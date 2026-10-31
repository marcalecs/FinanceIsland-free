import AppKit
import UserNotifications
import Combine
import SwiftUI

struct TradePrefsValues: Codable, Equatable {
    var risk = 10.0
    var slPercent = 0.5
    var rr = 2.0
    var symbol = "BTCUSDT"
    var feePercent = 0.04
    var bufferPercent = 0.008
    var tilt = TiltGuard.Settings()
    var setupTags = ["#Breakout", "#Sweep", "#Orderblock", "#Reversal"]
    var mistakeTags = ["#FOMO", "#Tilt", "#EarlyExit", "#MovedStop"]
    var keys: [String: String] = ["long": "l", "short": "s", "breakeven": "b", "close": "x"]
    var checklist: [String] = []
    var checklistForPaper = true
    var watchApps = ["Binance", "TradingView", "MetaTrader 5", "Bybit"]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TradePrefsValues()
        risk = (try? c.decode(Double.self, forKey: .risk)) ?? d.risk
        slPercent = (try? c.decode(Double.self, forKey: .slPercent)) ?? d.slPercent
        rr = (try? c.decode(Double.self, forKey: .rr)) ?? d.rr
        symbol = (try? c.decode(String.self, forKey: .symbol)) ?? d.symbol
        feePercent = (try? c.decode(Double.self, forKey: .feePercent)) ?? d.feePercent
        bufferPercent = (try? c.decode(Double.self, forKey: .bufferPercent)) ?? d.bufferPercent
        tilt = (try? c.decode(TiltGuard.Settings.self, forKey: .tilt)) ?? d.tilt
        setupTags = (try? c.decode([String].self, forKey: .setupTags)) ?? d.setupTags
        mistakeTags = (try? c.decode([String].self, forKey: .mistakeTags)) ?? d.mistakeTags
        keys = (try? c.decode([String: String].self, forKey: .keys)) ?? d.keys
        checklist = (try? c.decode([String].self, forKey: .checklist)) ?? d.checklist
        checklistForPaper = (try? c.decode(Bool.self, forKey: .checklistForPaper)) ?? d.checklistForPaper
        watchApps = (try? c.decode([String].self, forKey: .watchApps)) ?? d.watchApps
    }

    var activeChecklist: [String] { checklist.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

    var fee: Double { feePercent / 100 }
    var buffer: Double { bufferPercent / 100 }
}

@MainActor
final class TradePrefs: ObservableObject {
    static let shared = TradePrefs()
    private static let key = "tradePrefs"

    @Published var v: TradePrefsValues {
        didSet {
            guard v != oldValue else { return }
            if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: Self.key) }
            PaperEngine.shared.fee = v.fee
            PaperEngine.shared.buffer = v.buffer
        }
    }

    private init() {
        v = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(TradePrefsValues.self, from: $0) } ?? TradePrefsValues()
    }

    func reset() { v = TradePrefsValues() }
}

extension PaperEngine {
    static let symbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT", "XRPUSDT", "DOGEUSDT"]

    static let shared: PaperEngine = {
        let prefs = UserDefaults.standard.data(forKey: "tradePrefs").flatMap { try? JSONDecoder().decode(TradePrefsValues.self, from: $0) }
            ?? TradePrefsValues()
        let e = PaperEngine(symbol: prefs.symbol, record: { JournalStore.shared.record($0) }, entryBlock: { TradeDesk.entryBlock(paper: true) })
        e.fee = prefs.fee
        e.buffer = prefs.buffer
        e.onSymbol = { s in TradePrefs.shared.v.symbol = s; TradeDesk.shared.loadLot(s) }
        return e
    }()
}

@MainActor
final class TradeDesk: ObservableObject {
    static let shared = TradeDesk()

    struct Toast: Equatable {
        let id = UUID()
        let symbol: String
        let text: String
        let until: Date
    }

    @Published var pendingTag: UUID? {
        didSet { if pendingTag == nil, !tagQueue.isEmpty { pendingTag = tagQueue.removeFirst() } }
    }
    @Published private(set) var tagQueue: [UUID] = []

    func queueTags(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        tagQueue += ids
        if pendingTag == nil { pendingTag = tagQueue.removeFirst() }
    }

    func skipTags() {
        tagQueue = []
        pendingTag = nil
    }
    @Published private(set) var toast: Toast?
    @Published private(set) var manualPrices: [UUID: Double] = [:]
    @Published private(set) var hasPaper = false
    @Published private(set) var menuTitle = ""
    @Published var hotkeysActive = false
    @Published var checked: Set<Int> = []
    @Published private(set) var attention = 0
    private var appObservers: [NSObjectProtocol] = []
    private var guardTask: Task<Void, Never>?
    private var reminded: [String: Date] = [:]

    func checklistCounts(paper: Bool) -> (done: Int, total: Int)? {
        let list = TradePrefs.shared.v.activeChecklist
        guard !list.isEmpty, !paper || TradePrefs.shared.v.checklistForPaper else { return nil }
        return (checked.filter { $0 < list.count }.count, list.count)
    }

    var collapsedWidth: CGFloat? {
        if hasTrade { return 360 }
        if let t = toast { return min(520, max(300, CGFloat(t.text.count) * 7.2 + 60)) }
        if pendingTag != nil || MarketCalendar.shared.soon != nil { return 300 }
        return IdlePrefs.shared.v.tape ? 360 : nil
    }

    func hotkey(_ c: String) -> Bool {
        let v = TradePrefs.shared.v
        guard let action = v.keys.first(where: { $0.value == c && !c.isEmpty })?.key else { return false }
        switch action {
        case "long", "short":
            guard paper.entryBlocked == nil else { return true }
            if paper.open(side: action == "long" ? .buy : .sell, risk: v.risk, slPercent: v.slPercent, rr: v.rr,
                          checklist: checklistCounts(paper: true)) == .opened { checked = [] }
        case "breakeven": paper.moveStopToBreakeven()
        case "close": paper.close()
        default: return false
        }
        return true
    }

    private var settings: AppSettings?
    private weak var rates: RateStore?
    private var subs: Set<AnyCancellable> = []
    private var poller: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var notified: Set<String>

    private init() {
        notified = Set(UserDefaults.standard.stringArray(forKey: "tradeNotified") ?? [])
    }

    var paper: PaperEngine { .shared }
    var journal: JournalStore { .shared }

    var openManual: JournalEntry? {
        journal.entries.last { $0.kind == .trade && $0.status == .open && $0.tradeMode == .manual && $0.entry != nil && $0.stop != nil }
    }

    var hasTrade: Bool { hasPaper || openManual != nil }

    func start(settings: AppSettings, rates: RateStore) {
        self.settings = settings
        self.rates = rates
        let e = paper
        e.fallbackPrice = { [weak self] in self?.quote(PaperEngine.asset(e.symbol)) }
        loadLot(e.symbol)
        e.$position.map { $0 != nil }.removeDuplicates().sink { [weak self] v in self?.hasPaper = v }.store(in: &subs)
        e.$justClosed.compactMap { $0?.id }.sink { [weak self] id in self?.pendingTag = id }.store(in: &subs)
        e.objectWillChange.throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateTitle() } } }.store(in: &subs)
        journal.$entries.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.journalChanged() } }
        }.store(in: &subs)
        journalChanged()
        guardTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateAppWatch()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }


    private var pauseBlock: TiltGuard.Block? {
        guard case .tilt(let b)? = TradeDesk.entryBlock(paper: false), b.reason == .pause || b.reason == .dailyLoss else { return nil }
        return b
    }

    private func updateAppWatch() {
        let on = pauseBlock != nil
        if on, appObservers.isEmpty {
            let nc = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
                appObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] n in
                    let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    let id = app?.bundleIdentifier ?? "", name = app?.localizedName ?? ""
                    MainActor.assumeIsolated { self?.appOpened(bundleID: id, name: name) }
                })
            }
        } else if !on, !appObservers.isEmpty {
            appObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            appObservers = []
        }
    }

    static func matches(_ list: [String], bundleID: String, name: String) -> Bool {
        list.contains { item in
            let i = item.trimmingCharacters(in: .whitespaces).lowercased()
            return !i.isEmpty && (bundleID.lowercased() == i || name.lowercased().contains(i))
        }
    }

    private func appOpened(bundleID: String, name: String) {
        guard let b = pauseBlock, Self.matches(TradePrefs.shared.v.watchApps, bundleID: bundleID, name: name) else { return }
        if let t = reminded[name], Date().timeIntervalSince(t) < 600 { return }
        reminded[name] = Date()
        let reason = b.reason == .pause ? tr("a pause after a stop") : tr("the daily loss limit")
        post(tr("You're on a pause until \(Fmt.date(b.until, "HH:mm")). Reason: \(reason)"), symbol: "hand.raised.fill", seconds: 12)
        attention += 1
    }

    func loadLot(_ symbol: String) {
        Task {
            guard let lot = await ExchangeFilters.lot(symbol), PaperEngine.shared.symbol == symbol else { return }
            PaperEngine.shared.lotStep = lot.step
            PaperEngine.shared.priceTick = lot.tick
        }
    }

    static func entryBlock(paper: Bool, now: Date = Date()) -> PaperEngine.EntryBlock? {
        let entries = JournalStore.shared.entries
        if paper, let limit = ProFeature.limit(ProFeature.freePaperTradesPerMonth) {
            let cal = Calendar.current
            let month = entries.filter { $0.kind == .trade && $0.tradeMode != .manual && cal.isDate($0.opened, equalTo: now, toGranularity: .month) }
            if month.count >= limit { return .proLimit }
        }
        guard ProFeature.tiltGuard.isUnlocked, let b = TiltGuard.check(entries, TradePrefs.shared.v.tilt, now: now) else { return nil }
        return .tilt(b)
    }


    func post(_ text: String, symbol: String = "bell.fill", seconds: TimeInterval = 8) {
        let t = Toast(symbol: symbol, text: text, until: Date().addingTimeInterval(seconds))
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if self?.toast == t { self?.toast = nil }
        }
    }


    func quote(_ name: String) -> Double? {
        guard let settings, let s = HubSubject.find(name, settings) else { return nil }
        return price(s)
    }

    func subject(_ e: JournalEntry) -> HubSubject? {
        guard let settings else { return nil }
        return HubSubject.find(e.asset, settings) ?? e.itemID.flatMap { HubSubject.match(itemID: $0, settings) }
    }

    func price(_ s: HubSubject) -> Double? {
        if case .asset(let a) = s, let q = rates?.quote(a) { return q.price }
        return nil
    }

    func price(of e: JournalEntry) -> Double? {
        manualPrices[e.id] ?? subject(e).flatMap(price)
    }

    @discardableResult
    func openManual(asset: String, itemID: String?, side: Signal, stop: Double, target: Double?, price: Double) -> Bool {
        guard TradeDesk.entryBlock(paper: false) == nil, price > 0, stop > 0, stop != price,
              side == .sell ? stop > price : stop < price else { return false }
        let fee = TradePrefs.shared.v.fee
        let oneR = UserDefaults.standard.double(forKey: "journalOneR")
        var e = JournalEntry(asset: asset, itemID: itemID, kind: .trade, side: side, entry: price, stop: stop, target: target, text: "")
        e.mode = .manual
        e.openedAt = Date()
        e.initialStop = stop
        e.feeRate = fee
        if let c = checklistCounts(paper: false) { e.checklistDone = c.done; e.checklistTotal = c.total; checked = [] }
        if oneR > 0 {
            let q = RiskCalculator.roundDown(RiskCalculator.qty(risk: oneR, entry: price, stop: stop, fee: fee),
                                             step: RiskCalculator.manualStep(price: price))
            if q > 0 {
                e.qty = q
                e.riskAmount = RiskCalculator.riskAt(side: side, entry: price, stop: stop, qty: q, fee: fee)
            }
        }
        journal.add(e)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return true
    }

    func closeManual(_ e: JournalEntry) {
        guard let x = price(of: e) else { return }
        journal.close(e.id, exit: x, reason: .manual)
        pendingTag = e.id
    }

    private func journalChanged() {
        let open = journal.entries.filter { $0.kind == .trade && $0.status == .open && $0.tradeMode == .manual }
        if open.isEmpty { poller?.cancel(); poller = nil }
        else if poller == nil {
            poller = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.pollManual()
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                }
            }
        }
        updateTitle()
        objectWillChange.send()
    }

    private func pollManual() async {
        let open = journal.entries.filter { $0.kind == .trade && $0.status == .open && $0.tradeMode == .manual }
        for e in open {
            guard let s = subject(e) else { continue }
            var px = price(s)
            if px == nil, let r = try? await ChartFeed.candles(s, tf: .m1) { px = r.candles.last?.close }
            guard let p = px else { continue }
            manualPrices[e.id] = p
            checkLevels(e, price: p)
        }
        updateTitle()
    }

    private func checkLevels(_ e: JournalEntry, price p: Double) {
        let fmt = { (v: Double) in AssetFormat.price(v) }
        if let s = e.stop, e.side == .sell ? p >= s : p <= s, mark(e.id, "stop") {
            let title = tr("\(e.asset) reached your stop \(fmt(s))")
            AlertStore.shared.notify(id: e.id.uuidString + "-stop", title: title, body: tr("Now \(fmt(p)) · close the trade in the island"), thread: e.asset)
        }
        if let t = e.target, e.side == .sell ? p <= t : p >= t, mark(e.id, "target") {
            let title = tr("\(e.asset) reached your target \(fmt(t))")
            AlertStore.shared.notify(id: e.id.uuidString + "-target", title: title, body: tr("Now \(fmt(p)) · close the trade in the island"), thread: e.asset)
        }
    }

    private func mark(_ id: UUID, _ level: String) -> Bool {
        let k = id.uuidString + "|" + level
        guard !notified.contains(k) else { return false }
        notified.insert(k)
        UserDefaults.standard.set(Array(notified.suffix(200)), forKey: "tradeNotified")
        return true
    }


    private func updateTitle() {
        var t = ""
        if let p = paper.position, let r = paper.unrealizedR {
            t = p.asset + " " + String(format: "%+.2fR", r)
        } else if let e = openManual, let x = price(of: e) {
            t = e.asset + (Self.liveR(e, price: x).map { " " + String(format: "%+.2fR", $0) } ?? "")
        }
        if t != menuTitle { menuTitle = t }
    }

    static func liveNet(_ e: JournalEntry, price x: Double) -> Double? {
        guard let en = e.entry, let q = e.qty else { return nil }
        return RiskCalculator.netPnL(side: e.side, entry: en, exit: x, qty: q, fee: e.feeRate ?? 0)
    }

    static func liveR(_ e: JournalEntry, price x: Double) -> Double? {
        if let n = liveNet(e, price: x), let r = e.riskAmount, r > 0 { return n / r }
        guard let en = e.entry, let s = e.riskStop, en != s else { return nil }
        return (e.side == .sell ? en - x : x - en) / abs(en - s)
    }

    func eraseAll() {
        pendingTag = nil
        toast = nil
        manualPrices = [:]
        notified = []
        TradePrefs.shared.reset()
        paper.discard()
    }
}
