import Foundation

struct ManualPosition: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var symbol: String
    var crypto: Bool
    var amount: Double
    var entry: Double?
    var entryDate: Date?
    var entryFX: [String: Double]?
}

struct LongTermSnapshot: Codable, Equatable {
    var manual: [ManualPosition]
    var entries: [String: Double]
    var entryDates: [String: Date]
    var entryFX: [String: [String: Double]]
}

struct Holding: Identifiable, Sendable {
    enum Origin: String, Sendable { case manual = "Manual", wallet = "Wallet", binance = "Binance" }
    let id: String
    let symbol: String
    let crypto: Bool
    let amount: Double
    let origin: Origin
    let label: String
}

struct DailyTrend: Sendable {
    let score: Double
    let direction: Signal

    static func of(_ m: ProbabilityModel) -> DailyTrend {
        let v = m.closes.map(\.value)
        guard v.count > 21 else { return DailyTrend(score: 0, direction: .hold) }
        let score = max(-3, min(3, log(m.price / v[v.count - 21]) / (m.sigmaLong * sqrt(20))))
        let above = m.sma50Series.last.flatMap { $0 }.map { m.price >= $0 } ?? (score > 0)
        let dir: Signal = score > 0.5 && above ? .buy : score < -0.5 && !above ? .sell : .hold
        return DailyTrend(score: score, direction: dir)
    }
}

struct LongTermAdvice: Sendable {
    enum Action: String, Sendable { case buy, hold, sell }
    let action: Action
    let rule: String
    let reason: String
}

@MainActor
final class LongTermStore: ObservableObject {
    static let shared = LongTermStore()

    @Published var manual: [ManualPosition] = [] { didSet { save() } }
    @Published var entries: [String: Double] = [:] { didSet { save() } }
    @Published private(set) var prices: [String: Double] = [:]
    @Published private(set) var trend: [String: DailyTrend] = [:]
    @Published private(set) var dailySigma: [String: Double] = [:]
    @Published private(set) var change24h: [String: Double] = [:]
    @Published var entryDates: [String: Date] = [:] { didSet { save() } }
    @Published private(set) var entryFXs: [String: [String: Double]] = [:] { didSet { save() } }
    @Published private(set) var lastRemoved: Removed?
    private var lastSaved: Data?
    private var restoring = false
    private var base = "USD"

    struct Removed: Equatable {
        let holdingID: String
        let position: ManualPosition?
        let index: Int?
        let entry: Double?
        let entryDate: Date?
        let fx: [String: Double]?
        let at: Date
    }
    @Published private(set) var history: [String: [Double]] = [:]
    @Published private(set) var quotes: [String: (price: Double, change: Double?, currency: String)] = [:]
    @Published private(set) var currencies: [String: String] = [:]
    @Published private(set) var fx: [String: Double] = ["USD": 1]
    private var fxUpdated: Date?
    @Published private(set) var loading = false
    @Published private(set) var updated: Date?

    private init() {
        let d = UserDefaults.standard
        if let m = d.data(forKey: "ltManual"), let v = try? JSONDecoder().decode([ManualPosition].self, from: m) { manual = v }
        entries = d.dictionary(forKey: "ltEntries") as? [String: Double] ?? [:]
        entryDates = (d.dictionary(forKey: "ltEntryDates") as? [String: Double] ?? [:]).mapValues { Date(timeIntervalSince1970: $0) }
        entryFXs = d.dictionary(forKey: "ltEntryFX") as? [String: [String: Double]] ?? [:]
        lastSaved = try? DataVault.encoder.encode(snapshot)
        if let launch = lastSaved, !manual.isEmpty || !entries.isEmpty { DataVault.backup("longterm", launch, force: true) }
        repairSymbols()
    }

    var snapshot: LongTermSnapshot {
        LongTermSnapshot(manual: manual, entries: entries, entryDates: entryDates, entryFX: entryFXs)
    }

    func restore(_ s: LongTermSnapshot) {
        restoring = true
        manual = s.manual
        entries = s.entries
        entryDates = s.entryDates
        entryFXs = s.entryFX
        lastRemoved = nil
        history = [:]
        restoring = false
        save()
    }

    private func repairSymbols() {
        var changed = false
        for i in manual.indices {
            let n = SearchCatalog.normalize(manual[i].symbol)
            guard let c = SearchCatalog.items.first(where: { c in
                SearchCatalog.normalize(c.name) == n || c.aliases.map(SearchCatalog.normalize).contains(n)
                    || SearchCatalog.normalize(c.symbol) == n
            }) else { continue }
            let crypto = c.kind == .crypto
            if manual[i].symbol != c.symbol || manual[i].crypto != crypto {
                manual[i].symbol = c.symbol
                manual[i].crypto = crypto
                changed = true
            }
        }
        if changed { save() }
    }

    private func save() {
        guard !restoring else { return }
        if let data = try? DataVault.encoder.encode(snapshot), data != lastSaved {
            if let previous = lastSaved { DataVault.backup("longterm", previous) }
            lastSaved = data
        }
        if let m = try? JSONEncoder().encode(manual) { UserDefaults.standard.set(m, forKey: "ltManual") }
        UserDefaults.standard.set(entries, forKey: "ltEntries")
        UserDefaults.standard.set(entryDates.mapValues(\.timeIntervalSince1970), forKey: "ltEntryDates")
        UserDefaults.standard.set(entryFXs, forKey: "ltEntryFX")
    }

    func holdings(settings: AppSettings, rates: RateStore) -> [Holding] {
        let p = PortfolioStore.shared
        var out: [Holding] = []
        if settings.walletAddress != nil, let b = rates.ethBalance, b > 0 {
            out.append(Holding(id: "main", symbol: "ETH", crypto: true, amount: b, origin: .wallet, label: tr("Main wallet")))
        }
        for w in p.wallets {
            if let b = p.balances[w.id], b > 0 {
                out.append(Holding(id: "w:" + w.id.uuidString, symbol: w.chain.symbol, crypto: true, amount: b, origin: .wallet, label: w.label))
            }
            for t in p.tokens[w.id] ?? [] {
                out.append(Holding(id: "t:" + w.id.uuidString + ":" + t.symbol, symbol: TokenScanner.priceSymbol[t.symbol] ?? t.symbol,
                                   crypto: true, amount: t.amount, origin: .wallet, label: w.label + " · " + t.symbol))
            }
        }
        for h in p.binanceHoldings where (h.usd ?? 0) >= 1 {
            out.append(Holding(id: "b:" + h.asset, symbol: h.asset, crypto: true, amount: h.amount, origin: .binance, label: "Binance"))
        }
        for m in manual {
            out.append(Holding(id: "m:" + m.id.uuidString, symbol: m.symbol, crypto: m.crypto, amount: m.amount, origin: .manual,
                               label: ItemNames.name(m.symbol) ?? m.symbol))
        }
        return out
    }

    func entry(for h: Holding) -> Double? {
        if h.origin == .manual, let m = manual.first(where: { "m:" + $0.id.uuidString == h.id }) { return m.entry }
        return entries[h.id]
    }

    func setEntry(_ v: Double?, for h: Holding) {
        if h.origin == .manual, let i = manual.firstIndex(where: { "m:" + $0.id.uuidString == h.id }) {
            manual[i].entry = v
        } else {
            entries[h.id] = v
        }
        if v != nil { captureEntryFX(id: h.id, symbol: h.symbol, crypto: h.crypto, date: entryDate(for: h) ?? Date()) }
    }

    func entryFX(for h: Holding) -> [String: Double]? {
        if h.origin == .manual, let m = manual.first(where: { "m:" + $0.id.uuidString == h.id }) { return m.entryFX }
        return entryFXs[h.id]
    }

    private func setEntryFX(_ fx: [String: Double], id: String) {
        if id.hasPrefix("m:"), let i = manual.firstIndex(where: { "m:" + $0.id.uuidString == id }) {
            manual[i].entryFX = fx
        } else {
            entryFXs[id] = fx
        }
    }

    func captureEntryFX(id: String, symbol: String, crypto: Bool, date: Date) {
        let base = self.base
        let known = currencies[symbol]
        Task {
            var cur = known ?? (crypto ? "USD" : "")
            if cur.isEmpty {
                let r = try? await MarketData.series(WatchItem(source: .yahoo, symbol: symbol), interval: "1d")
                cur = r.map { $0.quote.currency.isEmpty ? "USD" : $0.quote.currency } ?? "USD"
            }
            var fx: [String: Double] = [:]
            for c in Set([cur, base]) { if let v = await Self.usdPerAt(c, date) { fx[c] = v } }
            if !fx.isEmpty { setEntryFX(fx, id: id) }
        }
    }

    static func usdPerAt(_ cur: String, _ date: Date) async -> Double? {
        switch cur {
        case "USD", "USDT", "USDC": return 1
        case "GBp", "GBX": return await usdPerAt("GBP", date).map { $0 / 100 }
        case "ZAc": return await usdPerAt("ZAR", date).map { $0 / 100 }
        case "ILA": return await usdPerAt("ILS", date).map { $0 / 100 }
        default:
            if Date().timeIntervalSince(date) < 2 * 86_400 { return await usdPer(cur) }
            let pts = await yahoo(cur + "USD=X", from: date.addingTimeInterval(-7 * 86_400), to: date.addingTimeInterval(86_400), interval: "1d")
            return pts.last(where: { $0.time <= date })?.value ?? pts.first?.value
        }
    }

    struct PnL {
        let cost: Double
        let local: Double
        let total: Double
        var fx: Double { total - local }
        let approx: Bool
    }

    func pnl(_ h: Holding, base: String) -> PnL? {
        guard let e = entry(for: h), e > 0, let p = prices[h.symbol] else { return nil }
        let cur = currency(h.symbol)
        if cur == base { return PnL(cost: e * h.amount, local: (p - e) * h.amount, total: (p - e) * h.amount, approx: false) }
        guard let nowA = fx[cur], let nowB = fx[base], nowB > 0 else { return nil }
        let now = nowA / nowB
        var then = now, approx = true
        if let saved = entryFX(for: h), let a = saved[cur], let b = saved[base], b > 0 { then = a / b; approx = false }
        return PnL(cost: e * h.amount * then, local: (p - e) * h.amount * then,
                   total: p * h.amount * now - e * h.amount * then, approx: approx)
    }

    func entryDate(for h: Holding) -> Date? {
        if h.origin == .manual, let m = manual.first(where: { "m:" + $0.id.uuidString == h.id }) { return m.entryDate }
        return entryDates[h.id]
    }

    func setEntryDate(_ d: Date?, for h: Holding) {
        if h.origin == .manual, let i = manual.firstIndex(where: { "m:" + $0.id.uuidString == h.id }) {
            manual[i].entryDate = d
        } else {
            entryDates[h.id] = d
        }
        history[h.id] = nil
        loadHistory(h)
        if let d, entry(for: h) != nil { captureEntryFX(id: h.id, symbol: h.symbol, crypto: h.crypto, date: d) }
    }

    func add(symbol: String, crypto: Bool, amount: Double, entry: Double?, date: Date? = nil) {
        let p = ManualPosition(symbol: symbol.uppercased(), crypto: crypto, amount: amount, entry: entry, entryDate: date)
        manual.append(p)
        if entry != nil { captureEntryFX(id: "m:" + p.id.uuidString, symbol: p.symbol, crypto: crypto, date: date ?? Date()) }
    }

    func remove(_ h: Holding) {
        let i = manual.firstIndex { "m:" + $0.id.uuidString == h.id }
        let r = Removed(holdingID: h.id, position: i.map { manual[$0] }, index: i, entry: entries[h.id],
                        entryDate: entryDates[h.id], fx: entryFXs[h.id], at: Date())
        if let i { manual.remove(at: i) }
        entries[h.id] = nil
        lastRemoved = r
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if lastRemoved == r { lastRemoved = nil }
        }
    }

    func undoRemove() {
        guard let r = lastRemoved else { return }
        if let p = r.position, !manual.contains(where: { $0.id == p.id }) { manual.insert(p, at: min(r.index ?? manual.count, manual.count)) }
        if let e = r.entry { entries[r.holdingID] = e }
        if let d = r.entryDate { entryDates[r.holdingID] = d }
        if let fx = r.fx { entryFXs[r.holdingID] = fx }
        lastRemoved = nil
    }

    func currency(_ symbol: String) -> String { currencies[symbol] ?? "USD" }

    func toUSD(_ v: Double, _ cur: String) -> Double? { fx[cur].map { v * $0 } }

    func fromUSD(_ v: Double, to cur: String) -> Double? { fx[cur].flatMap { $0 > 0 ? v / $0 : nil } }

    func valueUSD(_ h: Holding) -> Double? { prices[h.symbol].flatMap { toUSD($0 * h.amount, currency(h.symbol)) } }

    static func money(_ v: Double, _ cur: String) -> String {
        let n = Fmt.number(v, min: 2, max: abs(v) >= 100 ? 2 : abs(v) >= 1 ? 2 : 6)
        switch cur {
        case "USD": return "$" + n
        case "EUR": return "€" + n
        case "GBP": return "£" + n
        case "GBp", "GBX": return n + " p"
        default: return n + " " + Catalog.symbol(cur)
        }
    }

    static func usdPer(_ cur: String) async -> Double? {
        switch cur {
        case "USD", "USDT", "USDC": return 1
        case "GBp", "GBX": return await usdPer("GBP").map { $0 / 100 }
        case "ZAc": return await usdPer("ZAR").map { $0 / 100 }
        case "ILA": return await usdPer("ILS").map { $0 / 100 }
        default:
            guard let r = try? await MarketData.series(WatchItem(source: .yahoo, symbol: cur + "USD=X"), interval: "1d"),
                  r.quote.price > 0 else { return nil }
            return r.quote.price
        }
    }

    private func loadFX(_ wanted: Set<String>) async {
        let stale = fxUpdated.map { Date().timeIntervalSince($0) > 600 } ?? true
        let todo = wanted.filter { stale || fx[$0] == nil }
        guard !todo.isEmpty else { return }
        await withTaskGroup(of: (String, Double?).self) { g in
            for c in todo { g.addTask { (c, await Self.usdPer(c)) } }
            for await (c, r) in g { if let r { fx[c] = r } }
        }
        if stale { fxUpdated = Date() }
    }


    func refresh(_ holdings: [Holding], base: String = "USD") {
        self.base = base
        loading = true
        let symbols = Dictionary(holdings.map { ($0.symbol, $0.crypto) }, uniquingKeysWith: { a, _ in a })
        Task {
            await withTaskGroup(of: (String, Double?, DailyTrend?, String).self) { g in
                for (sym, crypto) in symbols {
                    g.addTask {
                        let stable: Set<String> = ["USDT", "USDC", "FDUSD", "DAI", "BUSD", "TUSD"]
                        if stable.contains(sym) { return (sym, 1, nil, "USD") }
                        let item = crypto ? WatchItem(source: .binance, symbol: sym + "USDT") : WatchItem(source: .yahoo, symbol: sym)
                        guard let r = try? await MarketData.series(item, interval: "1d") else { return (sym, nil, nil, crypto ? "USD" : "") }
                        let m = ProbabilityModel(points: r.candles.suffix(400).map { PricePoint(time: $0.openTime, value: $0.close) },
                                                 source: r.source, price: r.quote.price, crypto: crypto)
                        let mo = m.map(DailyTrend.of)
                        if let m { await MainActor.run { LongTermStore.shared.dailySigma[sym] = m.sigmaNow } }
                        if let c = r.quote.change24h { await MainActor.run { LongTermStore.shared.change24h[sym] = c } }
                        let cur = crypto ? "USD" : (r.quote.currency.isEmpty ? "USD" : r.quote.currency)
                        return (sym, r.quote.price, mo, cur)
                    }
                }
                for await (sym, price, mo, cur) in g {
                    if let price { prices[sym] = price }
                    if let mo { trend[sym] = mo }
                    if !cur.isEmpty { currencies[sym] = cur }
                }
            }
            await loadFX(Set(symbols.keys.map { currency($0) }).union([base]))
            updated = Date()
            loading = false
            for h in holdings where entryDate(for: h) != nil && history[h.id] == nil { loadHistory(h) }
        }
    }

    func loadHistory(_ h: Holding) {
        guard let from = entryDate(for: h) else { return }
        let sym = h.symbol, crypto = h.crypto, id = h.id
        Task {
            let v = await Self.prices(symbol: sym, crypto: crypto, from: from)
            if !v.isEmpty { history[id] = v }
        }
    }

    func loadQuote(_ c: CatalogItem) {
        let key = c.id
        guard quotes[key] == nil else { return }
        quotes[key] = (0, nil, "USD")
        Task {
            if c.kind == .crypto, let j = try? await Chain.json("https://api.binance.com/api/v3/ticker/24hr?symbol=\(c.symbol)USDT"),
               let p = Double(j["lastPrice"] as? String ?? "") {
                quotes[key] = (p, Double(j["priceChangePercent"] as? String ?? ""), "USD")
            } else if c.kind != .crypto, let r = try? await MarketData.series(WatchItem(source: .yahoo, symbol: c.symbol), interval: "1d") {
                let cur = r.quote.currency.isEmpty ? "USD" : r.quote.currency
                quotes[key] = (r.quote.price, r.quote.change24h, cur)
                await loadFX([cur])
            } else {
                quotes[key] = nil
            }
        }
    }

    static func historicalPrice(symbol: String, crypto: Bool, at t: Date) async -> Double? {
        let ms = Int(t.timeIntervalSince1970 * 1000)
        if crypto {
            guard let u = URL(string: "https://api.binance.com/api/v3/klines?symbol=\(symbol)USDT&interval=1m&startTime=\(ms)&limit=1"),
                  let (d, _) = try? await URLSession.shared.data(from: u),
                  let a = try? JSONSerialization.jsonObject(with: d) as? [[Any]], let k = a.first,
                  k.count > 1, let o = Double(k[1] as? String ?? "") else { return nil }
            return o
        }
        let recent = Date().timeIntervalSince(t) < 700 * 86_400
        let pts = await yahoo(symbol, from: t.addingTimeInterval(recent ? -3 * 86_400 : -10 * 86_400),
                              to: t.addingTimeInterval(recent ? 3 * 3600 : 86_400), interval: recent ? "60m" : "1d")
        if let p = pts.last(where: { $0.time <= t })?.value ?? pts.first?.value { return p }
        let hourly = Date().timeIntervalSince(t) < 170 * 86_400
        for iv in hourly ? ["1h", "1d"] : ["1d"] {
            if let r = try? await MarketData.series(WatchItem(source: .yahoo, symbol: symbol), interval: iv), !r.candles.isEmpty {
                if let c = r.candles.last(where: { $0.openTime <= t }) { return c.close }
                if let first = r.candles.first, first.openTime > t, iv == "1d" { return first.close }
            }
        }
        return nil
    }

    static func prices(symbol: String, crypto: Bool, from: Date) async -> [Double] {
        let span = Date().timeIntervalSince(from)
        if crypto {
            let iv = span <= 2 * 86_400 ? "15m" : span <= 14 * 86_400 ? "1h" : span <= 120 * 86_400 ? "4h" : "1d"
            let ms = Int(from.timeIntervalSince1970 * 1000)
            guard let u = URL(string: "https://api.binance.com/api/v3/klines?symbol=\(symbol)USDT&interval=\(iv)&startTime=\(ms)&limit=1000"),
                  let (d, _) = try? await URLSession.shared.data(from: u),
                  let a = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { return [] }
            let closes = a.compactMap { $0.count > 4 ? Double($0[4] as? String ?? "") : nil }
            return thin(closes)
        }
        let iv = span <= 55 * 86_400 ? "60m" : "1d"
        return thin(await yahoo(symbol, from: from, to: Date(), interval: iv).map(\.value))
    }

    private static func thin(_ v: [Double]) -> [Double] {
        guard v.count > 150 else { return v }
        let step = Double(v.count - 1) / 149
        return (0..<150).map { v[Int((Double($0) * step).rounded())] }
    }

    private static func yahoo(_ symbol: String, from: Date, to: Date, interval: String) async -> [PricePoint] {
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let u = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?period1=\(Int(from.timeIntervalSince1970))&period2=\(Int(to.timeIntervalSince1970))&interval=\(interval)") else { return [] }
        guard let d = try? await HTTP.get(u, timeout: 12),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let res = ((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let ts = res["timestamp"] as? [Double],
              let q = ((res["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first,
              let closes = q["close"] as? [Any] else { return [] }
        return zip(ts, closes).compactMap { t, c in (c as? Double).map { PricePoint(time: Date(timeIntervalSince1970: t), value: $0) } }
    }

    func advice(for h: Holding) -> LongTermAdvice? {
        guard let price = prices[h.symbol] else { return nil }
        let mo = trend[h.symbol]
        let score = mo?.score ?? 0
        let falling = mo?.direction == .sell, rising = mo?.direction == .buy
        let m = String(format: "%+.1f", score)
        guard let e = entry(for: h), e > 0 else {
            if rising { return .init(action: .buy, rule: "Daily uptrend", reason: "Daily momentum \(m). Set your entry price to check your rules on this position.") }
            if falling { return .init(action: .hold, rule: "Daily downtrend", reason: "Daily momentum \(m). Set your entry price to check your rules on this position.") }
            return .init(action: .hold, rule: "No clear trend", reason: "Add your entry price to check your rules on this position.")
        }
        let pnl = price / e - 1
        let up = String(format: "%.0f", pnl * 100), down = String(format: "%.0f", -pnl * 100)
        if pnl >= 0.40 {
            return .init(action: .sell, rule: "+40 % from entry: your take-profit rule",
                         reason: "Up \(up)% from your entry: the level where the take-profit rule triggers.")
        }
        if pnl >= 0.15 && (falling || score < 0) {
            return .init(action: .sell, rule: "+15 % and the trend turned down",
                         reason: "Up \(up)% from your entry while daily momentum turned negative (\(m)).")
        }
        if pnl <= -0.10 && !falling {
            return .init(action: .buy, rule: "−10 % from entry, trend stopped falling",
                         reason: "\(down)% under your entry; daily momentum is no longer negative (\(m)).")
        }
        if pnl <= -0.10 && falling {
            return .init(action: .hold, rule: "−10 % from entry, still falling",
                         reason: "\(down)% under your entry and daily momentum is still negative (\(m)).")
        }
        return .init(action: .hold, rule: "No rule triggered",
                     reason: "\(String(format: "%+.1f", pnl * 100))% from your entry; daily momentum \(m).")
    }

    func eraseAll() {
        if let current = try? DataVault.encoder.encode(snapshot), !manual.isEmpty || !entries.isEmpty {
            DataVault.backup("longterm", current, force: true)
        }
        restoring = true
        manual = []; entries = [:]; entryDates = [:]; entryFXs = [:]; prices = [:]; trend = [:]; history = [:]
        lastRemoved = nil
        restoring = false
        lastSaved = nil
        for k in ["ltManual", "ltEntries", "ltEntryDates", "ltEntryFX"] { UserDefaults.standard.removeObject(forKey: k) }
    }
}
