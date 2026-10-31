import Foundation

enum TiltGuard {
    struct Settings: Codable, Equatable, Sendable {
        var dailyLoss = 0.0
        var dailyLossInR = false
        var maxTrades = 0
        var maxLossStreak = 0
        var pauseMinutes = 0
        var timeZone = ""

        var isOn: Bool { dailyLoss > 0 || maxTrades > 0 || maxLossStreak > 0 || pauseMinutes > 0 }
    }

    enum Reason: String, Sendable { case dailyLoss, maxTrades, lossStreak, pause }

    struct Block: Equatable, Sendable {
        let reason: Reason
        let until: Date
    }

    static func calendar(_ s: Settings) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: s.timeZone) ?? .current
        return c
    }

    static func nextMidnight(_ now: Date, _ s: Settings) -> Date {
        let c = calendar(s)
        return c.date(byAdding: .day, value: 1, to: c.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
    }

    static func today(_ entries: [JournalEntry], _ s: Settings, now: Date) -> [JournalEntry] {
        let c = calendar(s)
        return entries.filter { $0.kind == .trade && $0.tradeMode != .simulated && c.isDate($0.opened, inSameDayAs: now) }
    }

    static func dayLoss(_ entries: [JournalEntry], _ s: Settings, now: Date) -> Double {
        let c = calendar(s)
        let closed = entries.filter {
            $0.kind == .trade && $0.status == .closed && $0.tradeMode != .simulated && c.isDate($0.closedAt ?? $0.at, inSameDayAs: now)
        }
        let result = s.dailyLossInR ? closed.compactMap(\.rMultiple).reduce(0, +) : closed.compactMap(\.netPnL).reduce(0, +)
        return max(0, -result)
    }

    static func remaining(_ entries: [JournalEntry], _ s: Settings, now: Date) -> Double? {
        s.dailyLoss > 0 ? max(0, s.dailyLoss - dayLoss(entries, s, now: now)) : nil
    }

    static func check(_ entries: [JournalEntry], _ s: Settings, now: Date = Date()) -> Block? {
        guard s.isOn else { return nil }
        let midnight = nextMidnight(now, s)
        if s.dailyLoss > 0, dayLoss(entries, s, now: now) >= s.dailyLoss - 1e-9 { return Block(reason: .dailyLoss, until: midnight) }
        let day = today(entries, s, now: now)
        if s.maxTrades > 0, day.count >= s.maxTrades { return Block(reason: .maxTrades, until: midnight) }
        let closed = day.filter { $0.status == .closed }.sorted { ($0.closedAt ?? $0.at) < ($1.closedAt ?? $1.at) }
        if s.maxLossStreak > 0 {
            var streak = 0
            for e in closed.reversed() { if (e.rMultiple ?? 0) < 0 { streak += 1 } else { break } }
            if streak >= s.maxLossStreak { return Block(reason: .lossStreak, until: midnight) }
        }
        if s.pauseMinutes > 0 {
            let stops = entries.filter { $0.kind == .trade && $0.status == .closed && $0.tradeMode != .simulated && $0.exitReason == .stop }
            if let last = stops.compactMap({ $0.closedAt ?? $0.at }).max() {
                let until = last.addingTimeInterval(Double(s.pauseMinutes) * 60)
                if until > now { return Block(reason: .pause, until: until) }
            }
        }
        return nil
    }
}
