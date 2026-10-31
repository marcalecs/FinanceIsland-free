import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, zh, es, de
    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return tr("System")
        case .en: return "English"
        case .zh: return "中文（简体）"
        case .es: return "Español"
        case .de: return "Deutsch"
        }
    }

    var resolved: AppLanguage {
        guard self == .system else { return self }
        for code in Locale.preferredLanguages {
            let base = String(code.prefix(2))
            if let l = AppLanguage(rawValue: base), l != .system { return l }
        }
        return .en
    }

    var locale: Locale {
        switch resolved {
        case .zh: return Locale(identifier: "zh_CN")
        case .es: return Locale(identifier: "es_ES")
        case .de: return Locale(identifier: "de_DE")
        default: return Locale(identifier: "en_US")
        }
    }
}

enum L10n {
    nonisolated(unsafe) private static var language: AppLanguage = .en
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var patterns: [(regex: NSRegularExpression, key: String)] = []
    private static let lock = NSLock()

    static var current: AppLanguage { lock.withLock { language } }

    static func set(_ l: AppLanguage) {
        lock.withLock {
            language = l.resolved
            cache = [:]
            patterns = []
            guard let table = tables[language] else { return }
            for key in table.keys where key.contains("%@") {
                let parts = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
                if let re = try? NSRegularExpression(pattern: "^" + parts.joined(separator: "(.+?)") + "$",
                                                     options: [.dotMatchesLineSeparators]) {
                    patterns.append((re, key))
                }
            }
            patterns.sort { $0.key.count > $1.key.count }
        }
    }

    static func translate(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard language != .en, let table = tables[language], !s.isEmpty else { return s }
        if let hit = cache[s] { return hit }
        var out = s
        if let t = table[s] {
            out = t
        } else if s.contains(where: \.isLetter) {
            let ns = s as NSString
            for (re, key) in patterns {
                guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { continue }
                let args = (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
                out = fill(table[key]!, args.map { translateNoLock($0, table) })
                break
            }
        }
        if cache.count > 4000 { cache = [:] }
        cache[s] = out
        return out
    }

    private static func translateNoLock(_ s: String, _ table: [String: String]) -> String { table[s] ?? s }

    private static func fill(_ template: String, _ args: [String]) -> String {
        var out = template
        for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "%\(i + 1)$@", with: a) }
        var i = 0
        while let r = out.range(of: "%@"), i < args.count {
            out.replaceSubrange(r, with: args[i]); i += 1
        }
        return out
    }

    static let tables: [AppLanguage: [String: String]] = {
        [.zh: Translations.zh, .es: Translations.es, .de: Translations.de]
    }()
}

func tr(_ s: String) -> String { L10n.translate(s) }
