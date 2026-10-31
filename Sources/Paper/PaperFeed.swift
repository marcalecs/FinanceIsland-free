import Foundation

struct BookTick: Sendable, Equatable {
    var bid: Double
    var ask: Double
    var time: Date
    var mid: Double { (bid + ask) / 2 }
}

enum FeedSource: String, Sendable {
    case connecting, futures, spot, simulated
    var isLive: Bool { self == .futures || self == .spot }
}

struct OfflineGenerator: Sendable {
    private var state: UInt64
    private(set) var price: Double
    let volatility: Double
    let spread: Double

    init(seed: UInt64, price: Double, volatility: Double = 0.0003, spread: Double = 0.00005) {
        state = seed
        self.price = price
        self.volatility = volatility
        self.spread = spread
    }

    mutating func uniform() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    mutating func gaussian() -> Double {
        let u = max(uniform(), 1e-12), v = uniform()
        return sqrt(-2 * log(u)) * cos(2 * .pi * v)
    }

    mutating func next(at time: Date) -> BookTick {
        price *= exp(volatility * gaussian())
        let half = price * spread / 2
        return BookTick(bid: price - half, ask: price + half, time: time)
    }
}

actor PaperFeed {
    typealias Sink = @MainActor @Sendable ([BookTick], FeedSource) -> Void

    static let flushEvery: UInt64 = 100_000_000
    static let simulatedEvery: UInt64 = 250_000_000

    let symbol: String
    var endpoints: [(String, FeedSource)]
    private let sink: Sink
    private var generator: OfflineGenerator?
    private var seed: UInt64
    private var fallbackPrice: Double?
    private var buffer: [BookTick] = []
    private var source: FeedSource = .connecting
    private var lastFlushedSource: FeedSource?
    private var runner: Task<Void, Never>?
    private var flusher: Task<Void, Never>?
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    init(symbol: String, seed: UInt64 = UInt64.random(in: 1...UInt64.max), fallbackPrice: Double?, sink: @escaping Sink) {
        self.symbol = symbol.lowercased()
        let s = symbol.lowercased()
        endpoints = [("wss://fstream.binance.com/ws/\(s)@bookTicker", .futures), ("wss://stream.binance.com:9443/ws/\(s)@bookTicker", .spot)]
        self.seed = seed
        self.fallbackPrice = fallbackPrice
        self.sink = sink
    }

    func start() {
        guard runner == nil else { return }
        runner = Task { await self.run() }
        flusher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.flushEvery)
                await self.flush()
            }
        }
    }

    func stop() {
        runner?.cancel()
        flusher?.cancel()
        runner = nil
        flusher = nil
    }

    private func flush() async {
        guard !buffer.isEmpty || lastFlushedSource != source else { return }
        let batch = buffer, src = source
        buffer = []
        lastFlushedSource = src
        await sink(batch, src)
    }

    private func push(_ t: BookTick, _ src: FeedSource) {
        source = src
        buffer.append(t)
        if buffer.count > 5_000 { buffer.removeFirst(buffer.count - 5_000) }
        fallbackPrice = t.mid
    }

    private func run() async {
        var backoff: Double = 2
        outer: while !Task.isCancelled {
            for (address, src) in endpoints {
                if await stream(address, src) { backoff = 2; continue outer }
                if Task.isCancelled { return }
            }
            await simulate(seconds: backoff)
            backoff = min(backoff * 2, 60)
        }
    }

    private func stream(_ address: String, _ src: FeedSource) async -> Bool {
        guard let url = URL(string: address) else { return false }
        let task = session.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        var got = false
        while !Task.isCancelled {
            guard let message = try? await receive(task, timeout: got ? 30 : 8) else { break }
            let data: Data?
            switch message {
            case .string(let s): data = s.data(using: .utf8)
            case .data(let d): data = d
            @unknown default: data = nil
            }
            guard let d = data, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let bid = Double(j["b"] as? String ?? ""), let ask = Double(j["a"] as? String ?? ""), bid > 0, ask >= bid else { continue }
            got = true
            generator = nil
            push(BookTick(bid: bid, ask: ask, time: Date()), src)
        }
        return got
    }

    private nonisolated func receive(_ task: URLSessionWebSocketTask, timeout: Double) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await task.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                task.cancel(with: .goingAway, reason: nil)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let m = try await group.next() else { throw URLError(.cancelled) }
            return m
        }
    }

    private func simulate(seconds: Double) async {
        if generator == nil {
            generator = OfflineGenerator(seed: seed, price: fallbackPrice ?? 100)
            seed &+= 1
        }
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !Task.isCancelled, var g = generator {
            push(g.next(at: Date()), .simulated)
            generator = g
            try? await Task.sleep(nanoseconds: Self.simulatedEvery)
        }
    }
}
