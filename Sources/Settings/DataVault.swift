import AppKit
import Foundation

struct DataExport: Codable {
    var format = 1
    var app: String
    var exported: Date
    var longTerm: LongTermSnapshot
    var journal: [JournalEntry]
    var alerts: [PriceAlert]? = nil
}

enum DataVault {
    static let throttle: TimeInterval = 15 * 60
    nonisolated(unsafe) private static var lastBackup: [String: Date] = [:]

    static var backupsDirectory: URL { AppIdentity.supportDirectory.appendingPathComponent("Backups", isDirectory: true) }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    static func backup(_ kind: String, _ data: Data, force: Bool = false) {
        let fm = FileManager.default
        let dir = backupsDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = backups(kind)
        let last = lastBackup[kind] ?? files.first?.date
        if !force, let last, Date().timeIntervalSince(last) < throttle { return }
        if let newest = files.first, (try? Data(contentsOf: newest.url)) == data { lastBackup[kind] = Date(); return }
        let now = Date()
        try? data.write(to: dir.appendingPathComponent("\(kind)-\(stamp.string(from: now)).json"), options: .atomic)
        lastBackup[kind] = now
        prune(kind)
    }

    static func backups(_ kind: String) -> [(url: URL, date: Date)] {
        let dir = backupsDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap { name -> (URL, Date)? in
            guard name.hasPrefix(kind + "-"), name.hasSuffix(".json") else { return nil }
            let raw = name.dropFirst(kind.count + 1).dropLast(5)
            guard let d = stamp.date(from: String(raw)) else { return nil }
            return (dir.appendingPathComponent(name), d)
        }
        .sorted { $0.1 > $1.1 }
    }

    static func prune(_ kind: String) {
        let files = backups(kind)
        let cal = Calendar(identifier: .iso8601)
        var keep = Set(files.prefix(5).map(\.url))
        var days: [DateComponents] = [], weeks: [DateComponents] = []
        for f in files {
            let day = cal.dateComponents([.year, .month, .day], from: f.date)
            if !days.contains(day), days.count < 10 { days.append(day); keep.insert(f.url) }
            let week = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: f.date)
            if !weeks.contains(week), weeks.count < 5 { weeks.append(week); keep.insert(f.url) }
        }
        for f in files where !keep.contains(f.url) { try? FileManager.default.removeItem(at: f.url) }
    }

    static func deleteBackups() {
        try? FileManager.default.removeItem(at: backupsDirectory)
    }

    @MainActor
    static func exportData() -> Data? {
        let x = DataExport(app: AppInfo.version, exported: Date(), longTerm: LongTermStore.shared.snapshot,
                           journal: JournalStore.shared.entries, alerts: AlertStore.shared.alerts)
        return try? encoder.encode(x)
    }

    @MainActor
    @discardableResult
    static func runExport() -> Bool {
        guard let data = exportData() else { return false }
        let panel = NSSavePanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.allowedContentTypes = [.json]
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "FinanceIsland-\(f.string(from: Date())).json"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            AppLog.write("export failed:", error.localizedDescription)
            return false
        }
    }

    @MainActor
    static func runImport() -> String? {
        let panel = NSOpenPanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url), let x = try? decoder.decode(DataExport.self, from: data) else {
            return "This file is not a FinanceIsland export"
        }
        if let current = exportData() { backup("before-import", current, force: true) }
        LongTermStore.shared.restore(x.longTerm)
        JournalStore.shared.restore(x.journal)
        if let a = x.alerts { AlertStore.shared.restore(a) }
        return "Imported \(x.longTerm.manual.count) positions and \(x.journal.count) journal entries"
    }

    @MainActor
    static func revealBackups() {
        try? FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(backupsDirectory)
    }
}
