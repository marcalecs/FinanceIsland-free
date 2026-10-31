import Foundation

enum DataService {
    static func chart(_ symbol: String, range: String, interval: String) async throws
        -> (price: Double?, prevClose: Double?, points: [PricePoint]) {
        let b = try await Yahoo.chart(symbol, range: range, interval: interval)
        return (b.meta.price, b.meta.prevClose, b.candles.map { PricePoint(time: $0.openTime, value: $0.close) })
    }

    typealias ChartData = (price: Double?, prevClose: Double?, points: [PricePoint])

    static func pairChart(_ a: Asset, range: String, interval: String) async throws -> ChartData {
        let direct: ChartData?
        do { direct = try await chart(a.yahoo, range: range, interval: interval) }
        catch { direct = nil; AppLog.write("direct \(a.yahoo) failed:", error) }
        if let direct, direct.points.count >= 2 { return direct }
        guard a.isFiat else {
            if let direct { return direct }
            throw URLError(.cannotParseResponse)
        }
        do {
            let cross = try await crossChart(code: a.code, base: a.base, range: range, interval: interval)
            if cross.points.count >= 2 || direct == nil { return cross }
        } catch {
            AppLog.write("cross \(a.code)/\(a.base) failed:", error)
        }
        if let direct { return direct }
        throw URLError(.cannotParseResponse)
    }

    private static func crossChart(code: String, base: String, range: String, interval: String) async throws -> ChartData {
        async let numTask: ChartData? = base == "USD" ? nil : chart("USD\(base)=X", range: range, interval: interval)
        async let denTask: ChartData? = code == "USD" ? nil : chart("USD\(code)=X", range: range, interval: interval)
        let num = try await numTask
        let den = try await denTask

        switch (num, den) {
        case let (n?, nil):
            return n
        case let (nil, d?):
            return (d.price.map { 1 / $0 }, d.prevClose.map { 1 / $0 },
                    d.points.map { PricePoint(time: $0.time, value: 1 / $0.value) })
        case let (n?, d?):
            guard !d.points.isEmpty else { throw URLError(.cannotParseResponse) }
            var j = 0
            var points: [PricePoint] = []
            for p in n.points {
                while j + 1 < d.points.count && d.points[j + 1].time <= p.time { j += 1 }
                let dv = d.points[j].value
                if dv != 0 { points.append(PricePoint(time: p.time, value: p.value / dv)) }
            }
            func ratio(_ x: Double?, _ y: Double?) -> Double? {
                guard let x, let y, y != 0 else { return nil }
                return x / y
            }
            return (ratio(n.price, d.price), ratio(n.prevClose, d.prevClose), points)
        case (nil, nil):
            throw URLError(.badURL)
        }
    }

    private static let rpcs = [
        "https://ethereum-rpc.publicnode.com",
        "https://eth.llamarpc.com",
        "https://rpc.ankr.com/eth",
    ]

    private struct RPCResponse: Decodable { let result: String? }

    static func ethBalance(_ address: String) async throws -> Double {
        var lastError: Error = URLError(.cannotConnectToHost)
        for endpoint in rpcs {
            guard let url = URL(string: endpoint) else { continue }
            do {
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.timeoutInterval = 15
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = ["jsonrpc": "2.0", "id": 1,
                                           "method": "eth_getBalance",
                                           "params": [address, "latest"]]
                req.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (data, _) = try await URLSession.shared.data(for: req)
                let r = try JSONDecoder().decode(RPCResponse.self, from: data)
                guard let hex = r.result, let wei = hexToDouble(hex) else { throw URLError(.cannotParseResponse) }
                return wei / 1e18
            } catch {
                AppLog.write("RPC \(endpoint) failed:", error)
                lastError = error
            }
        }
        throw lastError
    }

    private static func hexToDouble(_ hex: String) -> Double? {
        var s = Substring(hex)
        if s.hasPrefix("0x") { s = s.dropFirst(2) }
        var v = 0.0
        for c in s {
            guard let d = c.hexDigitValue else { return nil }
            v = v * 16 + Double(d)
        }
        return v
    }
}
