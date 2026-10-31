import AppKit
import Foundation

enum AppLog {
    static let maxBytes: Int64 = 2 * 1024 * 1024
    private static let queue = DispatchQueue(label: "AppLog", qos: .utility)

    static var enabled: Bool { UserDefaults.standard.object(forKey: "logEnabled") as? Bool ?? true }

    static var folder: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/FinanceIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static var file: URL { folder.appendingPathComponent("FinanceIsland.log") }
    static var previous: URL { folder.appendingPathComponent("FinanceIsland.1.log") }

    static func write(_ items: Any..., separator: String = " ") {
        let line = items.map { "\($0)" }.joined(separator: separator)
        print(line)
        guard enabled else { return }
        let stamp = Date()
        queue.async {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            f.timeZone = .current
            append(f.string(from: stamp) + "  " + line + "\n")
        }
    }

    private static func append(_ text: String) {
        let fm = FileManager.default
        let url = file
        if let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value, size > maxBytes {
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: url, to: previous)
        }
        guard let data = text.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    static func tail(_ n: Int = 12) -> [String] {
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Array(s.split(separator: "\n").suffix(n).map(String.init))
    }

    static func clear(_ done: @escaping @Sendable () -> Void) {
        queue.async {
            for u in [file, previous] where FileManager.default.fileExists(atPath: u.path) {
                try? FileManager.default.trashItem(at: u, resultingItemURL: nil)
            }
            DispatchQueue.main.async(execute: done)
        }
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        func one(_ u: URL) -> Int64 {
            let v = try? u.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        guard isDir.boolValue else { return one(url) }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let u as URL in e where (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                total += one(u)
            }
        }
        return total
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
