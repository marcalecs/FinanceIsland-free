import Foundation

enum DataSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case yahoo, nasdaq, binance, coinbase, kraken, coingecko, fred, ecb, openER

    var id: String { rawValue }

    var name: String {
        switch self {
        case .yahoo: return "Yahoo Finance"
        case .nasdaq: return "Nasdaq"
        case .binance: return "Binance"
        case .coinbase: return "Coinbase"
        case .kraken: return "Kraken"
        case .coingecko: return "CoinGecko"
        case .fred: return "Federal Reserve (FRED)"
        case .ecb: return "ECB"
        case .openER: return "ExchangeRate-API"
        }
    }

    var note: String {
        switch self {
        case .yahoo: return "Everything, intraday included, but often rate-limited"
        case .nasdaq: return "US stocks and ETFs: 10 years daily + today's minutes"
        case .binance: return "Crypto vs USDT, every timeframe"
        case .coinbase: return "Crypto vs USD, every timeframe except 4h"
        case .kraken: return "Crypto vs USD, last 720 candles"
        case .coingecko: return "Crypto closing prices only"
        case .fred: return "Official daily rates of 20 major currencies against the dollar"
        case .ecb: return "Official daily rates of 30 major currencies"
        case .openER: return "Latest rate of 160 currencies, no history"
        }
    }

    static let fiatChain: [DataSource] = [.yahoo, .fred, .ecb, .openER]
    static let cryptoChain: [DataSource] = [.binance, .coinbase, .kraken, .yahoo, .coingecko]
    static let stockChain: [DataSource] = [.yahoo, .nasdaq]
}

enum InstrumentKind: String, Sendable { case fiat, crypto, stock }

enum SourcePrefs {
    static func key(_ k: InstrumentKind) -> String { "source." + k.rawValue }

    static func preferred(_ k: InstrumentKind) -> DataSource? {
        UserDefaults.standard.string(forKey: key(k)).flatMap(DataSource.init(rawValue:))
    }

    static func chain(_ k: InstrumentKind) -> [DataSource] {
        switch k {
        case .fiat: return DataSource.fiatChain
        case .crypto: return DataSource.cryptoChain
        case .stock: return DataSource.stockChain
        }
    }

    static func order(_ k: InstrumentKind, sticky: DataSource?) -> [DataSource] {
        var out: [DataSource] = []
        for s in [preferred(k), sticky].compactMap({ $0 }) + chain(k) where !out.contains(s) { out.append(s) }
        return out
    }
}

actor SourceMemory {
    static let shared = SourceMemory()
    private var last: [String: DataSource] = [:]
    func get(_ key: String) -> DataSource? { last[key] }
    func set(_ key: String, _ s: DataSource) { last[key] = s }
}

struct CryptoSymbols: Sendable {
    let code: String
    let binance: String?
    let coinbase: String?
    let kraken: String?
    let coingecko: String?
    var yahoo: String { Catalog.entry(kind: .crypto, code: code)?.yahoo ?? "\(code)-USD" }

    static func forCode(_ code: String) -> CryptoSymbols {
        switch code {
        case "BTC": return .init(code: code, binance: "BTCUSDT", coinbase: "BTC-USD", kraken: "XBTUSD", coingecko: "bitcoin")
        case "ETH": return .init(code: code, binance: "ETHUSDT", coinbase: "ETH-USD", kraken: "ETHUSD", coingecko: "ethereum")
        case "SOL": return .init(code: code, binance: "SOLUSDT", coinbase: "SOL-USD", kraken: "SOLUSD", coingecko: "solana")
        case "TON": return .init(code: code, binance: "TONUSDT", coinbase: nil, kraken: "TONUSD", coingecko: "the-open-network")
        case "USDT": return .init(code: code, binance: nil, coinbase: "USDT-USD", kraken: "USDTUSD", coingecko: "tether")
        case "USDC": return .init(code: code, binance: nil, coinbase: nil, kraken: "USDCUSD", coingecko: "usd-coin")
        case "BNB": return .init(code: code, binance: "BNBUSDT", coinbase: nil, kraken: "BNBUSD", coingecko: "binancecoin")
        case "XRP": return .init(code: code, binance: "XRPUSDT", coinbase: "XRP-USD", kraken: "XRPUSD", coingecko: "ripple")
        case "DOGE": return .init(code: code, binance: "DOGEUSDT", coinbase: "DOGE-USD", kraken: "XDGUSD", coingecko: "dogecoin")
        case "ADA": return .init(code: code, binance: "ADAUSDT", coinbase: "ADA-USD", kraken: "ADAUSD", coingecko: "cardano")
        case "TRX": return .init(code: code, binance: "TRXUSDT", coinbase: nil, kraken: "TRXUSD", coingecko: "tron")
        default: return .init(code: code, binance: code + "USDT", coinbase: code + "-USD", kraken: code + "USD", coingecko: nil)
        }
    }

    static func forPair(_ pair: String) -> (symbols: CryptoSymbols, usdQuoted: Bool) {
        for q in ["USDT", "USDC", "FDUSD"] where pair.hasSuffix(q) && pair.count > q.count {
            let base = forCode(String(pair.dropLast(q.count)))
            return (CryptoSymbols(code: base.code, binance: pair, coinbase: base.coinbase, kraken: base.kraken,
                                  coingecko: base.coingecko), true)
        }
        let kraken = pair.replacingOccurrences(of: "BTC", with: "XBT")
        return (CryptoSymbols(code: pair, binance: pair, coinbase: nil, kraken: kraken, coingecko: nil), false)
    }
}

enum Freshness {
    static func check(_ last: Date?, maxAge: TimeInterval, source: DataSource) throws {
        guard let last else { return }
        if Date().timeIntervalSince(last) > maxAge {
            throw MarketError.unsupported("\(source.name) data is stale (last update \(Fmt.date(last, "d MMM yyyy")))")
        }
    }
}

enum SeriesCleaner {
    static func clean(_ c: [Candle]) -> [Candle] {
        let pos = c.filter { $0.close > 0 && $0.close.isFinite }
        guard pos.count >= 5 else { return pos }
        let closes = pos.map(\.close)
        var keep = [Bool](repeating: true, count: pos.count)
        let k = 3
        for i in pos.indices {
            let lo = max(0, i - k), hi = min(pos.count - 1, i + k)
            var nb: [Double] = []
            for j in lo...hi where j != i { nb.append(closes[j]) }
            guard nb.count >= 3 else { continue }
            nb.sort()
            let med = nb[nb.count / 2]
            let mad = nb.map { abs($0 - med) }.sorted()[nb.count / 2]
            let dev = abs(closes[i] - med)
            if med > 0 && dev / med > 0.15 && dev > 8 * max(mad, med * 0.002) { keep[i] = false }
        }
        return pos.indices.filter { keep[$0] }.map { pos[$0] }
    }

    static func clean(_ p: [PricePoint]) -> [PricePoint] {
        clean(p.map { Candle(time: $0.time, price: $0.value) }).map { PricePoint(time: $0.openTime, value: $0.close) }
    }
}
