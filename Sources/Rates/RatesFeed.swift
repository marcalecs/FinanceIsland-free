import Foundation

enum RatesFeed {
    struct Series: Sendable {
        let points: [PricePoint]
        let price: Double?
        let prevClose: Double?
        let source: DataSource
        var note: String? = nil
    }

    enum Span: Sendable, Hashable {
        case timeframe(Timeframe)
        case cards(SparkRange)
        case year
        case intraday

        var intraday: Bool {
            if case .timeframe(let tf) = self { return tf == .h1 || tf == .h24 }
            return self == .intraday
        }

        var dailyFrom: Date {
            let day = 86_400.0
            switch self {
            case .timeframe(let tf):
                switch tf {
                case .h1, .h24: return Date().addingTimeInterval(-3 * day)
                case .w1: return Date().addingTimeInterval(-9 * day)
                case .m1: return Date().addingTimeInterval(-32 * day)
                case .all: return Date().addingTimeInterval(-10 * 365 * day)
                }
            case .cards(let r):
                switch r {
                case .d5: return Date().addingTimeInterval(-8 * day)
                case .m1: return Date().addingTimeInterval(-32 * day)
                case .m3: return Date().addingTimeInterval(-93 * day)
                }
            case .year: return Date().addingTimeInterval(-740 * day)
            case .intraday: return Date().addingTimeInterval(-14 * day)
            }
        }

        var yahoo: (range: String, interval: String) {
            switch self {
            case .timeframe(let tf): return (tf.range, tf.interval)
            case .cards(let r): return (r.yahoo, "1d")
            case .year: return ("2y", "1d")
            case .intraday: return ("1mo", "15m")
            }
        }

        var candles: (interval: String, count: Int) {
            switch self {
            case .timeframe(let tf):
                switch tf {
                case .h1: return ("1m", 61)
                case .h24: return ("15m", 97)
                case .w1: return ("1h", 169)
                case .m1: return ("1d", 31)
                case .all: return ("1w", 1000)
                }
            case .cards(let r):
                switch r {
                case .d5: return ("1d", 6)
                case .m1: return ("1d", 31)
                case .m3: return ("1d", 92)
                }
            case .year: return ("1d", 740)
            case .intraday: return ("15m", 1000)
            }
        }

        var window: TimeInterval? {
            if case .timeframe(let tf) = self { return tf.window }
            return nil
        }
    }

    static func series(_ a: Asset, _ span: Span) async throws -> Series {
        let kind: InstrumentKind = a.isFiat ? .fiat : .crypto
        let memKey = a.id + "/" + a.base + "/" + (span.intraday ? "i" : "d")
        let order = SourcePrefs.order(kind, sticky: await SourceMemory.shared.get(memKey))
        let candle = CandleInterval.seconds(span.candles.interval)
        let maxAge: TimeInterval = a.isFiat ? 8 * 86_400 : max(span.intraday ? 6 * 3600 : 4 * 86_400, 2 * candle)
        let attempts: [(String, @Sendable () async throws -> Series)] = order.compactMap { src in
            guard let f = fetcher(src, a, span) else { return nil }
            return (src.name, {
                let s = try await f()
                if src != .openER && s.points.count < 2 { throw MarketError.badData }
                try Freshness.check(s.points.last?.time, maxAge: maxAge, source: src)
                return s
            })
        }
        guard !attempts.isEmpty else { throw MarketError.unsupported("No source for \(a.code)") }
        do {
            let (s, _) = try await firstSuccess(attempts)
            await SourceMemory.shared.set(memKey, s.source)
            return Series(points: trim(SeriesCleaner.clean(s.points), span), price: s.price,
                          prevClose: s.prevClose, source: s.source)
        } catch MarketError.allSourcesFailed(let list) {
            if a.isFiat && span.intraday && span != .intraday {
                if var daily = try? await series(a, .timeframe(.w1)), daily.points.count >= 2 {
                    daily.note = "No intraday rates right now · showing daily rates from \(daily.source.name)"
                    return daily
                }
            }
            throw MarketError.allSourcesFailed(list)
        }
    }

    static func quote(_ a: Asset, range: SparkRange) async throws -> (Quote, DataSource) {
        let s = try await series(a, .cards(range))
        let closes = s.points.map(\.value)
        guard let now = s.price ?? closes.last else { throw MarketError.badData }
        let prev = closes.count >= 2 ? closes[closes.count - 2] : (s.prevClose ?? now)
        return (Quote(price: now, prev: prev, history: closes, asOf: s.points.last?.time), s.source)
    }

    private static func trim(_ p: [PricePoint], _ span: Span) -> [PricePoint] {
        guard let window = span.window, let last = p.last else { return p }
        let cut = p.filter { $0.time >= last.time.addingTimeInterval(-window) }
        return cut.count >= 2 ? cut : Array(p.suffix(min(p.count, 30)))
    }

    private static func fetcher(_ src: DataSource, _ a: Asset, _ span: Span) -> (@Sendable () async throws -> Series)? {
        if a.isFiat {
            switch src {
            case .yahoo: return { try await yahooFiat(a, span) }
            case .fred:
                if span.intraday || !FRED.supports(a.code) || !FRED.supports(a.base) { return nil }
                return { try await fred(a, span) }
            case .ecb:
                if span.intraday || !ECB.supports(a.code, a.base) { return nil }
                return { try await ecb(a, span) }
            case .openER:
                if span.intraday || span == .year { return nil }
                return { try await openER(a) }
            default: return nil
            }
        }
        let sym = CryptoSymbols.forCode(a.code)
        let (iv, count) = span.candles
        switch src {
        case .binance:
            guard let s = sym.binance else { return nil }
            return {
                let c = try await Binance.klines(s, interval: iv, limit: count)
                return Series(points: c.map { PricePoint(time: $0.openTime, value: $0.close) },
                              price: c.last?.close, prevClose: nil, source: .binance)
            }
        case .coinbase:
            guard let s = sym.coinbase else { return nil }
            return { try await coinbase(s, iv, count) }
        case .kraken:
            guard let s = sym.kraken else { return nil }
            return {
                let c = try await Kraken.ohlc(s, interval: iv)
                let tail = Array(c.suffix(count))
                return Series(points: tail.map { PricePoint(time: $0.openTime, value: $0.close) },
                              price: tail.last?.close, prevClose: nil, source: .kraken)
            }
        case .yahoo:
            return {
                let y = span.yahoo
                let b = try await Yahoo.chart(sym.yahoo, range: y.range, interval: y.interval)
                return Series(points: b.candles.map { PricePoint(time: $0.openTime, value: $0.close) },
                              price: b.meta.price, prevClose: b.meta.prevClose, source: .yahoo)
            }
        case .coingecko:
            guard let id = sym.coingecko else { return nil }
            return {
                let days: Int
                switch span {
                case .timeframe(let tf): days = [.h1: 1, .h24: 1, .w1: 7, .m1: 30][tf] ?? 3650
                case .cards(let r): days = [.d5: 5, .m1: 30, .m3: 90][r] ?? 30
                case .year: days = 730
                case .intraday: days = 1
                }
                let c = try await CoinGecko.closes(id, days: days)
                return Series(points: c.map { PricePoint(time: $0.openTime, value: $0.close) },
                              price: c.last?.close, prevClose: nil, source: .coingecko)
            }
        default:
            return nil
        }
    }

    private static func coinbase(_ product: String, _ iv: String, _ count: Int) async throws -> Series {
        let c: [Candle]
        switch iv {
        case "1w":
            let daily = try await Coinbase.dailyHistory(product, from: Date().addingTimeInterval(-10 * 365 * 86_400))
            c = stride(from: daily.count - 1, through: 0, by: -7).map { daily[$0] }.reversed()
        default:
            let g = ["1m": 60, "15m": 900, "1h": 3600, "1d": 86_400][iv] ?? 86_400
            c = Array(try await Coinbase.candles(product, granularity: g).suffix(count))
        }
        return Series(points: c.map { PricePoint(time: $0.openTime, value: $0.close) },
                      price: c.last?.close, prevClose: nil, source: .coinbase)
    }

    private static func yahooFiat(_ a: Asset, _ span: Span) async throws -> Series {
        let y = span.yahoo
        let d = try await DataService.pairChart(a, range: y.range, interval: y.interval)
        guard !d.points.isEmpty || d.price != nil else { throw MarketError.badData }
        return Series(points: d.points, price: d.price, prevClose: d.prevClose, source: .yahoo)
    }

    private static func fred(_ a: Asset, _ span: Span) async throws -> Series {
        let h = try await FRED.pair(code: a.code, base: a.base, from: span.dailyFrom)
        guard let last = h.last else { throw MarketError.badData }
        let prev = h.count >= 2 ? h[h.count - 2].1 : nil
        return Series(points: h.map { PricePoint(time: $0.0, value: $0.1) }, price: last.1, prevClose: prev, source: .fred)
    }

    private static func ecb(_ a: Asset, _ span: Span) async throws -> Series {
        let h = try await ECB.history(code: a.code, base: a.base, from: span.dailyFrom)
        guard let last = h.last else { throw MarketError.badData }
        let prev = h.count >= 2 ? h[h.count - 2].1 : nil
        return Series(points: h.map { PricePoint(time: $0.0, value: $0.1) }, price: last.1, prevClose: prev, source: .ecb)
    }

    private static func openER(_ a: Asset) async throws -> Series {
        let rates = try await OpenER.latest(base: a.base)
        guard let perBase = rates[a.code], perBase > 0 else {
            throw MarketError.unsupported("ExchangeRate-API has no \(a.code)")
        }
        return Series(points: [], price: 1 / perBase, prevClose: nil, source: .openER)
    }
}
