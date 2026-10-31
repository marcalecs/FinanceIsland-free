import Foundation

struct Candle: Sendable, Hashable {
    let openTime: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    init(openTime: Date, open: Double, high: Double, low: Double, close: Double, volume: Double) {
        self.openTime = openTime
        self.open = open
        self.high = high
        self.low = low
        self.close = close
        self.volume = volume
    }

    init(time: Date, price: Double) {
        self.init(openTime: time, open: price, high: price, low: price, close: price, volume: 0)
    }
}

struct BarsMeta: Sendable {
    var price: Double? = nil
    var prevClose: Double? = nil
    var change24h: Double? = nil
    var volumeUSD24h: Double? = nil
    var name: String? = nil
    var currency: String? = nil
}

struct PriceBars: Sendable {
    var candles: [Candle]
    var adjClose: [Double]? = nil
    var meta = BarsMeta()
}

enum MarketError: LocalizedError {
    case unknownSymbol(String)
    case http(Int)
    case badData
    case notEnoughHistory(Int)
    case rateLimited(String)
    case unsupported(String)
    case allSourcesFailed([String])

    var errorDescription: String? {
        switch self {
        case .unknownSymbol(let s): return "Unknown ticker \(s)"
        case .http(let code): return "HTTP \(code)"
        case .badData: return "Bad data from the source"
        case .notEnoughHistory(let n): return "Only \(n) candles of history, need at least \(Indicators.minCandles)"
        case .rateLimited(let host): return "\(host) is rate-limiting requests, trying again in a few minutes"
        case .unsupported(let why): return why
        case .allSourcesFailed(let list):
            return "No data source answered (" + list.joined(separator: "; ") + ")"
        }
    }
}

enum DateParse {
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    private static let lock = NSLock()

    static func date(_ s: String, _ format: String, tz: String = "UTC") -> Date? {
        lock.lock(); defer { lock.unlock() }
        let key = format + "|" + tz
        let f = cache[key] ?? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: tz)
            f.dateFormat = format
            cache[key] = f
            return f
        }()
        return f.date(from: s)
    }

    static func string(_ d: Date, _ format: String, tz: String = "UTC") -> String {
        lock.lock(); defer { lock.unlock() }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = format
        return f.string(from: d)
    }
}

private func num(_ v: Any?) -> Double? {
    switch v {
    case let n as NSNumber: return n.doubleValue
    case let s as String:
        let clean = s.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(clean)
    default: return nil
    }
}

enum Yahoo {
    static let hosts = ["https://query1.finance.yahoo.com", "https://query2.finance.yahoo.com"]

    static func chart(_ symbol: String, range: String? = nil, period1: Date? = nil, interval: String) async throws -> PriceBars {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        var query = "interval=\(interval)&includeAdjustedClose=true"
        if let period1 {
            query += "&period1=\(Int(period1.timeIntervalSince1970))&period2=\(Int(Date().timeIntervalSince1970))"
        } else {
            query += "&range=\(range ?? "1mo")"
        }
        var last: Error = MarketError.badData
        for host in hosts {
            do {
                let data = try await HTTP.get("\(host)/v8/finance/chart/\(enc)?\(query)")
                return try parse(data, symbol: symbol)
            } catch let e as MarketError {
                if case .unknownSymbol = e { throw e }
                last = e
            } catch { last = error }
        }
        throw last
    }

    private static func parse(_ data: Data, symbol: String) throws -> PriceBars {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any] else { throw MarketError.badData }
        guard let res = (chart["result"] as? [[String: Any]])?.first else { throw MarketError.unknownSymbol(symbol) }
        let meta = res["meta"] as? [String: Any] ?? [:]
        let ts = (res["timestamp"] as? [Any])?.compactMap(num) ?? []
        let ind = res["indicators"] as? [String: Any] ?? [:]
        let q = (ind["quote"] as? [[String: Any]])?.first ?? [:]
        let adj = ((ind["adjclose"] as? [[String: Any]])?.first?["adjclose"] as? [Any])
        func col(_ k: String) -> [Any] { q[k] as? [Any] ?? [] }
        let o = col("open"), h = col("high"), l = col("low"), c = col("close"), v = col("volume")
        var candles: [Candle] = []
        var adjOut: [Double] = []
        for (i, t) in ts.enumerated() {
            guard let close = num(c[safe: i]) else { continue }
            let open = num(o[safe: i]) ?? close
            candles.append(Candle(openTime: Date(timeIntervalSince1970: t), open: open,
                                  high: num(h[safe: i]) ?? max(open, close),
                                  low: num(l[safe: i]) ?? min(open, close),
                                  close: close, volume: num(v[safe: i]) ?? 0))
            adjOut.append(adj.flatMap { num($0[safe: i]) } ?? close)
        }
        var m = BarsMeta()
        m.price = num(meta["regularMarketPrice"])
        m.prevClose = num(meta["previousClose"]) ?? num(meta["chartPreviousClose"])
        if let p = m.price, let ch = num(meta["fulldayChange"]) { m.prevClose = p - ch }
        m.name = meta["longName"] as? String ?? meta["shortName"] as? String
        m.currency = meta["currency"] as? String
        if let vol = num(meta["regularMarketVolume"]), let p = m.price, (m.currency ?? "USD") == "USD" {
            m.volumeUSD24h = vol * p
        }
        return PriceBars(candles: candles, adjClose: adj == nil ? nil : adjOut, meta: m)
    }
}

enum Nasdaq {
    private static let headers = ["Accept": "application/json, text/plain, */*",
                                  "Origin": "https://www.nasdaq.com", "Referer": "https://www.nasdaq.com/"]

    private static func classes(_ symbol: String) -> [String] { ["stocks", "etf"] }

    static func supports(_ symbol: String) -> Bool {
        !symbol.contains(".") && !symbol.contains("^") && !symbol.contains("=") && !symbol.contains("-")
    }

    static func daily(_ symbol: String, from: Date) async throws -> [Candle] {
        guard supports(symbol) else { throw MarketError.unsupported("Nasdaq only lists US tickers") }
        let start = DateParse.string(from, "yyyy-MM-dd")
        var last: Error = MarketError.unknownSymbol(symbol)
        for ac in classes(symbol) {
            do {
                let any = try await HTTP.json("https://api.nasdaq.com/api/quote/\(symbol)/historical?assetclass=\(ac)&fromdate=\(start)&limit=9999",
                                              headers: headers)
                guard let rows = (((any as? [String: Any])?["data"] as? [String: Any])?["tradesTable"] as? [String: Any])?["rows"] as? [[String: Any]],
                      !rows.isEmpty else { throw MarketError.unknownSymbol(symbol) }
                let out: [Candle] = rows.compactMap { r in
                    guard let ds = r["date"] as? String,
                          let d = DateParse.date(ds, "MM/dd/yyyy", tz: "America/New_York"),
                          let c = num(r["close"]) else { return nil }
                    let o = num(r["open"]) ?? c
                    return Candle(openTime: d, open: o, high: num(r["high"]) ?? max(o, c), low: num(r["low"]) ?? min(o, c),
                                  close: c, volume: num(r["volume"]) ?? 0)
                }
                return out.sorted { $0.openTime < $1.openTime }
            } catch { last = error }
        }
        throw last
    }

    struct Info: Sendable { let price: Double; let prevClose: Double?; let name: String? }

    static func info(_ symbol: String) async throws -> Info {
        guard supports(symbol) else { throw MarketError.unsupported("Nasdaq only lists US tickers") }
        var last: Error = MarketError.unknownSymbol(symbol)
        for ac in classes(symbol) {
            do {
                let any = try await HTTP.json("https://api.nasdaq.com/api/quote/\(symbol)/info?assetclass=\(ac)", headers: headers)
                guard let d = (any as? [String: Any])?["data"] as? [String: Any],
                      let p = d["primaryData"] as? [String: Any], let price = num(p["lastSalePrice"]) else {
                    throw MarketError.unknownSymbol(symbol)
                }
                let change = num(p["netChange"])
                return Info(price: price, prevClose: change.map { price - $0 }, name: d["companyName"] as? String)
            } catch { last = error }
        }
        throw last
    }

    static func intraday(_ symbol: String) async throws -> [Candle] {
        guard supports(symbol) else { throw MarketError.unsupported("Nasdaq only lists US tickers") }
        var last: Error = MarketError.unknownSymbol(symbol)
        for ac in classes(symbol) {
            do {
                let any = try await HTTP.json("https://api.nasdaq.com/api/quote/\(symbol)/chart?assetclass=\(ac)", headers: headers)
                guard let pts = ((any as? [String: Any])?["data"] as? [String: Any])?["chart"] as? [[String: Any]], !pts.isEmpty else {
                    throw MarketError.unknownSymbol(symbol)
                }
                let shift = TimeInterval(TimeZone(identifier: "America/New_York")?.secondsFromGMT() ?? 0)
                return pts.compactMap { p in
                    guard let x = num(p["x"]), let y = num(p["y"]) else { return nil }
                    return Candle(time: Date(timeIntervalSince1970: x / 1000 - shift), price: y)
                }
            } catch { last = error }
        }
        throw last
    }
}

enum Binance {
    static let hosts = ["https://data-api.binance.vision", "https://api.binance.com"]

    private static func get(_ path: String, _ query: String, symbol: String) async throws -> Data {
        var last: Error = MarketError.badData
        for host in hosts {
            do { return try await HTTP.get("\(host)\(path)?\(query)") }
            catch MarketError.http(400) { throw MarketError.unknownSymbol(symbol) }
            catch { last = error }
        }
        throw last
    }

    static func klines(_ symbol: String, interval: String, limit: Int = 1000, startTime: Date? = nil,
                       closedOnly: Bool = false) async throws -> [Candle] {
        var q = "symbol=\(symbol)&interval=\(interval)&limit=\(min(limit, 1000))"
        if let startTime { q += "&startTime=\(Int64(startTime.timeIntervalSince1970 * 1000))" }
        let data = try await get("/api/v3/klines", q, symbol: symbol)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[Any]] else { throw MarketError.badData }
        let now = Date()
        return rows.compactMap { r in
            guard r.count > 6, let t = num(r[0]), let ct = num(r[6]), let o = num(r[1]), let h = num(r[2]),
                  let l = num(r[3]), let c = num(r[4]), let v = num(r[5]) else { return nil }
            if closedOnly && Date(timeIntervalSince1970: ct / 1000) > now { return nil }
            return Candle(openTime: Date(timeIntervalSince1970: t / 1000), open: o, high: h, low: l, close: c, volume: v)
        }
    }

    static func dailyHistory(_ symbol: String, from: Date) async throws -> [Candle] {
        var out: [Candle] = []
        var start = from
        for _ in 0..<8 {
            let page = try await klines(symbol, interval: "1d", limit: 1000, startTime: start)
            out += page
            guard page.count == 1000, let last = page.last else { break }
            start = last.openTime.addingTimeInterval(86_400)
        }
        return out
    }

    static func ticker24h(_ symbol: String) async throws -> BarsMeta {
        let data = try await get("/api/v3/ticker/24hr", "symbol=\(symbol)", symbol: symbol)
        guard let t = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MarketError.badData }
        var m = BarsMeta()
        m.price = num(t["lastPrice"])
        m.change24h = num(t["priceChangePercent"])
        let quote = WatchItem.quotes.first { symbol.hasSuffix($0) } ?? ""
        if ["USDT", "USDC", "FDUSD"].contains(quote) { m.volumeUSD24h = num(t["quoteVolume"]) }
        m.currency = quote
        return m
    }
}

enum Coinbase {

    static func candles(_ product: String, granularity: Int, end: Date? = nil) async throws -> [Candle] {
        var q = "granularity=\(granularity)"
        if let end {
            let start = end.addingTimeInterval(-Double(granularity * 299))
            q += "&start=\(DateParse.string(start, "yyyy-MM-dd'T'HH:mm:ss'Z'"))&end=\(DateParse.string(end, "yyyy-MM-dd'T'HH:mm:ss'Z'"))"
        }
        let any: Any
        do { any = try await HTTP.json("https://api.exchange.coinbase.com/products/\(product)/candles?\(q)") }
        catch MarketError.http(404) { throw MarketError.unknownSymbol(product) }
        catch MarketError.http(400) { throw MarketError.unknownSymbol(product) }
        guard let rows = any as? [[Any]] else { throw MarketError.badData }
        return rows.compactMap { r in
            guard r.count >= 6, let t = num(r[0]), let l = num(r[1]), let h = num(r[2]), let o = num(r[3]),
                  let c = num(r[4]), let v = num(r[5]) else { return nil }
            return Candle(openTime: Date(timeIntervalSince1970: t), open: o, high: h, low: l, close: c, volume: v)
        }.sorted { $0.openTime < $1.openTime }
    }

    static func dailyHistory(_ product: String, from: Date) async throws -> [Candle] {
        var out: [Candle] = []
        var end = Date()
        for _ in 0..<12 {
            let page = try await candles(product, granularity: 86_400, end: end)
            guard let first = page.first else { break }
            out = page + out.filter { $0.openTime > page.last!.openTime }
            if first.openTime <= from || page.count < 250 { break }
            end = first.openTime.addingTimeInterval(-86_400)
        }
        return out.filter { $0.openTime >= from }
    }
}

enum Kraken {
    static let intervals: [String: Int] = ["1m": 1, "5m": 5, "15m": 15, "30m": 30, "1h": 60, "4h": 240, "1d": 1440, "1w": 10080]

    static func ohlc(_ pair: String, interval: String) async throws -> [Candle] {
        guard let minutes = intervals[interval] else { throw MarketError.unsupported("Kraken has no \(interval) candles") }
        let any = try await HTTP.json("https://api.kraken.com/0/public/OHLC?pair=\(pair)&interval=\(minutes)")
        guard let root = any as? [String: Any] else { throw MarketError.badData }
        if let errs = root["error"] as? [String], !errs.isEmpty { throw MarketError.unknownSymbol(pair) }
        guard let result = root["result"] as? [String: Any],
              let rows = result.first(where: { $0.key != "last" })?.value as? [[Any]] else { throw MarketError.badData }
        return rows.compactMap { r in
            guard r.count >= 7, let t = num(r[0]), let o = num(r[1]), let h = num(r[2]), let l = num(r[3]),
                  let c = num(r[4]), let v = num(r[6]) else { return nil }
            return Candle(openTime: Date(timeIntervalSince1970: t), open: o, high: h, low: l, close: c, volume: v)
        }
    }
}

enum CoinGecko {
    static func closes(_ id: String, days: Int) async throws -> [Candle] {
        let any = try await HTTP.json("https://api.coingecko.com/api/v3/coins/\(id)/market_chart?vs_currency=usd&days=\(days)")
        guard let prices = (any as? [String: Any])?["prices"] as? [[Any]] else { throw MarketError.unknownSymbol(id) }
        return prices.compactMap { p in
            guard p.count >= 2, let t = num(p[0]), let v = num(p[1]) else { return nil }
            return Candle(time: Date(timeIntervalSince1970: t / 1000), price: v)
        }
    }
}

enum FRED {
    private static let series: [String: (id: String, usdPerUnit: Bool)] = [
        "EUR": ("DEXUSEU", true), "GBP": ("DEXUSUK", true), "AUD": ("DEXUSAL", true), "NZD": ("DEXUSNZ", true),
        "JPY": ("DEXJPUS", false), "CNY": ("DEXCHUS", false), "CHF": ("DEXSZUS", false), "CAD": ("DEXCAUS", false),
        "INR": ("DEXINUS", false), "HKD": ("DEXHKUS", false), "KRW": ("DEXKOUS", false), "THB": ("DEXTHUS", false),
        "MXN": ("DEXMXUS", false), "SGD": ("DEXSIUS", false), "SEK": ("DEXSDUS", false), "NOK": ("DEXNOUS", false),
        "DKK": ("DEXDNUS", false), "BRL": ("DEXBZUS", false), "ZAR": ("DEXSFUS", false), "TWD": ("DEXTAUS", false),
    ]

    static func supports(_ code: String) -> Bool { code == "USD" || series[code] != nil }

    static func usdPer(_ code: String, from: Date) async throws -> [(Date, Double)] {
        guard let s = series[code] else { throw MarketError.unsupported("The Federal Reserve doesn't publish \(code)") }
        let day = DateParse.string(from, "yyyy-MM-dd")
        let data = try await HTTP.get("https://fred.stlouisfed.org/graph/fredgraph.csv?id=\(s.id)&cosd=\(day)", timeout: 20)
        let rows = CSV.rows(data).dropFirst().compactMap { r -> (Date, Double)? in
            guard r.count >= 2, let t = DateParse.date(r[0], "yyyy-MM-dd"), let v = Double(r[1]), v > 0 else { return nil }
            return (t, s.usdPerUnit ? v : 1 / v)
        }
        guard !rows.isEmpty else { throw MarketError.badData }
        return rows
    }

    static func pair(code: String, base: String, from: Date) async throws -> [(Date, Double)] {
        async let num = code == "USD" ? nil : usdPer(code, from: from)
        async let den = base == "USD" ? nil : usdPer(base, from: from)
        let n = try await num, d = try await den
        switch (n, d) {
        case let (n?, nil): return n
        case let (nil, d?): return d.map { ($0.0, 1 / $0.1) }
        case let (n?, d?):
            let byDate = Dictionary(d.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
            return n.compactMap { t, v in byDate[t].map { (t, v / $0) } }
        default: return []
        }
    }
}

enum ECB {
    static let currencies: Set<String> = ["AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD",
                                          "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD",
                                          "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"]

    static func supports(_ a: String, _ b: String) -> Bool { currencies.contains(a) && currencies.contains(b) }

    static func history(code: String, base: String, from: Date) async throws -> [(Date, Double)] {
        guard supports(code, base) else { throw MarketError.unsupported("The ECB does not publish \(code)/\(base)") }
        let start = DateParse.string(from, "yyyy-MM-dd")
        let any = try await HTTP.json("https://api.frankfurter.dev/v1/\(start)..?base=\(code)&symbols=\(base)")
        guard let rates = (any as? [String: Any])?["rates"] as? [String: [String: Any]] else { throw MarketError.badData }
        return rates.compactMap { k, v in
            guard let d = DateParse.date(k, "yyyy-MM-dd", tz: "Europe/Berlin"), let x = num(v[base]) else { return nil }
            return (d, x)
        }.sorted { $0.0 < $1.0 }
    }
}

enum OpenER {
    static func latest(base: String) async throws -> [String: Double] {
        let any = try await HTTP.json("https://open.er-api.com/v6/latest/\(base)")
        guard let r = (any as? [String: Any])?["rates"] as? [String: Any] else { throw MarketError.badData }
        return r.compactMapValues(num)
    }
}

enum CBOE {
    static func vix() async throws -> [Candle] {
        let data = try await HTTP.get("https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv")
        return CSV.rows(data).dropFirst().compactMap { r in
            guard r.count >= 5, let d = DateParse.date(r[0], "MM/dd/yyyy", tz: "America/New_York"),
                  let o = Double(r[1]), let h = Double(r[2]), let l = Double(r[3]), let c = Double(r[4]) else { return nil }
            return Candle(openTime: d, open: o, high: h, low: l, close: c, volume: 0)
        }
    }
}

enum Treasury {
    static func yields(year: Int) async throws -> [(date: Date, m3: Double?, y10: Double?)] {
        let url = "https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/\(year)/all?type=daily_treasury_yield_curve&field_tdr_date_value=\(year)&page&_format=csv"
        let rows = CSV.rows(try await HTTP.get(url, timeout: 25))
        guard let header = rows.first else { return [] }
        let i3 = header.firstIndex(of: "3 Mo"), i10 = header.firstIndex(of: "10 Yr")
        return rows.dropFirst().compactMap { r in
            guard let d = DateParse.date(r[0], "MM/dd/yyyy", tz: "America/New_York") else { return nil }
            return (d, i3.flatMap { Double(r[safe: $0] ?? "") }, i10.flatMap { Double(r[safe: $0] ?? "") })
        }
    }
}
