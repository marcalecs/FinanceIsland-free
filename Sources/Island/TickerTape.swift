import SwiftUI

struct IdlePrefsValues: Codable, Equatable {
    enum Speed: String, Codable, CaseIterable { case slow = "Slow", normal = "Normal", fast = "Fast" }
    enum Pin: String, Codable, CaseIterable { case quote = "Price", dayPnL = "Day P&L", tradeR = "Current R" }

    var tape = false
    var speed = Speed.normal
    var tapeQuotes = true
    var tapePnL = true
    var pins: [Pin] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IdlePrefsValues()
        tape = (try? c.decode(Bool.self, forKey: .tape)) ?? d.tape
        speed = (try? c.decode(Speed.self, forKey: .speed)) ?? d.speed
        tapeQuotes = (try? c.decode(Bool.self, forKey: .tapeQuotes)) ?? d.tapeQuotes
        tapePnL = (try? c.decode(Bool.self, forKey: .tapePnL)) ?? d.tapePnL
        pins = (try? c.decode([Pin].self, forKey: .pins)) ?? d.pins
    }

    var pointsPerSecond: Double {
        switch speed {
        case .slow: return 18
        case .normal: return 32
        case .fast: return 55
        }
    }
}

@MainActor
final class IdlePrefs: ObservableObject {
    static let shared = IdlePrefs()
    private static let key = "idlePrefs"

    @Published var v: IdlePrefsValues {
        didSet {
            guard v != oldValue else { return }
            if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: Self.key) }
            PortfolioPulse.shared.update()
        }
    }

    private init() {
        v = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(IdlePrefsValues.self, from: $0) } ?? IdlePrefsValues()
    }

    func reset() { v = IdlePrefsValues() }
}

@MainActor
final class PortfolioPulse: ObservableObject {
    static let shared = PortfolioPulse()

    @Published private(set) var dayPnL: Double?
    private var settings: AppSettings?
    private weak var rates: RateStore?
    private var task: Task<Void, Never>?

    func start(settings: AppSettings, rates: RateStore) {
        self.settings = settings
        self.rates = rates
        update()
    }

    var needed: Bool {
        let p = IdlePrefs.shared.v
        return (p.tape && p.tapePnL) || p.pins.contains(.dayPnL) || HolderPrefs.shared.v.moveAlerts
    }

    func update() {
        guard needed, settings != nil else { task?.cancel(); task = nil; return }
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    private func refresh() {
        guard let settings, let rates else { return }
        let store = LongTermStore.shared
        let hs = store.holdings(settings: settings, rates: rates)
        store.refresh(hs, base: settings.baseCurrency)
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            recompute()
        }
        recompute()
    }

    func recompute() {
        guard let settings, let rates else { return }
        let store = LongTermStore.shared
        let hs = store.holdings(settings: settings, rates: rates)
        var sum = 0.0, any = false
        for h in hs {
            guard let usd = store.valueUSD(h), let ch = store.change24h[h.symbol], ch > -100 else { continue }
            sum += usd - usd / (1 + ch / 100)
            any = true
        }
        dayPnL = any ? store.fromUSD(sum, to: settings.baseCurrency) ?? sum : nil
        MoveAlerts.check(hs, store: store)
    }

    func text(_ base: String) -> String? {
        dayPnL.map { (($0 >= 0) ? "+" : "−") + LongTermStore.money(abs($0), base) }
    }
}

@MainActor
struct TickerTape: View {
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var prefs = IdlePrefs.shared
    @ObservedObject private var pulse = PortfolioPulse.shared
    @State private var width: CGFloat = 1
    @State private var paused: Date?
    @State private var shift: TimeInterval = 0

    var body: some View {
        let items = segments
        if items.isEmpty {
            Image(systemName: "chart.line.uptrend.xyaxis")
        } else {
            TimelineView(.animation(paused: paused != nil)) { c in
                let t = (paused ?? c.date).timeIntervalSinceReferenceDate - shift
                let x = CGFloat((t * prefs.v.pointsPerSecond).truncatingRemainder(dividingBy: Double(max(width, 1))))
                HStack(spacing: 0) {
                    row(items)
                    row(items)
                }
                .fixedSize()
                .offset(x: -x)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                         .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("Ticker tape"))
            .accessibilityValue(items.map { $0.0 + " " + $0.1 }.joined(separator: ", "))
            .onHover { inside in
                if inside { paused = Date() }
                else if let p = paused { shift += Date().timeIntervalSince(p); paused = nil }
            }
        }
    }

    private func row(_ items: [(String, String, Color)]) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 4) {
                    Text(s.0)
                    Text(s.1).foregroundStyle(s.2)
                }
            }
        }
        .padding(.trailing, 14)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    private var segments: [(String, String, Color)] {
        var out: [(String, String, Color)] = []
        if prefs.v.tapePnL, let p = pulse.dayPnL, let s = pulse.text(settings.baseCurrency) {
            out.append((tr("Portfolio today"), s, TradeColors.pnl(p)))
        }
        if prefs.v.tapeQuotes {
            for a in settings.assets {
                guard let q = rates.quote(a) else { continue }
                out.append((tr("\(a.code) ") + Fmt.price(q.price, a),
                            (q.isUp ? "▲" : "▼") + String(format: "%.1f", abs(q.pct)) + "%", settings.color(a, up: q.isUp)))
            }
        }
        return out
    }
}

enum MenuBarPins {
    @MainActor
    static func title(settings: AppSettings, rates: RateStore) -> String {
        let trade = TradeDesk.shared.menuTitle
        if !trade.isEmpty { return trade }
        var parts: [String] = []
        for p in IdlePrefs.shared.v.pins.prefix(3) {
            switch p {
            case .quote:
                if let a = settings.pillAsset, let q = rates.quote(a) { parts.append(a.code + " " + Fmt.price(q.price, a)) }
            case .dayPnL:
                if let s = PortfolioPulse.shared.text(settings.baseCurrency) { parts.append(s) }
            case .tradeR:
                let r = JournalStats(JournalStore.shared.entries, filter: JournalFilter(from: Calendar.current.startOfDay(for: Date()))).totalR
                parts.append(tr("today \(TradeFormat.r(r))"))
            }
        }
        return parts.joined(separator: " · ")
    }
}
