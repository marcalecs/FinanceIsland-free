import Foundation

enum ChartTF: String, CaseIterable, Identifiable, Sendable {
    case m1 = "1m", m5 = "5m", m15 = "15m", h1 = "1h", h4 = "4h", d1 = "1D"
    var id: String { rawValue }
    var seconds: TimeInterval {
        switch self {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .h1: return 3600
        case .h4: return 14_400
        case .d1: return 86_400
        }
    }
    var intraday: Bool { self != .d1 }
}

enum ChartFeed {
    static func candles(_ s: HubSubject, tf: ChartTF) async throws -> (candles: [Candle], source: String) {
        switch s {
        case .item(let i):
            let r = try await MarketData.series(i, interval: interval(tf))
            return (r.candles, r.source.name)
        case .asset(let a):
            if !a.isFiat {
                let r = try await MarketData.series(WatchItem(source: .binance, symbol: a.code + "USDT"), interval: interval(tf))
                return (r.candles, r.source.name)
            }
            let r = try await MarketData.series(WatchItem(source: .yahoo, symbol: a.yahoo), interval: interval(tf))
            return (r.candles, r.source.name)
        }
    }

    static func binanceSymbol(_ s: HubSubject) -> String? {
        switch s {
        case .asset(let a): return a.isFiat ? nil : a.code + "USDT"
        case .item(let i): return i.isCrypto ? i.symbol : nil
        }
    }

    static func latest(_ s: HubSubject, tf: ChartTF, since: Date) async throws -> [Candle] {
        return try await candles(s, tf: tf).candles.filter { $0.openTime >= since.addingTimeInterval(-2 * tf.seconds) }
    }

    static func interval(_ tf: ChartTF) -> String {
        switch tf {
        case .m1: return "1m"
        case .m5: return "5m"
        case .m15: return "15m"
        case .h1: return "1h"
        case .h4: return "4h"
        case .d1: return "1d"
        }
    }

    static func merge(_ c: [Candle], every: TimeInterval) -> [Candle] {
        var out: [Candle] = []
        for x in c {
            let b = Date(timeIntervalSince1970: (x.openTime.timeIntervalSince1970 / every).rounded(.down) * every)
            if let last = out.last, last.openTime == b {
                out[out.count - 1] = Candle(openTime: b, open: last.open, high: max(last.high, x.high), low: min(last.low, x.low),
                                            close: x.close, volume: last.volume + x.volume)
            } else {
                out.append(Candle(openTime: b, open: x.open, high: x.high, low: x.low, close: x.close, volume: x.volume))
            }
        }
        return out
    }
}
