import Foundation

struct JournalEntry: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case note, trade }
    enum Status: String, Codable, Sendable { case open, closed }
    enum Mode: String, Codable, Sendable, CaseIterable { case manual, paper, simulated }
    enum ExitReason: String, Codable, Sendable { case target, stop, breakeven, manual, panic }

    var id = UUID()
    var at = Date()
    var asset: String
    var itemID: String?
    var kind: Kind
    var side: Signal = .buy
    var entry: Double?
    var stop: Double?
    var target: Double?
    var size: Double?
    var text: String
    var tags: [String] = []
    var status: Status?
    var exit: Double?

    var mode: Mode?
    var qty: Double?
    var riskAmount: Double?
    var feeRate: Double?
    var commission: Double?
    var grossPnL: Double?
    var netPnL: Double?
    var openedAt: Date?
    var closedAt: Date?
    var exitReason: ExitReason?
    var slippage: Double?
    var mae: Double?
    var mfe: Double?
    var setupTag: String?
    var mistakeTag: String?
    var note: String?
    var initialStop: Double?
    var stopMoved: Bool?
    var importedFrom: String?
    var externalIDs: [String]?
    var currency: String?
    var leverage: Double?
    var margin: Double?
    var liquidationPrice: Double?
    var fundingPaid: Double?
    var syncedAt: Date?
    var checklistDone: Int?
    var checklistTotal: Int?

    var tradeMode: Mode { mode ?? .manual }
    var isImported: Bool { importedFrom != nil }
    var outcome: Double? { rMultiple ?? (status == .closed ? netPnL : nil) }
    var opened: Date { openedAt ?? at }
    var riskStop: Double? { initialStop ?? stop }

    var rMultiple: Double? {
        guard kind == .trade, status == .closed else { return nil }
        if let n = netPnL, let r = riskAmount, r > 0 { return n / r }
        guard let e = entry, let s = riskStop, let x = exit, e != s else { return nil }
        return (side == .sell ? e - x : x - e) / abs(e - s)
    }

    var rewardRisk: Double? {
        guard let e = entry, let s = riskStop, let t = target, e != s else { return nil }
        return abs(t - e) / abs(e - s)
    }

    var allTags: [String] { tags + [setupTag, mistakeTag].compactMap { $0 } }
}
