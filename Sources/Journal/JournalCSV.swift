import Foundation

enum JournalCSV {
    static let columns = ["opened", "closed", "asset", "side", "source", "mode", "qty", "entry", "exit", "stop", "target",
                          "gross_pnl", "commission", "net_pnl", "currency", "risk", "r", "exit_reason", "setup", "mistake",
                          "tags", "checklist", "note"]

    static func make(_ entries: [JournalEntry], baseCurrency: String) -> String {
        let iso = ISO8601DateFormatter()
        let trades = entries.filter { $0.kind == .trade && $0.status == .closed }.sorted { ($0.closedAt ?? $0.at) < ($1.closedAt ?? $1.at) }
        var lines = [columns.joined(separator: ",")]
        for e in trades {
            let row: [String?] = [
                iso.string(from: e.opened), e.closedAt.map(iso.string), e.asset, e.side == .sell ? "SHORT" : "LONG",
                e.importedFrom ?? "journal", e.tradeMode.rawValue, num(e.qty), num(e.entry), num(e.exit), num(e.riskStop),
                num(e.target), num(e.grossPnL), num(e.commission), num(e.netPnL),
                e.netPnL == nil ? nil : (e.currency ?? (e.tradeMode == .manual ? baseCurrency : "USDT")),
                num(e.riskAmount), num(e.rMultiple), e.exitReason?.rawValue, e.setupTag, e.mistakeTag,
                e.tags.joined(separator: " "),
                e.checklistTotal.map { "\(e.checklistDone ?? 0)/\($0)" }, e.note ?? (e.text.isEmpty ? nil : e.text),
            ]
            lines.append(row.map { quote($0 ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func num(_ v: Double?) -> String? {
        guard let v, v.isFinite else { return nil }
        return String(format: "%.10g", v)
    }

    static func quote(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
