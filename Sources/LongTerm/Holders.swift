import AppKit
import SwiftUI

struct HolderPrefsValues: Codable, Equatable {
    var moveAlerts = false
    var movePercent = 5.0
    var weekly = true
    var weekday = 2
    var hour = 9
    var weeklyClosed: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HolderPrefsValues()
        moveAlerts = (try? c.decode(Bool.self, forKey: .moveAlerts)) ?? d.moveAlerts
        movePercent = (try? c.decode(Double.self, forKey: .movePercent)) ?? d.movePercent
        weekly = (try? c.decode(Bool.self, forKey: .weekly)) ?? d.weekly
        weekday = (try? c.decode(Int.self, forKey: .weekday)) ?? d.weekday
        hour = (try? c.decode(Int.self, forKey: .hour)) ?? d.hour
        weeklyClosed = try? c.decode(Date.self, forKey: .weeklyClosed)
    }
}

@MainActor
final class HolderPrefs: ObservableObject {
    static let shared = HolderPrefs()
    private static let key = "holderPrefs"

    @Published var v: HolderPrefsValues {
        didSet {
            guard v != oldValue else { return }
            if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: Self.key) }
            PortfolioPulse.shared.update()
        }
    }

    private init() {
        v = UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(HolderPrefsValues.self, from: $0) } ?? HolderPrefsValues()
    }

    func reset() { v = HolderPrefsValues() }
}

enum MoveAlerts {
    private static let key = "moveAlertsSent"

    @MainActor
    static func check(_ holdings: [Holding], store: LongTermStore) {
        let p = HolderPrefs.shared.v
        guard p.moveAlerts, p.movePercent > 0 else { return }
        let today = BenchmarkStore.dayKey(Date())
        var sent = Set(UserDefaults.standard.stringArray(forKey: key) ?? []).filter { $0.hasSuffix(today) }
        for symbol in Set(holdings.map(\.symbol)) where !BenchmarkStore.stable.contains(symbol) {
            guard let ch = store.change24h[symbol], abs(ch) >= p.movePercent else { continue }
            let k = symbol + "|" + today
            guard !sent.contains(k) else { continue }
            sent.insert(k)
            let move = String(format: "%@%.1f%%", ch >= 0 ? "▲ +" : "▼ −", abs(ch))
            AlertStore.shared.notify(id: "move-" + k, title: tr("\(symbol) in your portfolio: \(move) in 24 h"),
                                     body: tr("Your threshold is \(Fmt.number(p.movePercent, min: 0, max: 1))%. One notice per position a day."),
                                     thread: symbol)
        }
        UserDefaults.standard.set(Array(sent), forKey: key)
    }
}

@MainActor
final class WeeklySummary: ObservableObject {
    static let shared = WeeklySummary()

    struct Mover: Identifiable, Equatable {
        let symbol: String
        let pct: Double
        let value: Double?
        let headline: NewsItem?
        var id: String { symbol }
    }

    struct Data: Equatable {
        var movers: [Mover] = []
        var benchmark: BenchmarkStore.Result?
        var journalR = 0.0
        var journalNet = 0.0
        var journalTrades = 0
        var mistakes: Double?
        var made = Date()
    }

    @Published private(set) var data: Data?
    @Published private(set) var loading = false
    @Published var forced = false

    static func dueDate(_ p: HolderPrefsValues, now: Date = Date()) -> Date? {
        let cal = Calendar.current
        var c = DateComponents()
        c.weekday = p.weekday
        c.hour = p.hour
        return cal.nextDate(after: now, matching: c, matchingPolicy: .nextTime, direction: .backward)
    }

    func shouldShow(_ p: HolderPrefsValues) -> Bool {
        if forced { return true }
        guard p.weekly, let due = Self.dueDate(p) else { return false }
        return (p.weeklyClosed ?? .distantPast) < due && Date().timeIntervalSince(due) < 7 * 86_400
    }

    func close() {
        forced = false
        HolderPrefs.shared.v.weeklyClosed = Date()
    }

    func load(_ holdings: [Holding], base: String) {
        if let d = data, Date().timeIntervalSince(d.made) < 3600 { return }
        guard !loading else { return }
        loading = true
        let store = LongTermStore.shared
        let parts = holdings.map { (symbol: $0.symbol, crypto: $0.crypto, amount: $0.amount, usd: store.toUSD(1, store.currency($0.symbol)) ?? 1) }
        let usdPerBase = store.toUSD(1, base) ?? 1
        Task {
            var out = Data()
            var bySymbol: [String: (crypto: Bool, amount: Double, usd: Double)] = [:]
            for p in parts where !BenchmarkStore.stable.contains(p.symbol) {
                let v = bySymbol[p.symbol]
                bySymbol[p.symbol] = (p.crypto, (v?.amount ?? 0) + p.amount, p.usd)
            }
            var movers: [Mover] = []
            for (s, v) in bySymbol {
                let closes = await BenchmarkStore.daily(s, crypto: v.crypto, from: Date().addingTimeInterval(-10 * 86_400))
                let keys = closes.keys.sorted()
                let weekAgo = BenchmarkStore.dayKey(Date().addingTimeInterval(-7 * 86_400))
                guard let last = keys.last.flatMap({ closes[$0] }), let then = keys.last(where: { $0 <= weekAgo }).flatMap({ closes[$0] }),
                      then > 0 else { continue }
                let change = (last - then) * v.amount * v.usd / max(usdPerBase, 1e-9)
                movers.append(Mover(symbol: s, pct: last / then - 1, value: change,
                                    headline: PortfolioNews.shared.items.first { $0.symbol == s }?.news))
            }
            out.movers = Array(movers.sorted { abs($0.value ?? 0) > abs($1.value ?? 0) }.prefix(3))
            out.benchmark = await BenchmarkStore.compute(parts, from: Date().addingTimeInterval(-7 * 86_400))
            let week = JournalStats(JournalStore.shared.entries, filter: JournalFilter(from: Date().addingTimeInterval(-7 * 86_400)))
            out.journalR = week.totalR
            out.journalNet = week.netPnL
            out.journalTrades = week.totalTrades
            if LicenseStore.shared.isActive, week.totalTrades > 0 {
                out.mistakes = week.mistakeCost(Set(TradePrefs.shared.v.mistakeTags)).money
            }
            data = out
            loading = false
        }
    }
}

@MainActor
struct WeeklySummaryCard: View {
    let holdings: [Holding]
    let base: String
    @ObservedObject private var summary = WeeklySummary.shared
    @ObservedObject private var prefs = HolderPrefs.shared
    @Environment(\.look) private var look

    var body: some View {
        if summary.shouldShow(prefs.v) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "calendar")
                    Text(tr("Your week")).font(.system(size: 14, weight: .bold))
                    Spacer()
                    Button { summary.close() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                        .accessibilityLabel(tr("Close the weekly summary"))
                }
                if let d = summary.data {
                    if d.movers.isEmpty {
                        Text(tr("No price history for your positions yet.")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(d.movers) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(m.symbol).font(.system(size: 12.5, weight: .bold)).frame(width: 60, alignment: .leading)
                                Text((m.pct >= 0 ? "▲ +" : "▼ −") + String(format: "%.1f%%", abs(m.pct * 100)))
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(look.pnl(m.pct))
                                if let v = m.value {
                                    Text((v >= 0 ? "+" : "−") + LongTermStore.money(abs(v), base))
                                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                                }
                                Spacer()
                            }
                            if let h = m.headline {
                                Button { if let u = URL(string: h.link) { NSWorkspace.shared.open(u) } } label: {
                                    Text(h.title + " · " + h.publisher).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let b = d.benchmark, let p = b.portfolio.last, let s = b.spx.last, let c = b.btc.last {
                        Text(tr("Portfolio \(Self.pct(p)) · S&P 500 \(Self.pct(s)) · BTC \(Self.pct(c)) over 7 days"))
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                    }
                    if d.journalTrades > 0 {
                        Text(tr("Journal: \(d.journalTrades) trades · \(TradeFormat.r(d.journalR)) · \(TradeFormat.money(d.journalNet, unit: base))"))
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                    }
                    if let m = d.mistakes, m != 0 {
                        Text(tr("Trades with mistake tags this week: \(TradeFormat.money(m, unit: base))"))
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                    }
                } else {
                    Text(tr("Putting your week together…")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                Text(tr("Facts from your positions and journal, made on this Mac. No advice."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
            .padding(14)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
            .onAppear { summary.load(holdings, base: base) }
        }
    }

    static func pct(_ v: Double) -> String { (v >= 0 ? "▲ +" : "▼ −") + String(format: "%.1f%%", abs(v * 100)) }
}

struct FiftyTwoWeekBar: View {
    let symbol: String
    let crypto: Bool
    let price: Double?
    let format: (Double) -> String
    @State private var range: (lo: Double, hi: Double)?
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("52-week range (daily closes)")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            if let r = range, r.hi > r.lo {
                let f = price.map { CGFloat(min(max(($0 - r.lo) / (r.hi - r.lo), 0), 1)) }
                HStack(spacing: 8) {
                    Text(format(r.lo)).font(.system(size: 11.5).monospacedDigit())
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(look.theme.chip).frame(height: 5)
                            if let f {
                                Circle().fill(.white).frame(width: 10, height: 10).offset(x: (g.size.width - 10) * f)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 12)
                    Text(format(r.hi)).font(.system(size: 11.5).monospacedDigit())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("52-week range"))
                .accessibilityValue(tr("low \(format(r.lo)), high \(format(r.hi))") + (f.map { ", " + tr("price at \(Int(($0 * 100).rounded()))% of the range") } ?? ""))
            } else {
                Text("—").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
        .task(id: symbol) {
            let closes = await BenchmarkStore.daily(symbol, crypto: crypto, from: Date().addingTimeInterval(-365 * 86_400)).values
            if let lo = closes.min(), let hi = closes.max() { range = (lo, hi) }
        }
    }
}

@MainActor
final class Dividends: ObservableObject {
    static let shared = Dividends()
    struct Payment: Identifiable, Equatable {
        let symbol: String
        let date: Date
        let amount: Double
        var id: String { symbol + "\(date.timeIntervalSince1970)" }
    }
    @Published private(set) var payments: [Payment] = []
    @Published private(set) var loaded = false
    private var key = ""

    func load(_ symbols: [String]) {
        let k = symbols.sorted().joined(separator: ",")
        guard k != key else { return }
        key = k
        Task {
            var out: [Payment] = []
            for s in symbols {
                guard let enc = s.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                      let d = try? await HTTP.get("https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=2y&interval=1mo&events=div"),
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      let res = ((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
                      let divs = (res["events"] as? [String: Any])?["dividends"] as? [String: [String: Any]] else { continue }
                for v in divs.values {
                    guard let amount = (v["amount"] as? NSNumber)?.doubleValue, let t = (v["date"] as? NSNumber)?.doubleValue else { continue }
                    out.append(Payment(symbol: s, date: Date(timeIntervalSince1970: t), amount: amount))
                }
            }
            payments = out.sorted { $0.date > $1.date }
            loaded = true
        }
    }
}

@MainActor
struct DividendsCard: View {
    let symbols: [String]
    @ObservedObject private var dividends = Dividends.shared
    @Environment(\.look) private var look

    var body: some View {
        if !symbols.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Dividends of your stocks and ETFs")).font(.system(size: 14, weight: .bold))
                let recent = Array(dividends.payments.prefix(8))
                if recent.isEmpty {
                    Text(dividends.loaded ? tr("No dividends in the last two years.") : tr("Loading…"))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(recent) { p in
                    HStack(spacing: 8) {
                        Text(p.symbol).font(.system(size: 12, weight: .bold)).frame(width: 60, alignment: .leading)
                        Text(Fmt.date(p.date, "d MMM yyyy")).font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(Fmt.number(p.amount, min: 2, max: 4) + " " + tr("per share")).font(.system(size: 12).monospacedDigit())
                    }
                }
                Text(tr("Past payments (ex-dividend dates) as reported by Yahoo Finance; they may differ from your broker. Upcoming dates aren't shown: there's no free source we trust."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
            .onAppear { dividends.load(symbols) }
        }
    }
}

@MainActor
struct HolderSettings: View {
    @ObservedObject var state: IslandState
    @ObservedObject private var prefs = HolderPrefs.shared
    @Environment(\.look) private var look

    var body: some View {
        SettingsSection(title: "Your portfolio") {
            Row(title: "Notify when a position moves a lot", subtitle: "A macOS notification and a note in the island when a position moves more than this in 24 hours; once a day per position. Doesn't use the free alerts.") {
                HStack(spacing: 8) {
                    if prefs.v.moveAlerts {
                        TextField("", text: Binding(get: { String(format: "%g", prefs.v.movePercent) },
                                                    set: { if let x = Double($0.replacingOccurrences(of: ",", with: ".")), x > 0 { prefs.v.movePercent = x } }))
                            .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit()).multilineTextAlignment(.trailing)
                            .padding(.horizontal, 8).frame(width: 52, height: 28)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                        Text("%").font(.system(size: 13))
                    }
                    Switch(isOn: $prefs.v.moveAlerts)
                }
            }
            Row(title: "Weekly summary", subtitle: "A card in Portfolio: your biggest moves with headlines, the portfolio against the S&P 500 and BTC, and the journal's week. Facts only.") {
                Switch(isOn: $prefs.v.weekly)
            }
            if prefs.v.weekly {
                Row(title: "Shown from") {
                    HStack(spacing: 6) {
                        Picker("", selection: $prefs.v.weekday) {
                            ForEach(1...7, id: \.self) { d in Text(Calendar.current.weekdaySymbols[d - 1]).tag(d) }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 130)
                        Picker("", selection: $prefs.v.hour) {
                            ForEach(5...22, id: \.self) { h in Text(String(format: "%02d:00", h)).tag(h) }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 90)
                    }
                }
            }
            Row(title: "Show the weekly summary now", divider: false) {
                PillButton(title: "Show") {
                    WeeklySummary.shared.forced = true
                    state.mode = .longTerm
                }
            }
        }
    }
}
