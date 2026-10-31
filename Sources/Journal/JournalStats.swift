import Foundation

struct JournalFilter: Sendable, Equatable {
    enum Source: String, Sendable, CaseIterable { case manual, paper, binance, wallet }

    var from: Date? = nil
    var to: Date? = nil
    var modes: Set<JournalEntry.Mode> = [.manual, .paper]
    var tag: String? = nil
    var sources: Set<Source>? = nil

    static let standard = JournalFilter()

    static func source(_ e: JournalEntry) -> Source {
        switch e.importedFrom {
        case "binance": return .binance
        case "wallet": return .wallet
        default: return e.tradeMode == .manual ? .manual : .paper
        }
    }

    func includes(_ e: JournalEntry) -> Bool {
        guard e.kind == .trade, e.status == .closed, modes.contains(e.tradeMode) else { return false }
        let t = e.closedAt ?? e.at
        if let from, t < from { return false }
        if let to, t >= to { return false }
        if let tag, !e.allTags.contains(tag) { return false }
        if let sources, !sources.contains(Self.source(e)) { return false }
        return true
    }
}

struct JournalStats: Sendable {
    let trades: [JournalEntry]
    let rs: [Double]

    init(_ entries: [JournalEntry], filter: JournalFilter = .standard) {
        trades = entries.filter(filter.includes).sorted { ($0.closedAt ?? $0.at) < ($1.closedAt ?? $1.at) }
        rs = trades.compactMap(\.rMultiple)
    }

    var totalTrades: Int { trades.count }
    var wins: [Double] { rs.filter { $0 > 0 } }
    var losses: [Double] { rs.filter { $0 < 0 } }
    var outcomes: [Double] { trades.compactMap(\.outcome) }
    var winRate: Double? {
        let o = outcomes
        return o.isEmpty ? nil : Double(o.filter { $0 > 0 }.count) / Double(o.count)
    }
    var grossPnL: Double { trades.compactMap(\.grossPnL).reduce(0, +) }
    var commission: Double { trades.compactMap(\.commission).reduce(0, +) }
    var netPnL: Double { trades.compactMap(\.netPnL).reduce(0, +) }
    var totalR: Double { rs.reduce(0, +) }
    var avgR: Double? { rs.isEmpty ? nil : totalR / Double(rs.count) }

    var profitFactor: Double? {
        guard !rs.isEmpty else { return nil }
        let win = wins.reduce(0, +), loss = -losses.reduce(0, +)
        return loss > 0 ? win / loss : (win > 0 ? .infinity : nil)
    }

    var expectancy: Double? {
        guard !rs.isEmpty else { return nil }
        let n = Double(rs.count)
        let pWin = Double(wins.count) / n, pLoss = Double(losses.count) / n
        let avgWin = wins.isEmpty ? 0 : wins.reduce(0, +) / Double(wins.count)
        let avgLoss = losses.isEmpty ? 0 : -losses.reduce(0, +) / Double(losses.count)
        return pWin * avgWin - pLoss * avgLoss
    }

    var expectancyMoney: Double? {
        let money = trades.compactMap(\.netPnL)
        guard !money.isEmpty else { return nil }
        let w = money.filter { $0 > 0 }, l = money.filter { $0 < 0 }, n = Double(money.count)
        let avgWin = w.isEmpty ? 0 : w.reduce(0, +) / Double(w.count), avgLoss = l.isEmpty ? 0 : -l.reduce(0, +) / Double(l.count)
        return Double(w.count) / n * avgWin - Double(l.count) / n * avgLoss
    }

    var equityCurveR: [Double] { Self.cumulative(rs) }
    var equityCurveMoney: [Double] { Self.cumulative(trades.compactMap(\.netPnL)) }
    var maxDrawdownR: Double { Self.drawdown(equityCurveR) }
    var maxDrawdownMoney: Double { Self.drawdown(equityCurveMoney) }

    var currentStreak: Int {
        var n = 0
        for r in outcomes.reversed() {
            if r == 0 { break }
            if n == 0 { n = r > 0 ? 1 : -1; continue }
            if (r > 0) == (n > 0) { n += n > 0 ? 1 : -1 } else { break }
        }
        return n
    }

    static func cumulative(_ v: [Double]) -> [Double] {
        var sum = 0.0
        return [0] + v.map { sum += $0; return sum }
    }

    static func drawdown(_ curve: [Double]) -> Double {
        var peak = curve.first ?? 0, dd = 0.0
        for v in curve { peak = max(peak, v); dd = min(dd, v - peak) }
        return dd
    }

    struct Bucket: Identifiable, Sendable {
        let key: String
        let count: Int
        let totalR: Double
        var id: String { key }
        var avgR: Double { count > 0 ? totalR / Double(count) : 0 }
    }

    func buckets(_ key: (JournalEntry) -> String?) -> [Bucket] {
        var map: [String: (Int, Double)] = [:]
        for t in trades {
            guard let k = key(t), let r = t.rMultiple else { continue }
            let v = map[k] ?? (0, 0)
            map[k] = (v.0 + 1, v.1 + r)
        }
        return map.map { Bucket(key: $0.key, count: $0.value.0, totalR: $0.value.1) }.sorted { $0.key < $1.key }
    }

    func byHour(_ cal: Calendar = .current) -> [Bucket] {
        buckets { String(format: "%02d", cal.component(.hour, from: $0.opened)) }
    }

    func byWeekday(_ cal: Calendar = .current) -> [Bucket] {
        buckets { "\(cal.component(.weekday, from: $0.opened))" }
    }

    var byAsset: [Bucket] { buckets { $0.asset } }
    var bySide: [Bucket] { buckets { $0.side == .sell ? "SHORT" : "LONG" } }
    var bySetup: [Bucket] { buckets { $0.setupTag } }
    var byMistake: [Bucket] { buckets { $0.mistakeTag } }

    struct MistakeCost: Sendable {
        struct Tag: Sendable, Identifiable {
            let tag: String
            let count: Int
            let money: Double
            let r: Double
            var id: String { tag }
        }
        let money: Double
        let r: Double
        let count: Int
        let tags: [Tag]
        let cleanShare: Double?
    }

    func mistakeCost(_ mistakes: Set<String>) -> MistakeCost {
        var byTag: [String: (Int, Double, Double)] = [:]
        var money = 0.0, r = 0.0, tagged = 0
        for t in trades {
            let hit = Set(([t.mistakeTag].compactMap { $0 } + t.tags.map { $0.hasPrefix("#") ? $0 : "#" + $0 }).filter(mistakes.contains))
            guard !hit.isEmpty else { continue }
            tagged += 1
            money += t.netPnL ?? 0
            r += t.rMultiple ?? 0
            for h in hit {
                let v = byTag[h] ?? (0, 0, 0)
                byTag[h] = (v.0 + 1, v.1 + (t.netPnL ?? 0), v.2 + (t.rMultiple ?? 0))
            }
        }
        let tags = byTag.map { MistakeCost.Tag(tag: $0.key, count: $0.value.0, money: $0.value.1, r: $0.value.2) }.sorted { $0.money < $1.money }
        return MistakeCost(money: money, r: r, count: tagged, tags: tags,
                           cleanShare: trades.isEmpty ? nil : Double(trades.count - tagged) / Double(trades.count))
    }

    var checklistEffect: (full: (count: Int, avgR: Double?), partial: (count: Int, avgR: Double?)) {
        let with = trades.filter { ($0.checklistTotal ?? 0) > 0 }
        let full = with.filter { $0.checklistDone == $0.checklistTotal }, partial = with.filter { $0.checklistDone != $0.checklistTotal }
        func avg(_ l: [JournalEntry]) -> Double? {
            let v = l.compactMap(\.rMultiple)
            return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
        }
        return ((full.count, avg(full)), (partial.count, avg(partial)))
    }

    var movedStopShare: Double? {
        trades.isEmpty ? nil : Double(trades.filter { $0.stopMoved == true }.count) / Double(trades.count)
    }

    var afterLoss: (count: Int, totalR: Double) {
        var n = 0, r = 0.0
        for (i, t) in trades.enumerated() where i > 0 {
            let prev = trades[..<i].last { ($0.closedAt ?? $0.at) <= t.opened && ($0.rMultiple ?? 0) < 0 }
            if let p = prev, t.opened.timeIntervalSince(p.closedAt ?? p.at) <= 30 * 60 { n += 1; r += t.rMultiple ?? 0 }
        }
        return (n, r)
    }
}
