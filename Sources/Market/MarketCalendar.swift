import SwiftUI

@MainActor
final class MarketCalendar: ObservableObject {
    static let shared = MarketCalendar()
    static let soonWindow: TimeInterval = 5 * 60

    struct Event: Identifiable, Equatable {
        enum Kind: String { case open, close }
        let exchange: String
        let kind: Kind
        let at: Date
        var id: String { exchange + kind.rawValue + "\(Int(at.timeIntervalSince1970))" }
    }

    struct Session: Equatable {
        let open: Date
        let close: Date
    }

    struct Exchange {
        let name: String
        let symbol: String
        let timeZone: String
        let hours: [(open: Int, close: Int)]
    }

    static let exchanges: [Exchange] = [
        Exchange(name: "US stocks", symbol: "SPY", timeZone: "America/New_York", hours: [(930, 1600)]),
        Exchange(name: "London", symbol: "^FTSE", timeZone: "Europe/London", hours: [(800, 1630)]),
        Exchange(name: "Frankfurt", symbol: "^GDAXI", timeZone: "Europe/Berlin", hours: [(900, 1730)]),
        Exchange(name: "Tokyo", symbol: "^N225", timeZone: "Asia/Tokyo", hours: [(900, 1130), (1230, 1530)]),
        Exchange(name: "Hong Kong", symbol: "^HSI", timeZone: "Asia/Hong_Kong", hours: [(930, 1200), (1300, 1600)]),
    ]

    @Published private(set) var sessions: [String: [Session]] = [:]
    @Published private(set) var confirmed: Set<String> = []
    @Published private(set) var soon: Event?
    private var reported: [String: Session] = [:]
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        rebuild()
        task = Task { [weak self] in
            var last = Date.distantPast
            while !Task.isCancelled {
                if Date().timeIntervalSince(last) > 1800 {
                    await self?.load()
                    last = Date()
                }
                self?.rebuild()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    var events: [Event] {
        sessions.flatMap { name, list in
            list.flatMap { [Event(exchange: name, kind: .open, at: $0.open), Event(exchange: name, kind: .close, at: $0.close)] }
        }
    }

    var upcoming: [Event] { events.filter { $0.at > Date() }.sorted { $0.at < $1.at } }

    static func planned(_ ex: Exchange, from now: Date, days: Int = 8) -> [Session] {
        guard let tz = TimeZone(identifier: ex.timeZone) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.startOfDay(for: now)
        var out: [Session] = []
        for d in -1..<days {
            guard let day = cal.date(byAdding: .day, value: d, to: start), !cal.isDateInWeekend(day) else { continue }
            for h in ex.hours {
                guard let o = cal.date(bySettingHour: h.open / 100, minute: h.open % 100, second: 0, of: day),
                      let c = cal.date(bySettingHour: h.close / 100, minute: h.close % 100, second: 0, of: day) else { continue }
                out.append(Session(open: o, close: c))
            }
        }
        return out
    }

    static func merge(_ planned: [Session], reported: Session?, timeZone: String) -> [Session] {
        guard let r = reported, let tz = TimeZone(identifier: timeZone) else { return planned }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let same = planned.filter { cal.isDate($0.open, inSameDayAs: r.open) }
        let others = planned.filter { !cal.isDate($0.open, inSameDayAs: r.open) }
        let clipped = same.compactMap { s -> Session? in
            let o = max(s.open, r.open), c = min(s.close, r.close)
            return c > o ? Session(open: o, close: c) : nil
        }
        return (others + (clipped.isEmpty ? [r] : clipped)).sorted { $0.open < $1.open }
    }

    private func rebuild() {
        let now = Date()
        var out: [String: [Session]] = [:]
        var sure: Set<String> = []
        for ex in Self.exchanges {
            let r = reported[ex.name]
            out[ex.name] = Self.merge(Self.planned(ex, from: now), reported: r, timeZone: ex.timeZone)
            if let r, r.close > now.addingTimeInterval(-12 * 3600) { sure.insert(ex.name) }
        }
        if out != sessions { sessions = out }
        if sure != confirmed { confirmed = sure }
        let next = upcoming.first { $0.at.timeIntervalSince(now) <= Self.soonWindow }
        if next != soon { soon = next }
    }

    private func load() async {
        for ex in Self.exchanges {
            guard let enc = ex.symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let d = try? await HTTP.get("https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=1d&interval=1d"),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let meta = (((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first)?["meta"] as? [String: Any],
                  let regular = (meta["currentTradingPeriod"] as? [String: Any])?["regular"] as? [String: Any],
                  let start = (regular["start"] as? NSNumber)?.doubleValue, let end = (regular["end"] as? NSNumber)?.doubleValue,
                  end > start else { continue }
            reported[ex.name] = Session(open: Date(timeIntervalSince1970: start), close: Date(timeIntervalSince1970: end))
        }
        rebuild()
    }

    static func title(_ e: Event) -> String {
        e.kind == .open ? tr("\(tr(e.exchange)) opens") : tr("\(tr(e.exchange)) closes")
    }

    static func countdown(_ at: Date, now: Date) -> String {
        let s = max(0, Int(at.timeIntervalSince(now)))
        if s < 3_600 { return String(format: "%d:%02d", s / 60, s % 60) }
        return TradeFormat.duration(Double(s))
    }

    func isOpen(_ exchange: String, now: Date = Date()) -> Bool? {
        guard let list = sessions[exchange], !list.isEmpty else { return nil }
        return list.contains { now >= $0.open && now < $0.close }
    }
}

struct MarketHoursCard: View {
    @ObservedObject private var calendar = MarketCalendar.shared
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { c in
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("Exchange hours")).font(.system(size: 14, weight: .bold))
                ForEach(MarketCalendar.exchanges, id: \.name) { ex in
                    let next = calendar.upcoming.first { $0.exchange == ex.name }
                    if let open = calendar.isOpen(ex.name, now: c.date) {
                        HStack(spacing: 8) {
                            Circle().fill(open ? TradeColors.profit : .white.opacity(0.3)).frame(width: 7, height: 7)
                            Text(tr(ex.name)).font(.system(size: 12.5, weight: .semibold)).frame(width: 110, alignment: .leading)
                            Text(open ? tr("open") : tr("closed")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            if let next {
                                Text(next.kind == .open ? tr("opens in \(MarketCalendar.countdown(next.at, now: c.date))")
                                                        : tr("closes in \(MarketCalendar.countdown(next.at, now: c.date))"))
                                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.75))
                            }
                            if calendar.confirmed.contains(ex.name) {
                                Image(systemName: "checkmark.seal").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                                    .help(tr("Today's times confirmed by the exchange data"))
                            }
                        }
                    }
                }
                Text(tr(calendar.confirmed.isEmpty
                        ? "Regular hours of each exchange. Holidays and short days show once Yahoo Finance answers."
                        : "Regular hours of each exchange; ✓ marks days confirmed by the exchange data through Yahoo Finance."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
    }
}
