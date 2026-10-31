import Foundation

enum MarketSource: String, Sendable, Codable {
    case binance
    case yahoo
}

struct WatchItem: Hashable, Identifiable, Sendable {
    let source: MarketSource
    let symbol: String
    var id: String { source.rawValue + ":" + symbol }

    init(source: MarketSource, symbol: String) {
        self.source = source
        self.symbol = symbol
    }

    init?(id: String) {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let s = MarketSource(rawValue: parts[0]) else { return nil }
        self.init(source: s, symbol: parts[1])
    }

    var isCrypto: Bool { source == .binance }

    var display: String {
        guard isCrypto else { return symbol }
        for q in Self.quotes where symbol.hasSuffix(q) && symbol.count > q.count {
            return "\(symbol.dropLast(q.count))/\(q)"
        }
        return symbol
    }

    var short: String { isCrypto ? (display.split(separator: "/").first.map(String.init) ?? symbol) : symbol }

    var quotedInUSD: Bool { isCrypto ? ["USDT", "USDC", "FDUSD"].contains { symbol.hasSuffix($0) } : true }

    var newsQuery: String { isCrypto ? short + "-USD" : symbol }

    static let quotes = ["USDT", "USDC", "FDUSD", "BTC", "ETH", "EUR", "BNB"]
}

struct MarketQuote: Sendable {
    let price: Double
    let change24h: Double?
    let volumeUSD24h: Double?
    let name: String?
    let currency: String
}

struct MarketSeries: Sendable {
    let candles: [Candle]
    let quote: MarketQuote
    var source: DataSource = .yahoo
}

enum CandleInterval {
    static let all = ["1m", "5m", "15m", "30m", "1h", "2h", "4h", "6h", "12h", "1d", "1w"]

    static func name(_ iv: String) -> String {
        switch iv {
        case "1m": return "1 minute"
        case "5m": return "5 minutes"
        case "15m": return "15 minutes"
        case "30m": return "30 minutes"
        case "1h": return "1 hour"
        case "2h": return "2 hours"
        case "4h": return "4 hours"
        case "6h": return "6 hours"
        case "12h": return "12 hours"
        case "1w": return "1 week"
        default: return "1 day"
        }
    }

    static func seconds(_ iv: String) -> TimeInterval {
        switch iv {
        case "1m": return 60
        case "5m": return 300
        case "15m": return 900
        case "30m": return 1800
        case "1h": return 3600
        case "2h": return 7200
        case "4h": return 14_400
        case "6h": return 21_600
        case "12h": return 43_200
        case "1w": return 604_800
        default: return 86_400
        }
    }

}

enum MarketData {
    static func series(_ item: WatchItem, interval: String) async throws -> MarketSeries {
        let kind: InstrumentKind = item.isCrypto ? .crypto : .stock
        let memKey = item.id + "@" + interval
        let order = SourcePrefs.order(kind, sticky: await SourceMemory.shared.get(memKey))
        var attempts: [(String, @Sendable () async throws -> MarketSeries)] = []
        let step = CandleInterval.seconds(interval)
        let maxAge = item.isCrypto ? max(3 * step, 6 * 3600) : max(3 * step, 5 * 86_400)
        for src in order {
            guard let f = fetcher(src, item, interval) else { continue }
            attempts.append((src.name, {
                let s = try await f()
                try Freshness.check(s.candles.last?.openTime, maxAge: maxAge, source: src)
                return s
            }))
        }
        do {
            let (s, _) = try await firstSuccess(attempts)
            await SourceMemory.shared.set(memKey, s.source)
            return MarketSeries(candles: SeriesCleaner.clean(s.candles), quote: s.quote, source: s.source)
        } catch MarketError.allSourcesFailed(let list) {
            if !item.isCrypto && interval != "1d" {
                throw MarketError.unsupported("Intraday stock candles come only from Yahoo Finance, which isn't answering right now. The 1d timeframe works through Nasdaq.")
            }
            throw MarketError.allSourcesFailed(list)
        }
    }

    private static func fetcher(_ src: DataSource, _ item: WatchItem, _ interval: String) -> (@Sendable () async throws -> MarketSeries)? {
        if item.isCrypto {
            let (sym, usd) = CryptoSymbols.forPair(item.symbol)
            switch src {
            case .binance: return { try await binance(item.symbol, interval: interval) }
            case .kraken:
                guard let k = sym.kraken, Kraken.intervals[interval] != nil else { return nil }
                return { try await exchange(.kraken, try await Kraken.ohlc(k, interval: interval), interval: interval, usd: usd) }
            case .coinbase:
                guard usd, let p = sym.coinbase,
                      let g = ["1m": 60, "5m": 300, "15m": 900, "1h": 3600, "6h": 21_600, "1d": 86_400][interval] else { return nil }
                return { try await exchange(.coinbase, try await Coinbase.candles(p, granularity: g), interval: interval, usd: true) }
            case .yahoo:
                guard usd else { return nil }
                return { try await yahoo(sym.yahoo, interval: interval) }
            default: return nil
            }
        }
        switch src {
        case .yahoo: return { try await yahoo(item.symbol, interval: interval) }
        case .nasdaq:
            guard interval == "1d", Nasdaq.supports(item.symbol) else { return nil }
            return { try await nasdaq(item.symbol) }
        default: return nil
        }
    }

    private static func binance(_ symbol: String, interval: String) async throws -> MarketSeries {
        async let klines = Binance.klines(symbol, interval: interval, limit: 600)
        async let ticker = Binance.ticker24h(symbol)
        let all = try await klines
        let now = Date()
        let closed = all.filter { $0.openTime.addingTimeInterval(CandleInterval.seconds(interval)) <= now }
        var meta = (try? await ticker) ?? BarsMeta()
        if meta.price == nil { meta.price = all.last?.close }
        guard let price = meta.price else { throw MarketError.badData }
        return MarketSeries(candles: closed,
                            quote: MarketQuote(price: price, change24h: meta.change24h, volumeUSD24h: meta.volumeUSD24h,
                                               name: nil, currency: meta.currency ?? ""),
                            source: .binance)
    }

    private static func exchange(_ src: DataSource, _ all: [Candle], interval: String, usd: Bool) async throws -> MarketSeries {
        guard let last = all.last else { throw MarketError.badData }
        let now = Date()
        let closed = all.filter { $0.openTime.addingTimeInterval(CandleInterval.seconds(interval)) <= now }
        let dayAgo = now.addingTimeInterval(-86_400)
        let ref = all.last { $0.openTime <= dayAgo }?.close
        let change = ref.map { ($0 == 0) ? 0 : (last.close - $0) / $0 * 100 }
        let vol = all.filter { $0.openTime > dayAgo }.reduce(0) { $0 + $1.volume * $1.close }
        return MarketSeries(candles: closed,
                            quote: MarketQuote(price: last.close, change24h: change,
                                               volumeUSD24h: usd && vol > 0 ? vol : nil, name: nil,
                                               currency: usd ? "USD" : ""),
                            source: src)
    }

    private static func nasdaq(_ symbol: String) async throws -> MarketSeries {
        async let hist = Nasdaq.daily(symbol, from: Date().addingTimeInterval(-3 * 365 * 86_400))
        async let info = Nasdaq.info(symbol)
        var bars = try await hist
        if let last = bars.last, Calendar.current.isDateInToday(last.openTime) { bars.removeLast() }
        let i = try? await info
        guard let price = i?.price ?? bars.last?.close else { throw MarketError.badData }
        var change: Double?
        if let prev = i?.prevClose ?? bars.last?.close, prev != 0 { change = (price - prev) / prev * 100 }
        let vol = bars.last.map { $0.volume * $0.close }
        return MarketSeries(candles: bars,
                            quote: MarketQuote(price: price, change24h: change, volumeUSD24h: vol,
                                               name: i?.name, currency: "USD"),
                            source: .nasdaq)
    }

    private static func yahoo(_ symbol: String, interval: String) async throws -> MarketSeries {
        let (range, yInterval, merge): (String, String, Int) = {
            switch interval {
            case "1m": return ("5d", "1m", 1)
            case "5m": return ("1mo", "5m", 1)
            case "15m": return ("1mo", "15m", 1)
            case "30m": return ("1mo", "30m", 1)
            case "1h": return ("6mo", "60m", 1)
            case "2h": return ("1y", "60m", 2)
            case "4h": return ("2y", "60m", 4)
            case "6h": return ("2y", "60m", 6)
            case "12h": return ("2y", "60m", 12)
            case "1w": return ("10y", "1wk", 1)
            default: return ("2y", "1d", 1)
            }
        }()
        async let chartTask = Yahoo.chart(symbol, range: range, interval: yInterval)
        async let dayTask = Yahoo.chart(symbol, range: "1d", interval: "1h")
        let res = try await chartTask

        let barLen = yInterval == "60m" ? 3600 : CandleInterval.seconds(interval)
        let now = Date()
        var bars: [Candle] = []
        for (i, c) in res.candles.enumerated() {
            if yInterval != "1d" && c.openTime.addingTimeInterval(barLen) > now { continue }
            if yInterval == "1d" && Calendar.current.isDateInToday(c.openTime) && i == res.candles.count - 1 { continue }
            bars.append(c)
        }
        if merge > 1 { bars = mergeBars(bars, every: merge) }

        var change: Double?
        var price = res.meta.price ?? bars.last?.close
        if let day = try? await dayTask {
            price = day.meta.price ?? price
            if let p = price, let prev = day.meta.prevClose, prev != 0 { change = (p - prev) / prev * 100 }
        }
        guard let price else { throw MarketError.badData }
        return MarketSeries(candles: bars,
                            quote: MarketQuote(price: price, change24h: change, volumeUSD24h: res.meta.volumeUSD24h,
                                               name: res.meta.name, currency: res.meta.currency ?? "USD"),
                            source: .yahoo)
    }

    private static func mergeBars(_ bars: [Candle], every n: Int) -> [Candle] {
        var out: [Candle] = []
        var i = 0
        while i + n <= bars.count {
            let g = bars[i..<(i + n)]
            out.append(Candle(openTime: g.first!.openTime, open: g.first!.open,
                              high: g.map(\.high).max()!, low: g.map(\.low).min()!,
                              close: g.last!.close, volume: g.map(\.volume).reduce(0, +)))
            i += n
        }
        return out
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
