import Foundation

enum WalletInbox {
    struct FormatError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Position: Sendable, Equatable {
        let id: String
        let contract: String
        let side: Signal
        let closed: Bool
        let leverage: Double?
        let margin: Double?
        let entry: Double
        let exit: Double?
        let qty: Double
        let liquidation: Double?
        let funding: Double?
        let fees: Double?
        let realized: Double?
        let takeProfit: Double?
        let stopLoss: Double?
        let openedAt: Date
        let closedAt: Date?

        var key: String { "wallet:" + id }
        var asset: String { contract.split(separator: "-").first.map(String.init) ?? contract }
    }

    struct Export: Sendable, Equatable {
        let exportedAt: Date?
        let quote: String
        let positions: [Position]
    }

    struct Summary: Sendable, Equatable {
        var added = 0
        var updated = 0
        var closed = 0
        var unchanged = 0
    }

    static func parse(_ data: Data) throws -> Export {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FormatError(message: "Not a JSON object") }
        guard (j["v"] as? NSNumber)?.intValue == 1 else { throw FormatError(message: "Unsupported format version (v must be 1)") }
        guard j["source"] as? String == "wallet" else { throw FormatError(message: "source must be \"wallet\"") }
        guard let list = j["positions"] as? [[String: Any]] else { throw FormatError(message: "positions is missing") }
        var out: [Position] = []
        for (i, p) in list.enumerated() {
            func num(_ k: String) -> Double? {
                if let n = p[k] as? NSNumber { return n.doubleValue }
                if let s = p[k] as? String, let v = Double(s.trimmingCharacters(in: .whitespaces)) { return v }
                return nil
            }
            func id() -> String? { (p["id"] as? String) ?? (p["id"] as? NSNumber)?.stringValue }
            guard let pid = id(), !pid.isEmpty else { throw FormatError(message: "position \(i + 1): id is missing") }
            guard let contract = p["contract"] as? String, !contract.isEmpty else { throw FormatError(message: "position \(pid): contract is missing") }
            guard let side = p["side"] as? String, side == "long" || side == "short" else {
                throw FormatError(message: "position \(pid): side must be long or short")
            }
            guard let status = p["status"] as? String, status == "open" || status == "closed" else {
                throw FormatError(message: "position \(pid): status must be open or closed")
            }
            guard let entry = num("avg_entry_price"), entry > 0 else { throw FormatError(message: "position \(pid): avg_entry_price is missing") }
            guard let qty = num("value_base"), qty > 0 else { throw FormatError(message: "position \(pid): value_base is missing") }
            guard let opened = date(p["opened_at"]) else { throw FormatError(message: "position \(pid): opened_at is missing or not ISO-8601") }
            out.append(Position(id: pid, contract: contract, side: side == "short" ? .sell : .buy, closed: status == "closed",
                                leverage: num("leverage"), margin: num("margin_quote"), entry: entry, exit: num("exit_price"), qty: qty,
                                liquidation: num("liquidation_price"), funding: num("funding_paid_quote"), fees: num("fees_quote"),
                                realized: num("realized_pnl_quote"), takeProfit: num("take_profit"), stopLoss: num("stop_loss"),
                                openedAt: opened, closedAt: date(p["closed_at"])))
        }
        return Export(exportedAt: date(j["exported_at"]), quote: (j["quote"] as? String) ?? "USDT", positions: out)
    }

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func entry(_ p: Position, quote: String, synced: Date) -> JournalEntry {
        var e = JournalEntry(asset: p.asset, kind: .trade, side: p.side, entry: p.entry, text: "")
        e.at = p.openedAt
        e.status = .open
        e.mode = .manual
        e.qty = p.qty
        e.openedAt = p.openedAt
        e.currency = quote
        e.importedFrom = "wallet"
        e.externalIDs = [p.key]
        e.tags = ["perps"] + (p.leverage.map { ["x" + String(format: "%g", $0)] } ?? [])
        apply(p, to: &e, synced: synced)
        return e
    }

    static func apply(_ p: Position, to e: inout JournalEntry, synced: Date) {
        if let s = p.stopLoss, s > 0 {
            if e.initialStop == nil { e.initialStop = s } else if e.stop != s { e.stopMoved = true }
            e.stop = s
            e.riskAmount = abs(p.entry - (e.initialStop ?? s)) * p.qty + (p.fees ?? 0)
        }
        if let t = p.takeProfit, t > 0 { e.target = t }
        e.leverage = p.leverage ?? e.leverage
        e.margin = p.margin ?? e.margin
        e.liquidationPrice = p.liquidation ?? e.liquidationPrice
        e.fundingPaid = p.funding ?? e.fundingPaid
        e.syncedAt = synced
        e.entry = p.entry
        e.qty = p.qty
        if p.closed {
            e.status = .closed
            e.exit = p.exit ?? e.exit
            e.closedAt = p.closedAt ?? synced
            e.exitReason = e.exitReason ?? .manual
            let cost = (p.fees ?? 0) + (p.funding ?? 0)
            e.commission = cost
            if let r = p.realized {
                e.netPnL = r
                e.grossPnL = r + cost
            } else if let x = e.exit {
                let gross = (p.side == .sell ? p.entry - x : x - p.entry) * p.qty
                e.grossPnL = gross
                e.netPnL = gross - cost
            }
        }
    }

    static func merge(_ export: Export, into entries: [JournalEntry], now: Date = Date()) -> (entries: [JournalEntry], summary: Summary) {
        var list = entries
        var summary = Summary()
        let synced = export.exportedAt ?? now
        for p in export.positions {
            if let i = list.firstIndex(where: { $0.externalIDs?.contains(p.key) == true }) {
                guard list[i].status != .closed else { summary.unchanged += 1; continue }
                if let s = list[i].syncedAt, s > synced { summary.unchanged += 1; continue }
                var e = list[i]
                apply(p, to: &e, synced: synced)
                if e == list[i] { summary.unchanged += 1; continue }
                if p.closed { summary.closed += 1 } else { summary.updated += 1 }
                list[i] = e
            } else {
                list.append(entry(p, quote: export.quote, synced: synced))
                summary.added += 1
                if p.closed { summary.closed += 1 }
            }
        }
        return (list, summary)
    }

    @discardableResult
    static func process(folder: URL, apply: (Export) throws -> Void) -> [(file: String, error: String)] {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let failed = folder.appendingPathComponent("failed", isDirectory: true)
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var errors: [(String, String)] = []
        for f in files {
            do {
                let export = try parse(try Data(contentsOf: f))
                try apply(export)
                try? fm.removeItem(at: f)
            } catch {
                try? fm.createDirectory(at: failed, withIntermediateDirectories: true)
                let target = failed.appendingPathComponent(f.lastPathComponent)
                try? fm.removeItem(at: target)
                try? fm.moveItem(at: f, to: target)
                errors.append((f.lastPathComponent, error.localizedDescription))
            }
        }
        return errors
    }
}

final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    let url: URL
    let delay: TimeInterval
    private let onChange: () -> Void

    init(url: URL, delay: TimeInterval = 0.6, onChange: @escaping () -> Void) {
        self.url = url
        self.delay = delay
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: .main)
        s.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.onChange() }
            self.pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + self.delay, execute: w)
        }
        s.setCancelHandler { Darwin.close(fd) }
        s.resume()
        source = s
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
