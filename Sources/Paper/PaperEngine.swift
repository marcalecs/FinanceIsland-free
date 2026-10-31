import Foundation

@MainActor
final class PaperEngine: ObservableObject {
    struct Position: Equatable, Sendable {
        var symbol: String
        var asset: String
        var side: Signal
        var entry: Double
        var qty: Double
        var stop: Double
        var initialStop: Double
        var target: Double
        var risk: Double
        var fee: Double
        var openedAt: Date
        var mode: JournalEntry.Mode
        var mae = 0.0
        var mfe = 0.0
        var atBreakeven = false
        var stopMoved = false
        var checklist: (done: Int, total: Int)?

        static func == (a: Position, b: Position) -> Bool {
            a.symbol == b.symbol && a.side == b.side && a.entry == b.entry && a.qty == b.qty && a.stop == b.stop && a.target == b.target
                && a.openedAt == b.openedAt && a.mode == b.mode && a.mae == b.mae && a.mfe == b.mfe && a.atBreakeven == b.atBreakeven
                && a.checklist?.done == b.checklist?.done && a.checklist?.total == b.checklist?.total
        }
    }

    enum EntryBlock: Equatable, Sendable {
        case tilt(TiltGuard.Block)
        case proLimit
    }

    enum OpenResult: Equatable {
        case opened, blocked(EntryBlock), noPrice, alreadyOpen, tooSmall
    }

    @Published private(set) var position: Position?
    @Published private(set) var tick: BookTick?
    @Published private(set) var source: FeedSource = .connecting
    @Published var justClosed: JournalEntry?

    private(set) var symbol: String
    var fee = RiskCalculator.defaultFee
    var buffer = RiskCalculator.defaultBuffer
    var lotStep = 0.001
    var priceTick = 0.0
    private let record: (JournalEntry) -> Void
    private let entryBlock: () -> EntryBlock?
    private var feed: PaperFeed?
    private var watchers = 0
    var fallbackPrice: (() -> Double?)?
    var onSymbol: ((String) -> Void)?

    init(symbol: String = "BTCUSDT", record: @escaping (JournalEntry) -> Void, entryBlock: @escaping () -> EntryBlock?) {
        self.symbol = symbol
        self.record = record
        self.entryBlock = entryBlock
    }

    var asset: String { Self.asset(symbol) }
    static func asset(_ symbol: String) -> String { symbol.hasSuffix("USDT") ? String(symbol.dropLast(4)) : symbol }
    var mode: JournalEntry.Mode { source == .simulated ? .simulated : .paper }


    func retain() { watchers += 1; updateFeed() }
    func release() { watchers = max(0, watchers - 1); updateFeed() }

    func setSymbol(_ s: String) {
        guard s != symbol, position == nil else { return }
        symbol = s
        tick = nil
        stopFeed()
        updateFeed()
        onSymbol?(s)
    }

    private func updateFeed() {
        if watchers > 0 || position != nil { startFeed() } else { stopFeed() }
    }

    private func startFeed() {
        guard feed == nil else { return }
        source = .connecting
        let f = PaperFeed(symbol: symbol, fallbackPrice: tick?.mid ?? fallbackPrice?()) { [weak self] ticks, src in
            self?.handle(ticks, source: src)
        }
        feed = f
        Task { await f.start() }
    }

    private func stopFeed() {
        guard let f = feed else { return }
        feed = nil
        Task { await f.stop() }
    }


    func handle(_ ticks: [BookTick], source src: FeedSource) {
        if src != source {
            if var p = position {
                if src == .simulated, p.mode == .paper { p.mode = .simulated; position = p }
                else if src.isLive, p.mode == .simulated, tick != nil { finish(reason: .manual, level: nil) }
            }
            source = src
        }
        for t in ticks {
            tick = t
            guard var p = position else { continue }
            let px = p.side == .sell ? t.ask : t.bid
            let move = (p.side == .sell ? p.entry - px : px - p.entry) / abs(p.entry - p.initialStop)
            p.mae = max(p.mae, -move)
            p.mfe = max(p.mfe, move)
            position = p
            let stopHit = p.side == .sell ? px >= p.stop : px <= p.stop
            let targetHit = p.side == .sell ? px <= p.target : px >= p.target
            if stopHit { finish(reason: p.atBreakeven ? .breakeven : .stop, level: p.stop) }
            else if targetHit { finish(reason: .target, level: p.target) }
        }
        updateFeed()
    }


    var entryBlocked: EntryBlock? { entryBlock() }

    func plan(side: Signal, risk: Double, slPercent: Double, rr: Double) -> RiskCalculator.Plan? {
        guard let t = tick else { return nil }
        let entry = side == .sell ? t.bid : t.ask
        return RiskCalculator.plan(side: side, risk: risk, entry: entry, slPercent: slPercent, rr: rr, fee: fee, step: lotStep, tick: priceTick)
    }

    @discardableResult
    func open(side: Signal, risk: Double, slPercent: Double, rr: Double, checklist: (done: Int, total: Int)? = nil) -> OpenResult {
        guard let t = tick else { return .noPrice }
        if let p = position {
            if p.side == side { return .alreadyOpen }
            close(reason: .manual)
        }
        if let b = entryBlock() { return .blocked(b) }
        guard risk > 0, slPercent > 0, let plan = plan(side: side, risk: risk, slPercent: slPercent, rr: rr), plan.qty > 0 else { return .tooSmall }
        position = Position(symbol: symbol, asset: asset, side: side, entry: side == .sell ? t.bid : t.ask, qty: plan.qty, stop: plan.stop,
                            initialStop: plan.stop, target: plan.target, risk: plan.actualRisk, fee: fee, openedAt: t.time, mode: mode,
                            checklist: checklist)
        updateFeed()
        return .opened
    }

    var breakevenPrice: Double? {
        position.map { RiskCalculator.breakeven(side: $0.side, entry: $0.entry, fee: $0.fee, buffer: buffer) }
    }

    var canBreakeven: Bool {
        guard let p = position, let t = tick, let be = breakevenPrice, !p.atBreakeven else { return false }
        return p.side == .sell ? t.ask < be : t.bid > be
    }

    @discardableResult
    func moveStopToBreakeven() -> Bool {
        guard canBreakeven, var p = position, let be = breakevenPrice else { return false }
        p.stop = RiskCalculator.roundPrice(be, tick: priceTick)
        p.atBreakeven = true
        p.stopMoved = true
        position = p
        return true
    }

    func close(reason: JournalEntry.ExitReason = .manual) {
        guard position != nil, tick != nil else { return }
        finish(reason: reason, level: nil)
    }

    func panicClose() { close(reason: .panic) }

    func discard() {
        position = nil
        justClosed = nil
        updateFeed()
    }

    var unrealizedNet: Double? {
        guard let p = position, let t = tick else { return nil }
        return RiskCalculator.netPnL(side: p.side, entry: p.entry, exit: p.side == .sell ? t.ask : t.bid, qty: p.qty, fee: p.fee)
    }

    var unrealizedR: Double? {
        guard let n = unrealizedNet, let p = position else { return nil }
        return RiskCalculator.r(net: n, risk: p.risk)
    }

    private func finish(reason: JournalEntry.ExitReason, level: Double?) {
        guard let p = position, let t = tick else { return }
        let exit = p.side == .sell ? t.ask : t.bid
        var e = JournalEntry(asset: p.asset, kind: .trade, side: p.side, entry: p.entry, stop: p.stop, target: p.target, text: "")
        e.at = p.openedAt
        e.status = .closed
        e.exit = exit
        e.mode = p.mode
        e.qty = p.qty
        e.riskAmount = p.risk
        e.feeRate = p.fee
        e.grossPnL = RiskCalculator.grossPnL(side: p.side, entry: p.entry, exit: exit, qty: p.qty)
        e.commission = RiskCalculator.commission(entry: p.entry, exit: exit, qty: p.qty, fee: p.fee)
        e.netPnL = RiskCalculator.netPnL(side: p.side, entry: p.entry, exit: exit, qty: p.qty, fee: p.fee)
        e.openedAt = p.openedAt
        e.closedAt = t.time
        e.exitReason = reason
        if let level { e.slippage = p.side == .sell ? exit - level : level - exit }
        e.mae = p.mae
        e.mfe = p.mfe
        e.initialStop = p.initialStop
        e.stopMoved = p.stopMoved ? true : nil
        e.tags = ["paper"]
        e.checklistDone = p.checklist?.done
        e.checklistTotal = p.checklist?.total
        position = nil
        record(e)
        justClosed = e
    }
}
