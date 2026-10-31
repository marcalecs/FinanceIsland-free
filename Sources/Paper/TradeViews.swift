import SwiftUI

enum TradeColors {
    static let profit = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    static let loss = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    static func pnl(_ v: Double) -> Color { v >= 0 ? profit : loss }
}

enum TradeFormat {
    static func money(_ v: Double, unit: String?) -> String {
        let s = (v >= 0 ? "+" : "−") + Fmt.number(abs(v), min: 2, max: 2)
        guard let unit else { return s }
        return unit == "USD" || unit == "USDT" ? (v >= 0 ? "+$" : "−$") + Fmt.number(abs(v), min: 2, max: 2) : s + " " + unit
    }

    static func r(_ v: Double) -> String { String(format: "%+.2fR", v) }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        if s < 60 { return tr("\(s) s") }
        if s < 3_600 { return tr("\(s / 60) min") }
        if s < 86_400 { return tr("\(s / 3_600) h \(s % 3_600 / 60) min") }
        return tr("\(s / 86_400) d \(s % 86_400 / 3_600) h")
    }

    static func unit(_ e: JournalEntry, base: String) -> String { e.currency ?? (e.tradeMode == .manual ? base : "USDT") }

    static func spoken(money: Double?, r: Double?, unit: String?) -> String {
        let v = r ?? money ?? 0
        var parts: [String] = []
        if let r { parts.append(Fmt.number(abs(r), min: 2, max: 2) + " R") }
        if let money { parts.append(Fmt.number(abs(money), min: 2, max: 2) + (unit.map { " " + $0 } ?? "")) }
        let amount = parts.joined(separator: ", ")
        return v >= 0 ? tr("profit \(amount)") : tr("loss \(amount)")
    }

    static func spokenMode(_ m: JournalEntry.Mode) -> String {
        switch m {
        case .manual: return tr("Manual trade")
        case .paper: return tr("Paper trade, no real money")
        case .simulated: return tr("Simulated trade on offline data, no real money")
        }
    }

    static func modeTitle(_ m: JournalEntry.Mode) -> String {
        switch m {
        case .manual: return "MANUAL"
        case .paper: return "PAPER"
        case .simulated: return "SIMULATED"
        }
    }

    static func source(_ s: FeedSource) -> String {
        switch s {
        case .connecting: return "Connecting…"
        case .futures: return "Binance futures"
        case .spot: return "Binance spot"
        case .simulated: return "Offline generator"
        }
    }

    static func block(_ b: PaperEngine.EntryBlock, now: Date) -> String {
        switch b {
        case .proLimit: return tr("Free plan: \(ProFeature.freePaperTradesPerMonth) paper trades a month")
        case .tilt(let t):
            let left = duration(t.until.timeIntervalSince(now))
            switch t.reason {
            case .dailyLoss: return tr("Tilt Guard: daily loss limit reached · new entries in \(left)")
            case .maxTrades: return tr("Tilt Guard: trade limit for today reached · new entries in \(left)")
            case .lossStreak: return tr("Tilt Guard: too many losing trades in a row · new entries in \(left)")
            case .pause: return tr("Tilt Guard: pause after a stop · new entries in \(left)")
            }
        }
    }
}

struct ModeLabel: View {
    let mode: JournalEntry.Mode
    var size: CGFloat = 9.5
    var imported: String? = nil

    init(mode: JournalEntry.Mode, size: CGFloat = 9.5, imported: String? = nil) {
        self.mode = mode
        self.size = size
        self.imported = imported
    }

    init(entry e: JournalEntry, size: CGFloat = 9.5) {
        self.init(mode: e.tradeMode, size: size, imported: e.importedFrom)
    }

    var body: some View {
        Text(imported.map { $0.uppercased() } ?? TradeFormat.modeTitle(mode))
            .font(.system(size: size, weight: .heavy).monospacedDigit())
            .tracking(0.6)
            .foregroundStyle(.white.opacity(mode == .manual ? 0.6 : 0.95))
            .padding(.horizontal, 5).frame(height: size + 6)
            .overlay(Capsule().strokeBorder(.white.opacity(mode == .simulated ? 0.9 : 0.45), lineWidth: 1))
            .fixedSize()
            .accessibilityLabel(imported != nil ? tr("Imported from Binance") : TradeFormat.spokenMode(mode))
    }
}

struct PnLBadge: View {
    let money: Double?
    let r: Double?
    let unit: String?
    var size: CGFloat = 11.5

    var body: some View {
        let v = r ?? money ?? 0
        HStack(spacing: 4) {
            if let money { Text(TradeFormat.money(money, unit: unit)) }
            if money != nil && r != nil { Text("·").opacity(0.6) }
            if let r { Text(TradeFormat.r(r)) }
        }
        .font(.system(size: size, weight: .bold).monospacedDigit())
        .foregroundStyle(TradeColors.pnl(v))
        .padding(.horizontal, 6).frame(height: size + 7)
        .background(Capsule().fill(TradeColors.pnl(v).opacity(0.16)))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TradeFormat.spoken(money: money, r: r, unit: unit))
    }
}

struct LevelBar: View {
    let entry: Double
    let stop: Double
    let target: Double?
    let price: Double?
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            let right = target ?? (entry + (entry - stop) * 2)
            let span = right - stop
            let f = { (v: Double) in CGFloat(span == 0 ? 0.5 : min(max((v - stop) / span, 0), 1)) }
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [TradeColors.loss.opacity(0.75), .white.opacity(0.25), TradeColors.profit.opacity(target == nil ? 0.25 : 0.75)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(height: height)
                Rectangle().fill(.white.opacity(0.7)).frame(width: 1.5, height: height + 4).offset(x: g.size.width * f(entry) - 0.75)
                if let price {
                    Circle().fill(.white).frame(width: height + 5, height: height + 5)
                        .offset(x: g.size.width * f(price) - (height + 5) / 2)
                        .animation(.easeOut(duration: 0.2), value: price)
                }
            }
            .frame(height: g.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("From stop to target"))
        .accessibilityValue(spokenPosition)
    }

    private var spokenPosition: String {
        guard let price else { return tr("no price yet") }
        let right = target ?? (entry + (entry - stop) * 2)
        let f = right == stop ? 0.5 : min(max((price - stop) / (right - stop), 0), 1)
        return tr("price \(AssetFormat.price(price)), \(Int((f * 100).rounded()))% of the way from the stop to the target")
    }
}

@MainActor
struct CollapsedTradeView: View {
    @ObservedObject var paper: PaperEngine
    @ObservedObject var desk: TradeDesk
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let p = paper.position {
            row(mode: p.mode, asset: p.asset, price: paper.tick.map { p.side == .sell ? $0.ask : $0.bid },
                money: paper.unrealizedNet, r: paper.unrealizedR, unit: "USDT", bar: nil)
        } else if let e = desk.openManual, let en = e.entry, let st = e.stop {
            let px = desk.price(of: e)
            row(mode: .manual, asset: e.asset, price: px, money: px.flatMap { TradeDesk.liveNet(e, price: $0) },
                r: px.flatMap { TradeDesk.liveR(e, price: $0) }, unit: settings.baseCurrency,
                bar: (en, st, e.target, px))
        }
    }

    private func row(mode: JournalEntry.Mode, asset: String, price: Double?, money: Double?, r: Double?, unit: String,
                     bar: (Double, Double, Double?, Double?)?) -> some View {
        HStack(spacing: 6) {
            ModeLabel(mode: mode, size: 8.5)
            Text(asset).font(.system(size: 12.5, weight: .bold))
            Text(price.map(AssetFormat.price) ?? "—")
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
            PnLBadge(money: money, r: r, unit: unit, size: 10.5)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TradeFormat.spokenMode(mode) + ", " + asset)
        .accessibilityValue((price.map { tr("price \(AssetFormat.price($0))") + ", " } ?? "") + TradeFormat.spoken(money: money, r: r, unit: unit))
        .accessibilityHint(tr("Opens the trade"))
        .overlay(alignment: .bottom) {
            if let b = bar {
                LevelBar(entry: b.0, stop: b.1, target: b.2, price: b.3, height: 2)
                    .frame(height: 7).padding(.horizontal, 14).padding(.bottom, 1)
            }
        }
    }
}

@MainActor
struct TradeDeskView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @ObservedObject var paper: PaperEngine = .shared
    @ObservedObject var desk: TradeDesk = .shared
    @ObservedObject var journal: JournalStore = .shared
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CircleIconButton(symbol: "chevron.left", label: "Back") { state.mode = settings.lastTab.mode }
                Text(tr("Trade desk")).font(.system(size: 17, weight: .bold))
                Spacer()
                PillLink(title: "Open the journal", symbol: "book.pages") {
                    settings.lastTab = .journal
                    state.mode = .journal
                }
            }
            .frame(height: 34)
            if paper.position != nil {
                PaperPositionCard(paper: paper, compact: true)
            } else if let e = desk.openManual {
                ManualTradeCard(entry: e, desk: desk, settings: settings)
            }
            if let id = desk.pendingTag, journal.entry(id) != nil {
                TagPopover(entryID: id, settings: settings)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !desk.hasTrade {
                QuickTradeForm(settings: settings, desk: desk)
                SmartEntryField(placeholder: "long BTC 67000 stop 66000 target 70000")
            }
            recent
            Spacer(minLength: 0)
            FooterNote(text: tr("Training and your own trades only: FinanceIsland never sends orders."))
        }
        .padding(.horizontal, Layout.gutter).padding(.top, 12).padding(.bottom, 16)
        .frame(width: Layout.pageW, height: Layout.pageH, alignment: .top)
        .animation(.easeOut(duration: 0.22), value: desk.pendingTag)
        .onAppear { paper.retain(); desk.hotkeysActive = true }
        .onDisappear { paper.release(); desk.hotkeysActive = false }
    }

    @ViewBuilder
    private var recent: some View {
        let list = journal.entries.filter { $0.kind == .trade && $0.status == .closed }
            .sorted { ($0.closedAt ?? $0.at) > ($1.closedAt ?? $1.at) }.prefix(5)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Recent trades")).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                ForEach(Array(list)) { e in
                    HStack(spacing: 8) {
                        ModeLabel(entry: e, size: 8.5)
                        Text(e.asset).font(.system(size: 12.5, weight: .semibold))
                        Text(e.side == .sell ? "SHORT" : "LONG").font(.system(size: 9.5, weight: .heavy))
                            .foregroundStyle(look.pnl(up: e.side != .sell).opacity(0.8))
                        Spacer()
                        Text(Fmt.date(e.closedAt ?? e.at, "d MMM HH:mm")).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                        Text(e.rMultiple.map(TradeFormat.r) ?? e.netPnL.map { String(format: "%+.2f", $0) } ?? "—")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(look.pnl(e.outcome ?? 0))
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .frame(height: 24)
                }
            }
            .padding(12)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
    }
}

@MainActor
struct PaperPositionCard: View {
    @ObservedObject var paper: PaperEngine
    var compact = false
    @Environment(\.look) private var look

    var body: some View {
        if let p = paper.position {
            let px = paper.tick.map { p.side == .sell ? $0.ask : $0.bid }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    ModeLabel(mode: p.mode)
                    Text(p.asset).font(.system(size: 14, weight: .bold))
                    SignalBadgeView(signal: p.side, size: 9.5)
                    Text(px.map(AssetFormat.price) ?? "—").font(.system(size: 14, weight: .semibold).monospacedDigit())
                    Spacer()
                    PnLBadge(money: paper.unrealizedNet, r: paper.unrealizedR, unit: "USDT", size: 12.5)
                }
                LevelBar(entry: p.entry, stop: p.stop, target: p.target, price: px).frame(height: 12)
                HStack(spacing: 12) {
                    pair("entry", AssetFormat.price(p.entry))
                    pair("stop", AssetFormat.price(p.stop))
                    pair("target", AssetFormat.price(p.target))
                    pair("volume", Fmt.number(p.qty, min: 0, max: 6))
                    if !compact { pair("MAE", String(format: "%.2fR", p.mae)); pair("MFE", String(format: "%.2fR", p.mfe)) }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 1)) { c in
                        Text(TradeFormat.duration(c.date.timeIntervalSince(p.openedAt)))
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .font(.system(size: 11).monospacedDigit())
                HStack(spacing: 8) {
                    TradeButton(title: "Breakeven", symbol: "equal.circle", key: TradePrefs.shared.v.keys["breakeven"]) { paper.moveStopToBreakeven() }
                        .disabled(!paper.canBreakeven).opacity(paper.canBreakeven ? 1 : 0.45)
                    TradeButton(title: "Close", symbol: "xmark.circle", key: TradePrefs.shared.v.keys["close"]) { paper.close() }
                    TradeButton(title: "Panic close", symbol: "exclamationmark.octagon", tint: TradeColors.loss) { paper.panicClose() }
                    Spacer()
                }
            }
            .padding(12)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
    }

    private func pair(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(tr(title)).foregroundStyle(.white.opacity(0.45))
            Text(value).fontWeight(.semibold)
        }
        .lineLimit(1).fixedSize()
    }
}

@MainActor
struct ManualTradeCard: View {
    let entry: JournalEntry
    @ObservedObject var desk: TradeDesk
    @ObservedObject var settings: AppSettings
    @State private var newStop = ""
    @State private var movingStop = false
    @Environment(\.look) private var look

    var body: some View {
        let px = desk.price(of: entry)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                ModeLabel(mode: .manual)
                Text(entry.asset).font(.system(size: 14, weight: .bold))
                SignalBadgeView(signal: entry.side, size: 9.5)
                Text(px.map(AssetFormat.price) ?? "—").font(.system(size: 14, weight: .semibold).monospacedDigit())
                Spacer()
                PnLBadge(money: px.flatMap { TradeDesk.liveNet(entry, price: $0) }, r: px.flatMap { TradeDesk.liveR(entry, price: $0) },
                         unit: settings.baseCurrency, size: 12.5)
            }
            if let en = entry.entry, let st = entry.stop {
                LevelBar(entry: en, stop: st, target: entry.target, price: px).frame(height: 12)
            }
            HStack(spacing: 12) {
                pair("entry", entry.entry.map(AssetFormat.price) ?? "—")
                pair("stop", entry.stop.map(AssetFormat.price) ?? "—")
                pair("target", entry.target.map(AssetFormat.price) ?? "—")
                if let q = entry.qty { pair("volume", Fmt.number(q, min: 0, max: 6)) }
                Spacer(minLength: 0)
                TimelineView(.periodic(from: .now, by: 1)) { c in
                    Text(TradeFormat.duration(c.date.timeIntervalSince(entry.opened)))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .font(.system(size: 11).monospacedDigit())
            HStack(spacing: 8) {
                TradeButton(title: "Close at market", symbol: "flag.checkered") { desk.closeManual(entry) }
                    .disabled(px == nil).opacity(px == nil ? 0.45 : 1)
                if movingStop {
                    TextField(tr("new stop"), text: $newStop)
                        .textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
                        .padding(.horizontal, 9).frame(width: 100, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                        .onSubmit(applyStop)
                    TradeButton(title: "Apply", symbol: "checkmark", action: applyStop)
                } else {
                    TradeButton(title: "Move stop", symbol: "arrow.left.and.right") {
                        newStop = entry.stop.map { String(format: "%g", $0) } ?? ""
                        movingStop = true
                    }
                }
                Spacer()
            }
            Text(tr("You'll get a notification when the price reaches your stop or target. Only you close the trade."))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
        }
        .padding(12)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
    }

    private func applyStop() {
        if let v = Double(newStop.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")), v > 0 {
            JournalStore.shared.moveStop(entry.id, to: v)
        }
        movingStop = false
    }

    private func pair(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(tr(title)).foregroundStyle(.white.opacity(0.45))
            Text(value).fontWeight(.semibold)
        }
        .lineLimit(1).fixedSize()
    }
}

@MainActor
struct QuickTradeForm: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var desk: TradeDesk
    @ObservedObject private var prefs = TradePrefs.shared
    @State private var subjectID: String?
    @State private var stop = ""
    @State private var target = ""
    @State private var problem: String?
    @Environment(\.look) private var look
    @AppStorage("journalOneR") private var oneR = 0.0

    private var subjects: [HubSubject] { HubSubject.all(settings).filter { desk.price($0) != nil } }
    private var subject: HubSubject? { subjects.first { $0.id == subjectID } ?? subjects.first }

    var body: some View {
        let price = subject.flatMap(desk.price)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("New trade")).font(.system(size: 14, weight: .bold))
                ModeLabel(mode: .manual)
                Spacer()
                Menu {
                    ForEach(subjects) { s in Button(s.short) { subjectID = s.id; prefill() } }
                } label: {
                    Text(subject?.short ?? "—").font(.system(size: 12.5, weight: .bold))
                }
                .menuStyle(.borderlessButton).fixedSize()
                Text(price.map(AssetFormat.price) ?? "—").font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            HStack(spacing: 8) {
                field("stop (required)", $stop)
                field("target (optional)", $target)
                if let price, let st = number(stop), oneR > 0 {
                    let q = RiskCalculator.roundDown(RiskCalculator.qty(risk: oneR, entry: price, stop: st, fee: prefs.v.fee),
                                                     step: RiskCalculator.manualStep(price: price))
                    Text(tr("1R = \(LongTermStore.money(oneR, settings.baseCurrency)) · volume \(Fmt.number(q, min: 0, max: 6))"))
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                } else if oneR <= 0 {
                    Text(tr("Set 1R in Settings ▸ Trading for the volume")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            if let price {
                HStack(spacing: 6) {
                    Text(tr("Stop")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    ForEach([1.0, 2.0, 3.0], id: \.self) { pct in
                        preset(String(format: "−%.0f%%", pct)) { stop = AssetFormat.price(price * (1 - pct / 100)).replacingOccurrences(of: ",", with: "") }
                    }
                    Text(tr("Target")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.leading, 6)
                    ForEach([1.5, 2.0, 3.0], id: \.self) { rr in
                        preset(String(format: "%gR", rr)) {
                            guard let st = number(stop), st != price else { return }
                            target = AssetFormat.price(price + (price - st) * rr).replacingOccurrences(of: ",", with: "")
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            ChecklistView(paper: false)
            if let b = TradeDesk.entryBlock(paper: false) { TiltBanner(block: b) }
            HStack(spacing: 8) {
                SideButton(side: .buy, key: nil) { open(.buy, price) }
                SideButton(side: .sell, key: nil) { open(.sell, price) }
                if let problem { Text(tr(problem)).font(.system(size: 11.5)).foregroundStyle(TradeColors.loss).lineLimit(2) }
                Spacer()
            }
            .disabled(price == nil || TradeDesk.entryBlock(paper: false) != nil)
        }
        .padding(12)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard let p = subject.flatMap(desk.price) else { return }
        stop = AssetFormat.price(p * (1 - prefs.v.slPercent / 100)).replacingOccurrences(of: ",", with: "")
        target = ""
        problem = nil
    }

    private func open(_ side: Signal, _ price: Double?) {
        guard let s = subject, let price, let st = number(stop) else { problem = "Set a stop first."; return }
        var stopValue = st
        if side == .sell, stopValue < price { stopValue = price + (price - stopValue) }
        guard side == .sell ? stopValue > price : stopValue < price else { problem = "The stop must be on the losing side of the price."; return }
        if desk.openManual(asset: s.code, itemID: s.item?.id, side: side, stop: stopValue, target: number(target), price: price) {
            problem = nil
        } else {
            problem = "The trade couldn't be opened."
        }
    }

    private func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")).flatMap { $0 > 0 ? $0 : nil }
    }

    private func preset(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 8).frame(height: 22)
                .background(Capsule().fill(look.theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(tr(placeholder), text: text)
            .textFieldStyle(.plain).font(.system(size: 12.5).monospacedDigit())
            .padding(.horizontal, 9).frame(width: 132, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
    }
}

struct TiltBanner: View {
    let block: PaperEngine.EntryBlock

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { c in
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                Text(TradeFormat.block(block, now: c.date)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TradeColors.loss.opacity(0.85)))
        }
    }
}

struct SideButton: View {
    let side: Signal
    let key: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let c = side == .sell ? TradeColors.loss : TradeColors.profit
        Button(action: action) {
            HStack(spacing: 5) {
                Text(side == .sell ? "SHORT" : "LONG").font(.system(size: 12.5, weight: .heavy).monospacedDigit())
                if let key, !key.isEmpty { Text(key.uppercased()).font(.system(size: 9.5, weight: .bold).monospacedDigit()).opacity(0.6) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).frame(height: 30)
            .background(Capsule().fill(c.opacity(enabled ? 0.9 : 0.3)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(side == .sell ? tr("Open a short trade") : tr("Open a long trade"))
        .accessibilityHint(key.map { $0.isEmpty ? "" : tr("Key \($0.uppercased())") } ?? "")
    }
}

struct TradeButton: View {
    let title: String
    let symbol: String
    var key: String? = nil
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Label(tr(title), systemImage: symbol)
                if let key, !key.isEmpty { Text(key.uppercased()).font(.system(size: 9.5, weight: .bold).monospacedDigit()).opacity(0.55) }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(tint ?? .white.opacity(0.85))
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill((tint ?? .white).opacity(tint == nil ? 0.09 : 0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(tr(title))
        .accessibilityHint(key.map { $0.isEmpty ? "" : tr("Key \($0.uppercased())") } ?? "")
    }
}

@MainActor
struct TagPopover: View {
    let entryID: UUID
    @ObservedObject var settings: AppSettings
    @ObservedObject private var journal = JournalStore.shared
    @ObservedObject private var prefs = TradePrefs.shared
    @State private var note = ""
    @State private var stop = ""
    @State private var left = TagPopover.lifetime
    @State private var hovering = false
    @FocusState private var noteFocused: Bool
    @Environment(\.look) private var look

    static let lifetime = 20.0

    var body: some View {
        let e = journal.entry(entryID)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if let e { ModeLabel(entry: e); Text(e.asset).font(.system(size: 13, weight: .bold)) }
                Text(tr("closed")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                if let e { PnLBadge(money: e.netPnL, r: e.rMultiple, unit: TradeFormat.unit(e, base: settings.baseCurrency)) }
                Spacer()
                if !TradeDesk.shared.tagQueue.isEmpty {
                    Button(tr("Skip the other \(TradeDesk.shared.tagQueue.count)")) { TradeDesk.shared.skipTags() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(look.accent)
                }
                Text(tr("\(Int(left.rounded(.up))) s")).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.4))
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
            }
            tags(prefs.v.setupTags, selected: e?.setupTag) { t in journal.tag(entryID, setup: e?.setupTag == t ? nil : t, mistake: e?.mistakeTag, note: e?.note) }
            tags(prefs.v.mistakeTags, selected: e?.mistakeTag, tint: TradeColors.loss) { t in
                journal.tag(entryID, setup: e?.setupTag, mistake: e?.mistakeTag == t ? nil : t, note: e?.note)
            }
            if let e, e.isImported, e.stop == nil {
                HStack(spacing: 8) {
                    TextField(tr("stop you had in mind, for R"), text: $stop)
                        .textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
                        .padding(.horizontal, 10).frame(width: 190, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
                        .focused($noteFocused)
                        .onSubmit(applyStop)
                    Button(tr("Set"), action: applyStop).buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(look.accent)
                    Text(tr("Without a stop the result is shown in money only.")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }
            }
            TextField(tr("Short note: what worked, what didn't"), text: $note)
                .textFieldStyle(.plain).font(.system(size: 12))
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
                .focused($noteFocused)
                .onChange(of: note) { _, v in let c = journal.entry(entryID); journal.tag(entryID, setup: c?.setupTag, mistake: c?.mistakeTag, note: v) }
                .onSubmit(dismiss)
        }
        .padding(12)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        .onHover { h in hovering = h; if !h { left = Self.lifetime } }
        .onChange(of: noteFocused) { _, f in if !f { left = Self.lifetime } }
        .onAppear { note = e?.note ?? ""; left = Self.lifetime }
        .onChange(of: entryID) { _, _ in note = journal.entry(entryID)?.note ?? ""; stop = ""; left = Self.lifetime }
        .task(id: entryID) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if hovering || noteFocused { continue }
                left -= 0.25
                if left <= 0 { dismiss(); return }
            }
        }
    }

    private func dismiss() {
        if TradeDesk.shared.pendingTag == entryID { TradeDesk.shared.pendingTag = nil }
    }

    private func applyStop() {
        if let v = Double(stop.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")), v > 0 {
            journal.setStop(entryID, v)
        }
        stop = ""
    }

    private func tags(_ list: [String], selected: String?, tint: Color? = nil, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(list, id: \.self) { t in
                let on = selected == t
                Button { pick(t) } label: {
                    Text(t).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(on ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(Capsule().fill(on ? (tint ?? look.accent).opacity(0.8) : look.theme.chip))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

@MainActor
struct ChecklistView: View {
    let paper: Bool
    @ObservedObject private var desk = TradeDesk.shared
    @ObservedObject private var prefs = TradePrefs.shared
    @Environment(\.look) private var look

    var body: some View {
        let list = prefs.v.activeChecklist
        if !list.isEmpty, !paper || prefs.v.checklistForPaper {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                    let on = desk.checked.contains(i)
                    Button {
                        if on { desk.checked.remove(i) } else { desk.checked.insert(i) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: on ? "checkmark.square.fill" : "square")
                                .foregroundStyle(on ? look.accent : .white.opacity(0.5))
                            Text(item).font(.system(size: 12)).foregroundStyle(.white.opacity(on ? 0.95 : 0.7)).lineLimit(1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item)
                    .accessibilityValue(on ? tr("ticked") : tr("not ticked"))
                }
                Text(tr("\(desk.checked.filter { $0 < list.count }.count) of \(list.count) · you can enter without every tick"))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
        }
    }
}
