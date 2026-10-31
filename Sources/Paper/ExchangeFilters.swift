import Foundation

enum ExchangeFilters {
    struct Lot: Codable, Sendable {
        let step: Double
        let tick: Double
    }

    private struct Cache: Codable {
        var at: Date
        var lots: [String: Lot]
    }

    static let ttl: TimeInterval = 86_400
    private static let key = "exchangeFilters"

    static func lot(_ symbol: String) async -> Lot? {
        let s = symbol.uppercased()
        if let c = load(), Date().timeIntervalSince(c.at) < ttl, let l = c.lots[s] { return l }
        if let all = await fetch("https://fapi.binance.com/fapi/v1/exchangeInfo"), let l = all[s] {
            store(Cache(at: Date(), lots: all))
            return l
        }
        if let one = await fetch("https://api.binance.com/api/v3/exchangeInfo?symbol=\(s)"), let l = one[s] {
            var c = load() ?? Cache(at: Date(), lots: [:])
            c.lots[s] = l
            store(c)
            return l
        }
        return load()?.lots[s]
    }

    private static func fetch(_ url: String) async -> [String: Lot]? {
        guard let j = try? await HTTP.json(url) as? [String: Any], let list = j["symbols"] as? [[String: Any]] else { return nil }
        var out: [String: Lot] = [:]
        for item in list {
            guard let name = item["symbol"] as? String, let filters = item["filters"] as? [[String: Any]] else { continue }
            func value(_ type: String, _ field: String) -> Double? {
                filters.first { $0["filterType"] as? String == type }.flatMap { Double($0[field] as? String ?? "") }
            }
            if let step = value("LOT_SIZE", "stepSize"), let tick = value("PRICE_FILTER", "tickSize"), step > 0 {
                out[name] = Lot(step: step, tick: tick)
            }
        }
        return out.isEmpty ? nil : out
    }

    private static func load() -> Cache? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
    }

    private static func store(_ c: Cache) {
        if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: key) }
    }
}
