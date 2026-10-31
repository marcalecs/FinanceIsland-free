import Foundation

@MainActor
final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    struct Deleted: Equatable {
        let entry: JournalEntry
        let index: Int
        let at: Date
    }

    @Published private(set) var entries: [JournalEntry] = []
    @Published var draft: JournalEntry?
    @Published private(set) var lastDeleted: Deleted?
    private var lastSaved: Data?

    private init() { load() }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinanceIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.json")
    }

    var trades: [JournalEntry] { entries.filter { $0.kind == .trade } }
    var closed: [JournalEntry] { trades.filter { $0.status == .closed } }
    var openCount: Int { trades.count - closed.count }
    var stats: JournalStats { JournalStats(entries) }
    var totalR: Double { stats.totalR }
    var winRate: Double? { stats.winRate }
    var profitFactor: Double? { stats.profitFactor }
    var expectancy: Double? { stats.expectancy }
    var maxDrawdownR: Double { stats.maxDrawdownR }
    var equityCurve: [Double] { stats.equityCurveR }

    func add(_ e: JournalEntry) {
        var e = e
        e.id = UUID()
        e.at = Date()
        e.status = e.kind == .trade ? .open : nil
        entries.append(e)
        save()
    }

    func close(_ id: UUID, exit: Double, reason: JournalEntry.ExitReason? = nil) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var e = entries[i]
        e.status = .closed
        e.exit = exit
        e.closedAt = Date()
        e.exitReason = reason ?? e.exitReason
        if let en = e.entry, let q = e.qty {
            let fee = e.feeRate ?? 0
            e.grossPnL = RiskCalculator.grossPnL(side: e.side, entry: en, exit: exit, qty: q)
            e.commission = RiskCalculator.commission(entry: en, exit: exit, qty: q, fee: fee)
            e.netPnL = RiskCalculator.netPnL(side: e.side, entry: en, exit: exit, qty: q, fee: fee)
        }
        entries[i] = e
        save()
    }

    func importTrades(_ list: [JournalEntry]) {
        if let data = lastSaved, !entries.isEmpty { DataVault.backup("journal", data, force: true) }
        entries.append(contentsOf: list)
        save()
    }

    @discardableResult
    func applyWallet(_ export: WalletInbox.Export) -> WalletInbox.Summary {
        let before = Dictionary(entries.compactMap { e in e.externalIDs?.first.map { ($0, e.status) } }, uniquingKeysWith: { a, _ in a })
        let r = WalletInbox.merge(export, into: entries)
        guard r.summary.added + r.summary.updated + r.summary.closed > 0 else { return r.summary }
        if let data = lastSaved, !entries.isEmpty { DataVault.backup("journal", data, force: true) }
        entries = r.entries
        save()
        let newlyClosed = entries.filter { e in
            e.importedFrom == "wallet" && e.status == .closed && e.externalIDs?.first.map { before[$0] != .closed } == true
        }
        TradeDesk.shared.queueTags(newlyClosed.map(\.id))
        return r.summary
    }

    func setStop(_ id: UUID, _ stop: Double) {
        guard let i = entries.firstIndex(where: { $0.id == id }), let en = entries[i].entry, let q = entries[i].qty, stop > 0, stop != en else { return }
        entries[i].stop = stop
        entries[i].initialStop = stop
        let fees = entries[i].commission ?? 0
        let k = entries[i].grossPnL.flatMap { g in entries[i].exit.map { x in abs(x - en) * q > 0 ? abs(g) / (abs(x - en) * q) : 1 } } ?? 1
        entries[i].riskAmount = abs(en - stop) * q * k + fees
        save()
    }

    func record(_ e: JournalEntry) {
        entries.append(e)
        save()
    }

    func moveStop(_ id: UUID, to stop: Double) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].status == .open, entries[i].stop != stop else { return }
        if entries[i].initialStop == nil { entries[i].initialStop = entries[i].stop }
        entries[i].stop = stop
        entries[i].stopMoved = true
        save()
    }

    func tag(_ id: UUID, setup: String?, mistake: String?, note: String?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].setupTag = setup
        entries[i].mistakeTag = mistake
        let n = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entries[i].note = n.isEmpty ? nil : n
        save()
    }

    func entry(_ id: UUID?) -> JournalEntry? { id.flatMap { id in entries.first { $0.id == id } } }

    func delete(_ id: UUID) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let d = Deleted(entry: entries[i], index: i, at: Date())
        entries.remove(at: i)
        lastDeleted = d
        save()
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if lastDeleted == d { lastDeleted = nil }
        }
    }

    func undoDelete() {
        guard let d = lastDeleted, !entries.contains(where: { $0.id == d.entry.id }) else { return }
        entries.insert(d.entry, at: min(d.index, entries.count))
        lastDeleted = nil
        save()
    }

    func restore(_ list: [JournalEntry]) {
        entries = list
        lastDeleted = nil
        save()
    }

    func eraseAll() {
        if let data = lastSaved, !entries.isEmpty { DataVault.backup("journal", data, force: true) }
        entries = []
        draft = nil
        lastDeleted = nil
        lastSaved = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        entries = (try? dec.decode([JournalEntry].self, from: data)) ?? []
        lastSaved = data
        if !entries.isEmpty { DataVault.backup("journal", data, force: true) }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(entries), data != lastSaved else { return }
        if let previous = lastSaved { DataVault.backup("journal", previous) }
        lastSaved = data
        try? data.write(to: Self.fileURL, options: .atomic)
    }


    private static func round(_ v: Double) -> Double {
        let digits: Double = abs(v) >= 1000 ? 0 : abs(v) >= 1 ? 2 : 6
        let k = pow(10, digits)
        return (v * k).rounded() / k
    }
}
