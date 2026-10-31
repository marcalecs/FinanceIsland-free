import AppKit
import SwiftUI

@MainActor
final class WalletPerps: ObservableObject {
    static let shared = WalletPerps()

    struct Problem: Identifiable, Equatable {
        let file: String
        let error: String
        let at: Date
        var id: String { file + "\(at.timeIntervalSince1970)" }
    }

    @Published private(set) var problems: [Problem] = []
    @Published private(set) var lastImport: Date?
    @Published private(set) var prices: [String: (price: Double, at: Date)] = [:]
    @Published var liquidationAlerts: Bool = UserDefaults.standard.bool(forKey: "walletLiquidationAlerts") {
        didSet { UserDefaults.standard.set(liquidationAlerts, forKey: "walletLiquidationAlerts") }
    }

    static let warnDistance = 0.10
    private var watcher: FolderWatcher?
    private var priceTask: Task<Void, Never>?

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinanceIsland/Inbox/wallet", isDirectory: true)
    }

    var open: [JournalEntry] {
        JournalStore.shared.entries.filter { $0.importedFrom == "wallet" && $0.kind == .trade && $0.status == .open }
    }

    func start() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        scan()
        watch()
        updatePrices()
    }

    func scan() {
        let errors = WalletInbox.process(folder: Self.folder) { export in
            let s = JournalStore.shared.applyWallet(export)
            if s.added + s.updated + s.closed > 0 { lastImport = Date() }
        }
        if !errors.isEmpty {
            problems = (errors.map { Problem(file: $0.file, error: $0.error, at: Date()) } + problems).prefix(5).map { $0 }
        }
        updatePrices()
    }

    func clearProblems() { problems = [] }

    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for url in panel.urls {
            let dest = Self.folder.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + url.lastPathComponent)
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        scan()
    }

    private func watch() {
        guard watcher == nil else { return }
        let w = FolderWatcher(url: Self.folder) { [weak self] in MainActor.assumeIsolated { self?.scan() } }
        w.start()
        watcher = w
    }


    func updatePrices() {
        if open.isEmpty { priceTask?.cancel(); priceTask = nil; return }
        guard priceTask == nil else { return }
        priceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.open.isEmpty else { break }
                for asset in Set(self.open.map(\.asset)) {
                    if let d = try? await HTTP.get("https://api.binance.com/api/v3/ticker/price?symbol=\(asset)USDT"),
                       let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let p = Double(j["price"] as? String ?? "") {
                        self.prices[asset] = (p, Date())
                    }
                }
                self.checkLiquidation()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
            self?.priceTask = nil
        }
    }

    func price(_ e: JournalEntry) -> Double? { prices[e.asset]?.price }

    static func livePnL(_ e: JournalEntry, price x: Double) -> Double? {
        guard let en = e.entry, let q = e.qty else { return nil }
        return (e.side == .sell ? en - x : x - en) * q - (e.fundingPaid ?? 0)
    }

    static func liquidationDistance(_ e: JournalEntry, price x: Double) -> Double? {
        guard let l = e.liquidationPrice, l > 0, x > 0 else { return nil }
        return e.side == .sell ? (l - x) / x : (x - l) / x
    }

    private func checkLiquidation() {
        guard liquidationAlerts else { return }
        let day = BenchmarkStore.dayKey(Date())
        var sent = Set(UserDefaults.standard.stringArray(forKey: "walletLiqSent") ?? []).filter { $0.hasSuffix(day) }
        for e in open {
            guard let x = price(e), let d = Self.liquidationDistance(e, price: x), d < Self.warnDistance,
                  let key = e.externalIDs?.first, !sent.contains(key + "|" + day) else { continue }
            sent.insert(key + "|" + day)
            AlertStore.shared.notify(id: "liq-" + key, title: tr("\(e.asset) Wallet position is \(Self.pct(d)) from liquidation"),
                                     body: tr("Liquidation at \(AssetFormat.price(e.liquidationPrice ?? 0)), now \(AssetFormat.price(x)). FinanceIsland only reads: act in Wallet if you want to."),
                                     thread: "wallet")
        }
        UserDefaults.standard.set(Array(sent), forKey: "walletLiqSent")
    }

    static func pct(_ d: Double) -> String { String(format: "%.1f%%", max(d, 0) * 100) }
}

@MainActor
struct WalletPerpsSection: View {
    @ObservedObject private var perps = WalletPerps.shared
    @ObservedObject private var journal = JournalStore.shared
    @Environment(\.look) private var look

    var body: some View {
        let list = perps.open
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Wallet · Perps").uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Rectangle().fill(look.theme.line).frame(height: 1) }
                        row(e)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
            }
            .onAppear { perps.updatePrices() }
        }
    }

    private func row(_ e: JournalEntry) -> some View {
        let px = perps.price(e)
        let pnl = px.flatMap { WalletPerps.livePnL(e, price: $0) }
        let dist = px.flatMap { WalletPerps.liquidationDistance(e, price: $0) }
        let near = (dist ?? 1) < WalletPerps.warnDistance
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ModeLabel(entry: e)
                Text(e.asset).font(.system(size: 13.5, weight: .bold))
                Text((e.side == .sell ? "SHORT" : "LONG") + (e.leverage.map { " ×" + String(format: "%g", $0) } ?? ""))
                    .font(.system(size: 11, weight: .heavy).monospacedDigit())
                    .foregroundStyle(e.side == .sell ? TradeColors.loss : TradeColors.profit)
                Spacer()
                if let pnl {
                    PnLBadge(money: pnl, r: nil, unit: e.currency ?? "USDT")
                } else if let s = e.syncedAt {
                    Text(tr("no live price · file of \(Fmt.date(s, "d MMM HH:mm"))")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
            HStack(spacing: 12) {
                Text(tr("entry") + " " + (e.entry.map(AssetFormat.price) ?? "—"))
                if let px { Text(tr("now") + " " + AssetFormat.price(px)) }
                if let l = e.liquidationPrice { Text(tr("liquidation") + " " + AssetFormat.price(l)) }
                if let dist {
                    HStack(spacing: 3) {
                        if near { Image(systemName: "exclamationmark.triangle.fill") }
                        Text(near ? tr("\(WalletPerps.pct(dist)) to liquidation · close") : tr("\(WalletPerps.pct(dist)) to liquidation"))
                    }
                    .foregroundStyle(near ? TradeColors.loss : .white.opacity(0.6))
                    .fontWeight(near ? .bold : .regular)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct WalletTradeForm: View {
    @State private var open = false
    @State private var contract = "BTC-USD-PERP"
    @State private var side: Signal = .buy
    @State private var leverage = "10"
    @State private var margin = ""
    @State private var entry = ""
    @State private var liquidation = ""
    @State private var tp = ""
    @State private var sl = ""
    @State private var problem: String?
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    ModeLabel(mode: .manual, imported: "wallet")
                    Text(tr("Add a Wallet trade")).font(.system(size: 13, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                HStack(spacing: 8) {
                    field("contract", $contract, 130)
                    PillPicker(options: [Signal.buy, .sell], selection: $side, label: { $0 == .sell ? "SHORT" : "LONG" }, minWidth: 50)
                    field("leverage", $leverage, 60)
                    field("margin", $margin, 80)
                }
                HStack(spacing: 8) {
                    field("entry", $entry, 90)
                    field("liquidation", $liquidation, 90)
                    field("take profit", $tp, 90)
                    field("stop loss", $sl, 90)
                    Spacer(minLength: 0)
                    Button(tr("Add"), action: add)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(look.accent.opacity(0.85)))
                }
                if let problem { Text(tr(problem)).font(.system(size: 11.5)).foregroundStyle(TradeColors.loss) }
                Text(tr("Wallet has no official read access, so FinanceIsland can't fetch this itself. Files from the Inbox update and close trades with the same id."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
    }

    private func num(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")).flatMap { $0 > 0 ? $0 : nil } }

    private func add() {
        guard let en = num(entry), let m = num(margin), let lev = num(leverage), !contract.isEmpty else {
            problem = "Contract, leverage, margin and entry are needed."
            return
        }
        let p = WalletInbox.Position(id: "manual-" + UUID().uuidString, contract: contract.uppercased(), side: side, closed: false,
                                     leverage: lev, margin: m, entry: en, exit: nil, qty: m * lev / en, liquidation: num(liquidation),
                                     funding: nil, fees: nil, realized: nil, takeProfit: num(tp), stopLoss: num(sl),
                                     openedAt: Date(), closedAt: nil)
        _ = JournalStore.shared.applyWallet(WalletInbox.Export(exportedAt: Date(), quote: "USDT", positions: [p]))
        WalletPerps.shared.updatePrices()
        problem = nil
        margin = ""; entry = ""; liquidation = ""; tp = ""; sl = ""
        open = false
    }

    private func field(_ placeholder: String, _ text: Binding<String>, _ width: CGFloat) -> some View {
        TextField(tr(placeholder), text: text)
            .textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 9).frame(width: width, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
    }
}

@MainActor
struct WalletAccountRow: View {
    @ObservedObject private var perps = WalletPerps.shared
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("W").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(Color(red: 0.2, green: 0.5, blue: 0.95)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("Wallet (Telegram)")).font(.system(size: 13.5, weight: .semibold))
                    Text(perps.lastImport.map { tr("Inbox · last update \(Fmt.date($0, "d MMM HH:mm"))") } ?? tr("Inbox · read-only, no sign-in"))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text(tr("\(perps.open.count) open")).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                PillButton(title: "Import file…") { perps.importFiles() }
                PillButton(title: "Open folder") { NSWorkspace.shared.open(WalletPerps.folder) }
            }
            Text(tr("Wallet has no official read-only API, so FinanceIsland never signs in to it. Wallet Perps positions come from JSON files you put in the Inbox folder. For the TON wallet in Wallet, add its address above."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(tr("Notify me near liquidation (under 10%)")).font(.system(size: 12.5))
                Spacer()
                Switch(isOn: $perps.liquidationAlerts)
            }
            ForEach(perps.problems) { p in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(look.trend.red)
                    Text(tr("\(p.file) moved to failed/: \(p.error)")).font(.system(size: 11.5)).foregroundStyle(look.trend.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !perps.problems.isEmpty {
                PillButton(title: "Clear") { perps.clearProblems() }
            }
        }
    }
}
