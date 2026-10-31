import Foundation
import SwiftUI

@MainActor
final class ChartModel: ObservableObject {
    enum Style: String, CaseIterable, Identifiable { case candles = "Candles", line = "Line"; var id: String { rawValue } }
    enum Indicator: String, CaseIterable, Identifiable {
        case ma20 = "MA 20", ma50 = "MA 50", ema9 = "EMA 9", bands = "Bollinger", volume = "Volume", rsi = "RSI 14", macd = "MACD", plan = "Plan"
        var id: String { rawValue }
    }
    enum Tool: String, CaseIterable, Identifiable {
        case cursor, hline, trend
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .cursor: return "cursorarrow"
            case .hline: return "minus"
            case .trend: return "line.diagonal"
            }
        }
        var title: String {
            switch self {
            case .cursor: return "Crosshair"
            case .hline: return "Horizontal line"
            case .trend: return "Trend line"
            }
        }
    }
    struct Drawing: Identifiable, Equatable {
        enum Kind: Equatable { case hline(Double), trend(Date, Double, Date, Double) }
        let id = UUID()
        var kind: Kind
    }

    let subject: HubSubject
    let plan: (entry: Double, stop: Double, target: Double)?
    @Published var tf: ChartTF { didSet { if tf != oldValue { load() } } }
    @Published private(set) var candles: [Candle] = []
    @Published private(set) var source = ""
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published var style: Style = .candles
    @Published var indicators: Set<Indicator> = [.ma20, .ma50, .volume, .plan] {
        didSet { UserDefaults.standard.set(indicators.map(\.rawValue), forKey: key("indicators")) }
    }
    @Published var tool: Tool = .cursor
    @Published var drawings: [Drawing] = []
    @Published var visible: Double = 120 {
        didSet { UserDefaults.standard.set(visible, forKey: key("visible")) }
    }
    @Published var offset: Double = 0
    @Published var priceScale: Double = 1 {
        didSet { UserDefaults.standard.set(priceScale, forKey: key("scale")) }
    }
    private(set) var ma20: [Double?] = [], ma50: [Double?] = [], ema9: [Double?] = []
    private(set) var bandUp: [Double?] = [], bandDown: [Double?] = []
    private(set) var rsi14: [Double?] = [], macdLine: [Double?] = [], macdSignal: [Double?] = []

    private func key(_ name: String) -> String { "chart." + subject.id + "." + name }
    private var timer: Timer?
    private var socket: URLSessionWebSocketTask?
    @Published private(set) var live = false
    @Published private(set) var lastTick: Date?

    init(subject: HubSubject, plan: (entry: Double, stop: Double, target: Double)?, tf: ChartTF = .m15) {
        self.subject = subject
        self.plan = plan
        self.tf = tf
        if let saved = UserDefaults.standard.stringArray(forKey: key("indicators")) {
            indicators = Set(saved.compactMap(Indicator.init(rawValue:)))
        }
        load()
    }

    var hasSavedIndicators: Bool { UserDefaults.standard.object(forKey: key("indicators")) != nil }
    private var restoredZoom = false

    private func restoreZoom() {
        guard !restoredZoom else { return }
        restoredZoom = true
        let d = UserDefaults.standard
        if d.object(forKey: key("visible")) != nil { visible = max(20, min(d.double(forKey: key("visible")), Double(max(candles.count, 20)))) }
        if d.object(forKey: key("scale")) != nil { priceScale = d.double(forKey: key("scale")) }
    }

    func resume() {
        guard socket == nil && timer == nil else { return }
        load(quiet: true)
        startLive()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        live = false
    }

    func startLive() {
        stop()
        if let sym = ChartFeed.binanceSymbol(subject) {
            stream(sym)
        } else {
            let every: TimeInterval = 15
            timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            live = true
        }
    }

    private func poll() {
        guard let since = candles.last?.openTime else { return }
        let s = subject, tf = tf
        Task {
            guard let fresh = try? await ChartFeed.latest(s, tf: tf, since: since), tf == self.tf else { return }
            apply(fresh)
        }
    }

    private func stream(_ symbol: String) {
        let iv = tf == .d1 ? "1d" : ChartFeed.interval(tf)
        guard let url = URL(string: "wss://stream.binance.com:9443/ws/\(symbol.lowercased())@kline_\(iv)") else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        live = true
        receive(task)
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            let text: String? = { if case .success(.string(let t)) = result { return t }; return nil }()
            let failed: Bool = { if case .failure = result { return true }; return false }()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.socket === task else { return }
                    if failed {
                        self.live = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            MainActor.assumeIsolated { if self.socket === task { self.startLive() } }
                        }
                        return
                    }
                    if let text, let c = Self.kline(text) { self.apply([c]) }
                    self.receive(task)
                }
            }
        }
    }

    private static func kline(_ text: String) -> Candle? {
        guard let d = text.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let k = o["k"] as? [String: Any], let t = k["t"] as? Double,
              let op = Double(k["o"] as? String ?? ""), let hi = Double(k["h"] as? String ?? ""),
              let lo = Double(k["l"] as? String ?? ""), let cl = Double(k["c"] as? String ?? ""),
              let v = Double(k["v"] as? String ?? "") else { return nil }
        return Candle(openTime: Date(timeIntervalSince1970: t / 1000), open: op, high: hi, low: lo, close: cl, volume: v)
    }

    private func apply(_ fresh: [Candle]) {
        guard !fresh.isEmpty else { return }
        var c = candles
        var added = 0
        for x in fresh.sorted(by: { $0.openTime < $1.openTime }) {
            if let l = c.last, x.openTime == l.openTime { c[c.count - 1] = x }
            else if let l = c.last, x.openTime > l.openTime { c.append(x); added += 1 }
            else if let i = c.lastIndex(where: { $0.openTime == x.openTime }) { c[i] = x }
        }
        if added > 0 && offset < 0 { offset -= Double(added) }
        candles = c
        recompute()
        lastTick = Date()
        live = true
    }

    func load(quiet: Bool = false) {
        let s = subject, tf = tf
        if !quiet { loading = true; error = nil }
        Task {
            do {
                let r = try await ChartFeed.candles(s, tf: tf)
                guard tf == self.tf else { return }
                let fresh = candles.isEmpty || !quiet
                candles = r.candles
                source = r.source
                recompute()
                if fresh { fit(); restoreZoom() }
                error = r.candles.isEmpty ? "No candles for this timeframe" : nil
                if !quiet { startLive() }
            } catch {
                if !quiet { self.error = "No connection to the price sources" }
                AppLog.write("chart \(s.short) \(tf.rawValue) failed:", error.localizedDescription)
            }
            loading = false
        }
    }

    private func recompute() {
        let c = candles.map(\.close)
        ma20 = Indicators.sma(c, 20); ma50 = Indicators.sma(c, 50); ema9 = Indicators.ema(c, 9)
        rsi14 = Indicators.rsi(c, 14)
        (macdLine, macdSignal) = Indicators.macd(c)
        var up: [Double?] = [], dn: [Double?] = []
        for i in c.indices {
            guard let m = ma20[i], i >= 19 else { up.append(nil); dn.append(nil); continue }
            let w = c[(i - 19)...i]
            let sd = sqrt(w.map { ($0 - m) * ($0 - m) }.reduce(0, +) / 20)
            up.append(m + 2 * sd); dn.append(m - 2 * sd)
        }
        bandUp = up; bandDown = dn
    }

    var first: Double { Double(candles.count) - visible - offset }

    func fit() {
        visible = Double(min(max(candles.count, 20), 150))
        offset = 4
        priceScale = 1
    }

    func zoom(_ factor: Double, anchor: Double) {
        let n = Double(candles.count)
        guard n > 0, factor.isFinite, factor > 0 else { return }
        let iAnchor = first + anchor * visible
        let v = min(max(visible / factor, 12), max(n * 1.3, 40))
        let newFirst = iAnchor - anchor * v
        visible = v
        offset = clampOffset(n - v - newFirst)
    }

    func pan(bars: Double) { offset = clampOffset(offset + bars) }

    private func clampOffset(_ o: Double) -> Double {
        let n = Double(candles.count)
        return min(max(o, -(n - 10)), visible * 0.6)
    }

    func index(of date: Date) -> Double {
        guard let f = candles.first, let l = candles.last else { return 0 }
        if date <= f.openTime { return date.timeIntervalSince(f.openTime) / tf.seconds }
        if date >= l.openTime { return Double(candles.count - 1) + date.timeIntervalSince(l.openTime) / tf.seconds }
        var lo = 0, hi = candles.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if candles[mid].openTime <= date { lo = mid } else { hi = mid }
        }
        let span = candles[hi].openTime.timeIntervalSince(candles[lo].openTime)
        return Double(lo) + (span > 0 ? date.timeIntervalSince(candles[lo].openTime) / span : 0)
    }

    func date(at index: Double) -> Date {
        guard let f = candles.first, let l = candles.last else { return Date() }
        if index <= 0 { return f.openTime.addingTimeInterval(index * tf.seconds) }
        let n = candles.count
        if index >= Double(n - 1) { return l.openTime.addingTimeInterval((index - Double(n - 1)) * tf.seconds) }
        let i = Int(index), frac = index - Double(i)
        return candles[i].openTime.addingTimeInterval(frac * candles[i + 1].openTime.timeIntervalSince(candles[i].openTime))
    }
}

@MainActor
final class ChartHover: ObservableObject {
    @Published var point: CGPoint?
    @Published var draft: ChartModel.Drawing?
}
