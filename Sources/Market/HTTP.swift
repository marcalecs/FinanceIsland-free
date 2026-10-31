import Foundation

enum HTTP {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 40
        c.waitsForConnectivity = false
        c.httpAdditionalHeaders = ["User-Agent": userAgent, "Accept": "*/*"]
        return URLSession(configuration: c)
    }()

    private static let cooldown = Cooldown()
    private static let yahoo = YahooGate()

    static func isYahoo(_ host: String) -> Bool { host.hasSuffix("finance.yahoo.com") }

    static func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> Data {
        let host = url.host ?? ""
        if isYahoo(host) {
            if let d = await yahoo.cached(url.absoluteString) { return d }
            await yahoo.waitForSlot()
        }
        if await cooldown.isBlocked(host) { throw MarketError.rateLimited(host) }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            if isYahoo(host) { await yahoo.store(url.absoluteString, data) }
            return data
        case 429:
            await cooldown.block(host, for: 300)
            throw MarketError.rateLimited(host)
        case 403, 500...599:
            await cooldown.block(host, for: 60)
            throw MarketError.http(status)
        default:
            throw MarketError.http(status)
        }
    }

    static func get(_ string: String, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> Data {
        guard let url = URL(string: string) else { throw MarketError.badData }
        return try await get(url, headers: headers, timeout: timeout)
    }

    static func json(_ string: String, headers: [String: String] = [:]) async throws -> Any {
        let data = try await get(string, headers: headers)
        return try JSONSerialization.jsonObject(with: data)
    }

    private actor YahooGate {
        static let perMinute = 40
        static let cacheFor: TimeInterval = 30
        private var stamps: [Date] = []
        private var cache: [String: (at: Date, data: Data)] = [:]

        func cached(_ key: String) -> Data? {
            guard let c = cache[key], Date().timeIntervalSince(c.at) < Self.cacheFor else { return nil }
            return c.data
        }

        func store(_ key: String, _ data: Data) {
            if cache.count > 300 { cache = cache.filter { Date().timeIntervalSince($0.value.at) < Self.cacheFor } }
            cache[key] = (Date(), data)
        }

        func waitForSlot() async {
            while true {
                let now = Date()
                stamps.removeAll { now.timeIntervalSince($0) >= 60 }
                if stamps.count < Self.perMinute { stamps.append(now); return }
                let wait = 60 - now.timeIntervalSince(stamps[0]) + 0.05
                try? await Task.sleep(nanoseconds: UInt64(max(wait, 0.05) * 1_000_000_000))
            }
        }
    }

    private actor Cooldown {
        private var until: [String: Date] = [:]
        func isBlocked(_ host: String) -> Bool {
            guard let u = until[host] else { return false }
            if u > Date() { return true }
            until[host] = nil
            return false
        }
        func block(_ host: String, for seconds: TimeInterval) { until[host] = Date().addingTimeInterval(seconds) }
        func blocked() -> [String] { until.filter { $0.value > Date() }.map(\.key).sorted() }
    }
}

func firstSuccess<T: Sendable>(_ attempts: [(String, @Sendable () async throws -> T)]) async throws -> (T, String) {
    var failures: [String] = []
    for (name, attempt) in attempts {
        do { return (try await attempt(), name) }
        catch {
            if case MarketError.unknownSymbol = error, attempts.count == 1 { throw error }
            failures.append("\(name): \(error.localizedDescription)")
        }
    }
    throw MarketError.allSourcesFailed(failures)
}

enum CSV {
    static func rows(_ data: Data) -> [[String]] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
        return text.split(whereSeparator: \.isNewline).map {
            $0.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
        }
    }
}
