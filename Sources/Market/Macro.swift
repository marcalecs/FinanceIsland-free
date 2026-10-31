import SwiftUI

@MainActor
final class MacroStore: ObservableObject {
    static let shared = MacroStore()
    static let window: TimeInterval = 3_600

    enum Level: Int, Comparable {
        case calm, watch, stress
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        var title: String {
            switch self {
            case .calm: return "Calm"
            case .watch: return "Watch"
            case .stress: return "Stress"
            }
        }
    }

    struct Release: Identifiable {
        let name: String
        let at: Date
        var id: String { name + "\(Int(at.timeIntervalSince1970))" }
    }

    static let releases: [Release] = [
        ("Jobs report (NFP)", "2026-11-06T13:30:00Z"),
        ("CPI", "2026-11-10T13:30:00Z"),
        ("Fed decision (FOMC)", "2026-12-09T19:00:00Z"),
    ].compactMap { name, iso in ISO8601DateFormatter().date(from: iso).map { Release(name: name, at: $0) } }

    @Published private(set) var hy: Double?
    @Published private(set) var hyChange: Double?
    @Published private(set) var hyDate: Date?
    @Published private(set) var usdjpy: Double?
    @Published private(set) var usdjpyChange: Double?
    @Published private(set) var vix: Double?
    @Published private(set) var funding: Double?
    @Published private(set) var oiShare: Double?
    @Published private(set) var updated: Date?
    private var task: Task<Void, Never>?
    private var creditLoaded = Date.distantPast

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                try? await Task.sleep(nanoseconds: 300_000_000_000)
            }
        }
    }

    func next(_ now: Date = Date()) -> Release? { Self.releases.first { $0.at.addingTimeInterval(Self.window) > now } }

    func inWindow(_ now: Date = Date()) -> Release? {
        Self.releases.first { abs($0.at.timeIntervalSince(now)) < Self.window }
    }

    func calendarLevel(_ now: Date = Date()) -> Level {
        if inWindow(now) != nil { return .stress }
        if let n = next(now), n.at.timeIntervalSince(now) < 86_400 { return .watch }
        return .calm
    }

    var creditLevel: Level? {
        guard let hy else { return nil }
        let d = hyChange ?? 0
        if hy >= 4 || d >= 0.25 { return .stress }
        if hy >= 3.5 || d >= 0.1 { return .watch }
        return .calm
    }

    var yenLevel: Level? {
        guard usdjpyChange != nil || vix != nil else { return nil }
        if (usdjpyChange ?? 0) <= -0.015 || (vix ?? 0) > 25 { return .stress }
        if (usdjpyChange ?? 0) <= -0.0075 || (vix ?? 0) > 20 { return .watch }
        return .calm
    }

    var fundingLevel: Level? {
        guard let funding else { return nil }
        if funding > 0.0005 && (oiShare ?? 0) >= 0.999 { return .stress }
        if abs(funding) > 0.0005 { return .watch }
        return .calm
    }

    func level(_ now: Date = Date()) -> Level {
        ([calendarLevel(now)] + [creditLevel, yenLevel, fundingLevel].compactMap { $0 }).max() ?? .calm
    }


    private func load() async {
        async let fx = Self.daily("JPY=X")
        async let vol = Self.daily("^VIX")
        async let fund = try? HTTP.json("https://fapi.binance.com/fapi/v1/premiumIndex?symbol=BTCUSDT")
        async let oi = try? HTTP.json("https://fapi.binance.com/futures/data/openInterestHist?symbol=BTCUSDT&period=1d&limit=30")
        if Date().timeIntervalSince(creditLoaded) > 3_600, let c = await Self.credit() {
            hy = c.last; hyChange = c.change; hyDate = c.date
            creditLoaded = Date()
        }
        if let j = await fx { usdjpy = j.price; usdjpyChange = j.change }
        if let v = await vol { vix = v.price }
        if let f = (await fund as? [String: Any])?["lastFundingRate"] as? String { funding = Double(f) }
        if let rows = await oi as? [[String: Any]] {
            let values = rows.compactMap { ($0["sumOpenInterest"] as? String).flatMap(Double.init) }
            if let last = values.last, let top = values.max(), top > 0 { oiShare = last / top }
        }
        updated = Date()
    }

    private static func daily(_ symbol: String) async -> (price: Double, change: Double)? {
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let d = try? await HTTP.get("https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=5d&interval=1d"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let result = ((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let price = ((result["meta"] as? [String: Any])?["regularMarketPrice"] as? NSNumber)?.doubleValue,
              let quote = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first,
              let closes = (quote["close"] as? [Any])?.compactMap({ ($0 as? NSNumber)?.doubleValue }),
              closes.count >= 2, let prev = closes.dropLast().last, prev > 0 else { return nil }
        return (price, price / prev - 1)
    }

    private static func credit() async -> (last: Double, change: Double?, date: Date)? {
        guard let d = try? await HTTP.get("https://fred.stlouisfed.org/graph/fredgraph.csv?id=BAMLH0A0HYM2"),
              let text = String(data: d, encoding: .utf8) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        let rows: [(Date, Double)] = text.split(whereSeparator: \.isNewline).suffix(20).compactMap { line in
            let p = line.split(separator: ",")
            guard p.count == 2, let day = f.date(from: String(p[0])), let v = Double(p[1]) else { return nil }
            return (day, v)
        }
        guard let last = rows.last else { return nil }
        let back = rows.count > 5 ? rows[rows.count - 6].1 : nil
        return (last.1, back.map { last.1 - $0 }, last.0)
    }
}

struct MacroCard: View {
    @ObservedObject private var macro = MacroStore.shared
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { c in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(tr("Macro risk")).font(.system(size: 14, weight: .bold))
                    chip(macro.level(c.date))
                    Spacer()
                    if let n = macro.next(c.date) {
                        Text(n.at > c.date ? tr("\(tr(n.name)) in \(MarketCalendar.countdown(n.at, now: c.date))") : tr("\(tr(n.name)) just out"))
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                    }
                }
                HStack(spacing: 8) {
                    tile(tr("Calendar"), calendarValue(c.date), macro.calendarLevel(c.date),
                         tr("Within an hour of a jobs, CPI or Fed release prices jump both ways. Dates from the official BLS and Fed schedules."))
                    tile(tr("Credit"), creditValue, macro.creditLevel,
                         tr("US high-yield spread (FRED). Stress at 4% or a rise of 0.25 points in 5 trading days: risk appetite is drying up."))
                    tile(tr("Yen & VIX"), yenValue, macro.yenLevel,
                         tr("USD/JPY falling 1.5% in a day or VIX above 25 has marked carry-trade unwinds, as in August 2024."))
                    tile(tr("BTC funding"), fundingValue, macro.fundingLevel,
                         tr("Funding above 0.05% per 8 hours with open interest at a 30-day high means crowded longs."))
                }
                Text(tr("Risk conditions, not a forecast. Macro figures come from FRED and Yahoo Finance and can lag by a day."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
        .onAppear { macro.start() }
    }

    func color(_ l: MacroStore.Level?) -> Color {
        switch l {
        case .calm: return look.trend.green
        case .watch: return Accent.orange.color
        case .stress: return look.trend.red
        case nil: return .white.opacity(0.3)
        }
    }

    func chip(_ l: MacroStore.Level) -> some View {
        Text(tr(l.title)).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color(l))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(color(l).opacity(0.15)))
    }

    func tile(_ title: String, _ value: String, _ level: MacroStore.Level?, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color(level)).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
        .help(help)
    }

    func calendarValue(_ now: Date) -> String {
        if let r = macro.inWindow(now) { return tr("\(tr(r.name)) window") }
        guard let n = macro.next(now) else { return tr("No releases set") }
        return Fmt.date(n.at, "d MMM HH:mm")
    }

    var creditValue: String {
        guard let hy = macro.hy else { return "—" }
        return String(format: "%.2f%%", hy) + (macro.hyChange.map { String(format: " %+.2f", $0) } ?? "")
    }

    var yenValue: String {
        let jpy = macro.usdjpyChange.map { String(format: "%+.1f%%", $0 * 100) }
        let vix = macro.vix.map { String(format: "VIX %.0f", $0) }
        let parts = [jpy, vix].compactMap { $0 }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    var fundingValue: String {
        guard let f = macro.funding else { return "—" }
        return String(format: "%+.3f%%", f * 100) + (macro.oiShare.map { String(format: " · OI %.0f%%", $0 * 100) } ?? "")
    }
}
