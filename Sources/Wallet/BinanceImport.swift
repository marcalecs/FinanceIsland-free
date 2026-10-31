import Foundation
import SwiftUI

@MainActor
final class BinanceImporter: ObservableObject {
    static let shared = BinanceImporter()

    struct Summary: Equatable {
        var added = 0
        var duplicates = 0
        var stillOpen: [String] = []
        var unmatchedSells = 0
        var futuresRead = false
        var error: String?
    }

    @Published private(set) var running = false
    @Published private(set) var progress = ""
    @Published private(set) var last: Summary?

    static let quotes = ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "BTC", "ETH", "BNB", "EUR", "TRY", "BRL"]
    static let stable: Set<String> = ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "DAI", "USD"]
    static let pause: UInt64 = 400_000_000

    static func split(_ symbol: String) -> (base: String, quote: String) {
        for q in quotes where symbol.hasSuffix(q) && symbol.count > q.count { return (String(symbol.dropLast(q.count)), q) }
        return (symbol, "USDT")
    }

    static func normalize(_ pair: String) -> String? {
        let p = pair.uppercased().filter { $0.isLetter || $0.isNumber }
        guard !p.isEmpty else { return nil }
        return quotes.contains(where: { p.hasSuffix($0) && p.count > $0.count }) ? p : p + "USDT"
    }

    func symbols(pair: String?) -> [String] {
        if let pair, let p = Self.normalize(pair) { return [p] }
        var out = Set(PortfolioStore.shared.binanceHoldings.map(\.asset).filter { !Self.stable.contains($0) }.map { $0 + "USDT" })
        for e in JournalStore.shared.entries where e.importedFrom == "binance" {
            if let id = e.externalIDs?.first { let parts = id.split(separator: ":"); if parts.count > 2 { out.insert(String(parts[2])) } }
        }
        return out.sorted()
    }

    func run(days: Int, pair: String?) {
        guard !running, let key = AccountKeychain.get("binance.key"), let secret = AccountKeychain.get("binance.secret") else { return }
        running = true
        last = nil
        let list = symbols(pair: pair)
        let base = UserDefaults.standard.string(forKey: "baseCurrency") ?? "USD"
        Task {
            var summary = Summary()
            do {
                try await BinanceAccount.checkReadOnly(key: key, secret: secret)
                let to = Date(), from = to.addingTimeInterval(-Double(days) * 86_400)
                var fills: [TradeAssembler.Fill] = []
                for (i, s) in list.enumerated() {
                    progress = tr("Reading \(s) · \(i + 1) of \(list.count)")
                    fills += try await Self.spot(s, from: from, to: to, key: key, secret: secret)
                    if let f = try? await Self.futures(s, from: from, to: to, key: key, secret: secret) {
                        fills += f
                        summary.futuresRead = true
                    }
                }
                progress = tr("Building trades…")
                let prices = await Self.prices()
                let result = TradeAssembler.assemble(fills) { asset, amount, f in
                    let q = Self.split(f.symbol).quote
                    if asset == q { return amount }
                    if asset == Self.split(f.symbol).base { return amount * f.price }
                    if let p = prices[asset + q] { return amount * p }
                    if let p = prices[asset + "USDT"], let qu = Self.stable.contains(q) ? 1 : prices[q + "USDT"], qu > 0 { return amount * p / qu }
                    return nil
                }
                let usdPerBase = await LongTermStore.usdPer(base) ?? 1
                summary.stillOpen = result.stillOpen
                summary.unmatchedSells = result.unmatchedSells
                let known = Set(JournalStore.shared.entries.compactMap { $0.externalIDs?.last })
                var fresh: [JournalEntry] = []
                for t in result.trades {
                    guard let closing = t.fillIDs.last, !known.contains(closing) else { summary.duplicates += 1; continue }
                    let q = Self.split(t.symbol).quote
                    let usd = Self.stable.contains(q) ? 1 : (prices[q + "USDT"] ?? 0)
                    let k = usdPerBase > 0 ? usd / usdPerBase : 1
                    fresh.append(Self.entry(t, rate: k, currency: base))
                }
                summary.added = fresh.count
                if !fresh.isEmpty {
                    JournalStore.shared.importTrades(fresh)
                    TradeDesk.shared.queueTags(fresh.map(\.id))
                }
            } catch {
                summary.error = error.localizedDescription
            }
            last = summary
            progress = ""
            running = false
        }
    }

    static func entry(_ t: TradeAssembler.Trade, rate k: Double, currency: String) -> JournalEntry {
        var e = JournalEntry(asset: split(t.symbol).base, kind: .trade, side: t.side, entry: t.entry, text: "")
        e.at = t.openedAt
        e.status = .closed
        e.exit = t.exit
        e.mode = .manual
        e.qty = t.qty
        e.grossPnL = t.gross * k
        e.commission = t.commission * k
        e.netPnL = t.net * k
        e.currency = currency
        e.openedAt = t.openedAt
        e.closedAt = t.closedAt
        e.exitReason = .manual
        e.importedFrom = "binance"
        e.externalIDs = t.fillIDs
        if t.market == .futures { e.tags = ["futures"] }
        return e
    }

    private static func spot(_ symbol: String, from: Date, to: Date, key: String, secret: String) async throws -> [TradeAssembler.Fill] {
        var out: [TradeAssembler.Fill] = []
        var start = from
        while start < to {
            let end = min(start.addingTimeInterval(86_400 - 1), to)
            let extra = "symbol=\(symbol)&startTime=\(ms(start))&endTime=\(ms(end))&limit=1000"
            let list = try await BinanceAccount.signed("/api/v3/myTrades", key: key, secret: secret, extra: extra) as? [[String: Any]] ?? []
            out += list.compactMap { parse($0, symbol: symbol, market: .spot) }
            start = end.addingTimeInterval(0.001)
            try await Task.sleep(nanoseconds: pause)
        }
        return out
    }

    private static func futures(_ symbol: String, from: Date, to: Date, key: String, secret: String) async throws -> [TradeAssembler.Fill] {
        var out: [TradeAssembler.Fill] = []
        var start = from
        while start < to {
            let end = min(start.addingTimeInterval(7 * 86_400 - 1), to)
            let extra = "symbol=\(symbol)&startTime=\(ms(start))&endTime=\(ms(end))&limit=1000"
            let list = try await BinanceAccount.signed("/fapi/v1/userTrades", key: key, secret: secret, extra: extra,
                                                       host: "https://fapi.binance.com") as? [[String: Any]] ?? []
            out += list.compactMap { parse($0, symbol: symbol, market: .futures) }
            start = end.addingTimeInterval(0.001)
            try await Task.sleep(nanoseconds: pause / 4)
        }
        return out
    }

    private static func ms(_ d: Date) -> Int { Int(d.timeIntervalSince1970 * 1000) }

    private static func parse(_ j: [String: Any], symbol: String, market: TradeAssembler.Fill.Market) -> TradeAssembler.Fill? {
        func num(_ k: String) -> Double? { (j[k] as? NSNumber)?.doubleValue ?? Double(j[k] as? String ?? "") }
        guard let id = (j["id"] as? NSNumber)?.int64Value, let order = (j["orderId"] as? NSNumber)?.int64Value,
              let price = num("price"), let qty = num("qty"), let time = num("time") else { return nil }
        let buy = (j["isBuyer"] as? Bool) ?? (j["buyer"] as? Bool) ?? ((j["side"] as? String) == "BUY")
        return TradeAssembler.Fill(id: id, orderID: order, symbol: symbol, market: market, isBuy: buy, price: price, qty: qty,
                                   commission: num("commission") ?? 0, commissionAsset: j["commissionAsset"] as? String ?? "",
                                   time: Date(timeIntervalSince1970: time / 1000))
    }

    private static func prices() async -> [String: Double] {
        guard let d = try? await HTTP.get("https://api.binance.com/api/v3/ticker/price"),
              let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [:] }
        var out: [String: Double] = [:]
        for t in a { if let s = t["symbol"] as? String, let p = Double(t["price"] as? String ?? "") { out[s] = p } }
        return out
    }
}

@MainActor
struct BinanceImportCard: View {
    @ObservedObject private var importer = BinanceImporter.shared
    @ObservedObject private var portfolio = PortfolioStore.shared
    @AppStorage("binanceImportDays") private var days = 30
    @State private var pair = ""
    @State private var open = false
    @Environment(\.look) private var look

    var body: some View {
        if portfolio.binanceConnected {
            VStack(alignment: .leading, spacing: 10) {
                Button { withAnimation(.easeOut(duration: 0.18)) { open.toggle() } } label: {
                    HStack(spacing: 8) {
                        ModeLabel(mode: .manual, imported: "binance")
                        Text(tr("Import trades from Binance")).font(.system(size: 13, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if open {
                    HStack(spacing: 8) {
                        PillPicker(options: [7, 30, 90], selection: $days, label: { tr("\($0) days") }, minWidth: 54)
                        TextField(tr("pair, e.g. BTCUSDT (empty: all)"), text: $pair)
                            .textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
                            .padding(.horizontal, 10).frame(width: 210, height: 28)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
                        Spacer()
                        Button(tr(importer.running ? "Importing…" : "Import")) { importer.run(days: days, pair: pair.isEmpty ? nil : pair) }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(Capsule().fill(look.accent.opacity(0.85)))
                            .disabled(importer.running)
                    }
                    if !importer.progress.isEmpty {
                        Text(importer.progress).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                    }
                    if let r = importer.last { result(r) }
                    Text(tr("Uses your read-only key: filled trades are read, nothing is sent. Pairs: your Binance balances and pairs imported before. Trades have no stop, so results show in money until you add one. A backup is made first."))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
    }

    @ViewBuilder
    private func result(_ r: BinanceImporter.Summary) -> some View {
        if let e = r.error {
            Text(tr(e)).font(.system(size: 11.5)).foregroundStyle(TradeColors.loss).fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("Added \(r.added) trades · \(r.duplicates) already in the journal"))
                    .font(.system(size: 12, weight: .semibold))
                if !r.stillOpen.isEmpty {
                    Text(tr("Still open, imported once closed: \(r.stillOpen.joined(separator: ", "))"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                if r.unmatchedSells > 0 {
                    Text(tr("\(r.unmatchedSells) sells had no buy in this period and were left out"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                if !r.futuresRead {
                    Text(tr("Futures weren't read: a read-only key usually has no futures access."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}
