import Foundation

struct Indicators: Sendable {
    static let minCandles = 210

    let closes: [Double]
    let sma20: [Double?]
    let sma50: [Double?]
    let sma200: [Double?]
    let rsi14: [Double?]
    let macd: [Double?]
    let macdSignal: [Double?]
    let bbUpper: [Double?]
    let bbLower: [Double?]
    let atr14: [Double?]
    let roc10: [Double?]
    let volumeRatio: [Double?]

    init(_ candles: [Candle]) {
        let c = candles.map(\.close)
        closes = c
        sma20 = Self.sma(c, 20)
        sma50 = Self.sma(c, 50)
        sma200 = Self.sma(c, 200)
        rsi14 = Self.rsi(c, 14)
        (macd, macdSignal) = Self.macd(c)
        let sd = Self.stdev(c, 20)
        bbUpper = zip(sma20, sd).map { a, s in a.flatMap { a in s.map { a + 2 * $0 } } }
        bbLower = zip(sma20, sd).map { a, s in a.flatMap { a in s.map { a - 2 * $0 } } }
        atr14 = Self.atr(candles, 14)
        roc10 = c.indices.map { i in
            guard i >= 10, c[i - 10] != 0 else { return nil }
            return (c[i] - c[i - 10]) / c[i - 10] * 100
        }
        let v = candles.map(\.volume)
        volumeRatio = v.indices.map { i in
            guard i >= 20 else { return nil }
            let avg = v[(i - 20)..<i].reduce(0, +) / 20
            return avg > 0 ? v[i] / avg : nil
        }
    }

    var count: Int { closes.count }

    static func sma(_ x: [Double], _ n: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: x.count)
        guard x.count >= n else { return out }
        var sum = x[0..<n].reduce(0, +)
        out[n - 1] = sum / Double(n)
        for i in n..<x.count {
            sum += x[i] - x[i - n]
            out[i] = sum / Double(n)
        }
        return out
    }

    static func macd(_ x: [Double], fast: Int = 12, slow: Int = 26, signal: Int = 9) -> (line: [Double?], signal: [Double?]) {
        let line: [Double?] = zip(ema(x, fast), ema(x, slow)).map { a, b in
            guard let a, let b else { return nil }
            return a - b
        }
        return (line, emaOptional(line, signal))
    }

    static func ema(_ x: [Double], _ n: Int) -> [Double?] {
        emaOptional(x.map { Optional($0) }, n)
    }

    static func emaOptional(_ x: [Double?], _ n: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: x.count)
        let k = 2.0 / Double(n + 1)
        var seed: [Double] = []
        var prev: Double?
        for i in x.indices {
            guard let v = x[i] else { continue }
            if let p = prev {
                let e = v * k + p * (1 - k)
                out[i] = e
                prev = e
            } else {
                seed.append(v)
                if seed.count == n {
                    let s = seed.reduce(0, +) / Double(n)
                    out[i] = s
                    prev = s
                }
            }
        }
        return out
    }

    static func rsi(_ x: [Double], _ n: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: x.count)
        guard x.count > n else { return out }
        var gain = 0.0, loss = 0.0
        for i in 1...n {
            let d = x[i] - x[i - 1]
            if d >= 0 { gain += d } else { loss -= d }
        }
        var ag = gain / Double(n), al = loss / Double(n)
        func value() -> Double { al == 0 ? (ag == 0 ? 50 : 100) : 100 - 100 / (1 + ag / al) }
        out[n] = value()
        for i in (n + 1)..<x.count {
            let d = x[i] - x[i - 1]
            ag = (ag * Double(n - 1) + max(d, 0)) / Double(n)
            al = (al * Double(n - 1) + max(-d, 0)) / Double(n)
            out[i] = value()
        }
        return out
    }

    static func stdev(_ x: [Double], _ n: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: x.count)
        guard x.count >= n else { return out }
        for i in (n - 1)..<x.count {
            let w = x[(i - n + 1)...i]
            let m = w.reduce(0, +) / Double(n)
            out[i] = sqrt(w.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n))
        }
        return out
    }

    static func atr(_ c: [Candle], _ n: Int) -> [Double?] {
        var out = [Double?](repeating: nil, count: c.count)
        guard c.count > n else { return out }
        var tr: [Double] = [c[0].high - c[0].low]
        for i in 1..<c.count {
            let pc = c[i - 1].close
            tr.append(max(c[i].high - c[i].low, abs(c[i].high - pc), abs(c[i].low - pc)))
        }
        var a = tr[1...n].reduce(0, +) / Double(n)
        out[n] = a
        for i in (n + 1)..<c.count {
            a = (a * Double(n - 1) + tr[i]) / Double(n)
            out[i] = a
        }
        return out
    }
}
