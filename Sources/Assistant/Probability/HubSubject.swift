import Foundation

enum HubSubject: Hashable, Identifiable, Sendable {
    case asset(Asset)
    case item(WatchItem)

    var id: String {
        switch self {
        case .asset(let a): return "a|" + a.id + "/" + a.base
        case .item(let i): return "i|" + i.id
        }
    }
    var short: String {
        switch self {
        case .asset(let a): return a.isFiat ? a.code + "/" + a.base : a.code
        case .item(let i): return i.isCrypto ? i.display : ItemNames.short(i.symbol, name: ItemNames.name(i.symbol))
        }
    }
    var code: String {
        switch self {
        case .asset(let a): return a.code
        case .item(let i): return i.short
        }
    }
    var name: String {
        switch self {
        case .asset(let a): return a.name
        case .item(let i): return i.isCrypto ? i.display : (ItemNames.name(i.symbol) ?? i.symbol)
        }
    }
    var crypto: Bool {
        switch self {
        case .asset(let a): return !a.isFiat
        case .item(let i): return i.isCrypto
        }
    }
    var item: WatchItem? { if case .item(let i) = self { return i } else { return nil } }

    func format(_ v: Double, unit: Bool = true) -> String {
        let s = abs(v) >= 10_000 ? Fmt.number(v, min: 0, max: 0)
            : abs(v) >= 1 ? Fmt.number(v, min: 2, max: 2) : Fmt.number(v, min: 4, max: 6)
        guard unit else { return s }
        switch self {
        case .asset(let a): return a.isFiat ? s + " " + a.unit : "$" + s
        case .item(let i): return i.quotedInUSD ? "$" + s : s
        }
    }
}

enum ItemNames {
    nonisolated(unsafe) private static var saved: [String: String] =
        UserDefaults.standard.dictionary(forKey: "itemNames") as? [String: String] ?? [:]

    static func name(_ symbol: String) -> String? {
        if let n = saved[symbol.uppercased()] { return n }
        return SearchCatalog.items.first { $0.symbol.uppercased() == symbol.uppercased() }?.name
    }

    static func remember(_ symbol: String, name: String) {
        saved[symbol.uppercased()] = name
        UserDefaults.standard.set(saved, forKey: "itemNames")
    }

    static func short(_ symbol: String, name: String?) -> String {
        if symbol.hasPrefix("^") || symbol.hasSuffix("=F"), let name { return name }
        return symbol
    }
}

extension HubSubject {
    init?(id: String) {
        if id.hasPrefix("i|"), let w = WatchItem(id: String(id.dropFirst(2))) {
            self = .item(w)
            return
        }
        guard id.hasPrefix("a|") else { return nil }
        let body = id.dropFirst(2)
        guard let slash = body.lastIndex(of: "/") else { return nil }
        let base = String(body[body.index(after: slash)...])
        guard let a = Asset.make(id: String(body[..<slash]), base: base) else { return nil }
        self = .asset(a)
    }
}
