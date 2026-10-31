import Foundation

struct ProbabilityModel: Sendable {
    let closes: [PricePoint]
    let source: DataSource
    let price: Double
    let sigmaNow: Double
    let sigmaLong: Double
    let crypto: Bool
    let barSeconds: TimeInterval
    let barsPerDay: Double

    struct Event: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
        let p: Double
        let base: Double
        var noSkill = false
        var level: Double? = nil
    }

    let highs: [Double]?
    let lows: [Double]?

    init?(candles: [Candle], source: DataSource, price: Double?, crypto: Bool) {
        let c = candles.filter { $0.close > 0 && $0.high > 0 && $0.low > 0 }
        self.init(points: c.map { PricePoint(time: $0.openTime, value: $0.close) }, source: source, price: price, crypto: crypto,
                  highs: c.map(\.high), lows: c.map(\.low))
    }

    init?(points: [PricePoint], source: DataSource, price: Double?, crypto: Bool,
          highs: [Double]? = nil, lows: [Double]? = nil) {
        let keep = points.indices.filter { points[$0].value > 0 }
        let p = keep.map { points[$0] }
        guard p.count >= 40 else { return nil }
        closes = p
        values = p.map(\.value)
        self.highs = highs.flatMap { h in h.count == points.count ? keep.map { h[$0] } : nil }
        self.lows = lows.flatMap { l in l.count == points.count ? keep.map { l[$0] } : nil }
        self.source = source
        self.crypto = crypto
        self.price = price ?? p.last!.value
        let r = zip(p.dropFirst(), p).map { log($0.value / $1.value) }
        let mean = r.reduce(0, +) / Double(r.count)
        sigmaLong = max(sqrt(r.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(r.count - 1, 1))), 1e-5)
        var v = r.prefix(20).map { $0 * $0 }.reduce(0, +) / 20
        for x in r.dropFirst(20) { v = 0.94 * v + 0.06 * x * x }
        sigmaNow = max(sqrt(v), 1e-5)
        let gaps = zip(p.dropFirst(), p).map { $0.time.timeIntervalSince($1.time) }.filter { $0 > 0 }.sorted()
        barSeconds = gaps.isEmpty ? 86_400 : gaps[gaps.count / 2]
        if barSeconds >= 20 * 3600 {
            barsPerDay = 1
        } else if crypto {
            barsPerDay = 86_400 / barSeconds
        } else {
            let cal = Calendar(identifier: .gregorian)
            let days = Set(p.map { cal.startOfDay(for: $0.time) })
            barsPerDay = Double(p.count) / Double(max(days.count, 1))
        }
    }

    var intraday: Bool { barSeconds < 20 * 3600 }

    func spanText(_ bars: Int) -> String {
        guard intraday else { return tr("\(bars) sessions") }
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.hour, .minute]
        var cal = Calendar(identifier: .gregorian)
        let lang = L10n.current
        cal.locale = lang == .system ? Locale.current : Locale(identifier: lang.rawValue)
        f.calendar = cal
        return f.string(from: Double(bars) * barSeconds) ?? "\(bars)"
    }

    let values: [Double]
    let cache = ModelCache()
    var sessionsPerYear: Double { barsPerDay * (crypto ? 365 : 252) }
    var annualVolNow: Double { sigmaNow * sqrt(sessionsPerYear) }

    static func phi(_ x: Double) -> Double { 0.5 * erfc(-x / 2.squareRoot()) }

    func touch(_ level: Double, h: Int, sigma: Double? = nil) -> Double {
        let s = (sigma ?? sigmaNow) * sqrt(Double(max(h, 1)))
        return min(0.99, 2 * (1 - Self.phi(abs(log(level / price)) / s)))
    }

    func range(_ d: Int, z: Double, drift: Double = 0) -> (lo: Double, hi: Double) {
        let s = sigmaNow * sqrt(Double(d)) * z, c = price * exp(drift * Double(d))
        return (c * exp(-s), c * exp(s))
    }

    var sma50Series: [Double?] {
        if let s = cache.sma50 { return s }
        let s = computeSMA50()
        cache.sma50 = s
        return s
    }

    private func computeSMA50() -> [Double?] {
        let v = values
        var out = [Double?](repeating: nil, count: v.count), sum = 0.0
        for i in v.indices {
            sum += v[i]
            if i >= 50 { sum -= v[i - 50] }
            if i >= 49 { out[i] = sum / 50 }
        }
        return out
    }

    func historicalTouch(_ move: Double, h: Int) -> Double? {
        let v = values
        guard v.count > h + 20 else { return nil }
        var hit = 0, n = 0
        for i in 0..<(v.count - h) {
            let w = v[(i + 1)...(i + h)]
            let ok = move >= 0 ? (w.max()! / v[i] - 1) >= move : (w.min()! / v[i] - 1) <= move
            if ok { hit += 1 }
            n += 1
        }
        return Double(hit) / Double(n)
    }

    private func realised(_ r: [Double], from i: Int, _ n: Int) -> Double? {
        guard i >= 0, i + n <= r.count else { return nil }
        let w = r[i..<(i + n)]
        return sqrt(w.map { $0 * $0 }.reduce(0, +) / Double(n))
    }

    func events(h: Int, up: Double, down: Double) -> [Event] {
        let key = "\(h)|\(up)|\(down)"
        if let hit = cache.events[key] { return hit }
        let out = computeEvents(h: h, up: up, down: down)
        if cache.events.count > 200 { cache.events = [:] }
        cache.events[key] = out
        return out
    }

    private func computeEvents(h: Int, up: Double, down: Double) -> [Event] {
        var out: [Event] = []
        let fmt = { (x: Double) in String(format: "%+.1f%%", (x / price - 1) * 100) }

        let window = intraday ? h : 10
        let move: Double = intraday ? max(0.001, (1.5 * sigmaLong * sqrt(Double(h)) * 1000).rounded() / 1000)
                                    : crypto ? 0.08 : 0.02
        let pu = touch(price * (1 + move), h: window), pd = touch(price * (1 - move), h: window)
        let bigP = min(0.99, 1 - (1 - pu) * (1 - pd))
        let bigBase = values.count > 30 ? bigShare(move, h: window) : bigP
        out.append(Event(id: "big", title: "Sharp move",
                         detail: intraday ? "more than ±\(String(format: move < 0.01 ? "%.1f" : "%.0f", move * 100))% within \(spanText(h))"
                                          : String(format: "more than ±%.0f%% within 10 sessions", move * 100),
                         p: bigP, base: bigBase))

        out.append(Event(id: "up", title: "Reaches %@", detail: intraday ? "\(fmt(up)) within \(spanText(h))" : "\(fmt(up)) within \(h) sessions",
                         p: touch(up, h: h), base: historicalTouch(up / price - 1, h: h) ?? touch(up, h: h, sigma: sigmaLong),
                         level: up))
        out.append(Event(id: "down", title: "Falls to %@", detail: intraday ? "\(fmt(down)) within \(spanText(h))" : "\(fmt(down)) within \(h) sessions",
                         p: touch(down, h: h), base: historicalTouch(down / price - 1, h: h) ?? touch(down, h: h, sigma: sigmaLong),
                         level: down))

        if let nervous = nervous(h: h) { out.append(nervous) }

        let v = values
        let k = intraday ? h : 5
        if v.count > 20 + k {
            let ups = (0..<(v.count - k)).filter { v[$0 + k] > v[$0] }.count
            let share = Double(ups) / Double(v.count - k)
            out.append(Event(id: "dir", title: intraday ? "Up over \(spanText(k))" : "Up over 5 sessions",
                             detail: "direction is not predicted: this is how often it happened",
                             p: share, base: share, noSkill: true))
        }
        return out
    }

    private func bigShare(_ move: Double, h: Int) -> Double {
        let v = values
        var hit = 0
        for i in 0..<(v.count - h) {
            let w = v[(i + 1)...(i + h)]
            if w.max()! / v[i] - 1 >= move || w.min()! / v[i] - 1 <= -move { hit += 1 }
        }
        return Double(hit) / Double(v.count - h)
    }

    private func nervous(h: Int) -> Event? {
        let r = zip(values.dropFirst(), values).map { log($0 / $1) }
        guard r.count > 20 + h + 30 else { return nil }
        var trailing: [Double] = [], ahead: [Double] = []
        for i in 20...(r.count - h) {
            guard let t = realised(r, from: i - 20, 20), let a = realised(r, from: i, h) else { continue }
            trailing.append(t); ahead.append(a)
        }
        let sorted = trailing.sorted()
        let threshold = 1.25 * sorted[sorted.count / 2]
        let now = realised(r, from: r.count - 20, 20) ?? sigmaNow
        let base = Double(ahead.filter { $0 > threshold }.count) / Double(ahead.count)
        let idx = trailing.indices.sorted { abs(trailing[$0] - now) < abs(trailing[$1] - now) }
            .prefix(max(10, trailing.count * 2 / 5))
        let p = Double(idx.filter { ahead[$0] > threshold }.count) / Double(idx.count)
        let annual = threshold * sqrt(sessionsPerYear) * 100
        return Event(id: "vol", title: "Nervous market",
                     detail: intraday ? "volatility above \(String(format: "%.0f", annual))% a year over \(spanText(h))"
                                      : String(format: "volatility above %.0f%% a year over %d sessions", annual, h),
                     p: p, base: base)
    }

}

extension ProbabilityModel {
    var riskScore: Int {
        var peak = 0.0, dd = 0.0
        for v in values { peak = max(peak, v); dd = min(dd, v / peak - 1) }
        let s = 0.6 * min(annualVolNow / 0.6, 1) + 0.4 * min(abs(dd) / 0.3, 1)
        return Int((s * 100).rounded())
    }

    var isLive: Bool {
        guard let t = closes.last?.time else { return false }
        return Date().timeIntervalSince(t.addingTimeInterval(barSeconds)) < 2 * barSeconds + 60
    }

    var lastClose: Date { (closes.last?.time ?? Date()).addingTimeInterval(intraday ? barSeconds : 0) }

    func sessionDate(_ d: Int) -> Date {
        if intraday { return Date().addingTimeInterval(barSeconds * Double(d)) }
        let cal = Calendar(identifier: .gregorian)
        var date = closes.last?.time ?? Date(), left = d
        while left > 0 {
            date = cal.date(byAdding: .day, value: 1, to: date)!
            if crypto || !cal.isDateInWeekend(date) { left -= 1 }
        }
        return date
    }
}

final class ModelCache: @unchecked Sendable {
    var events: [String: [ProbabilityModel.Event]] = [:]
    var sma50: [Double?]?
}
