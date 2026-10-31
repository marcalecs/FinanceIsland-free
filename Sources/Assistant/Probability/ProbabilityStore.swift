import Foundation

@MainActor
final class ProbabilityStore: ObservableObject {
    @Published private(set) var models: [String: ProbabilityModel] = [:]

    var staleSince: Date? {
        models.values.filter { $0.crypto && Date().timeIntervalSince($0.lastClose) > 2 * 86_400 }.map(\.lastClose).min()
    }
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading: Set<String> = []
    private var fetched: [String: Date] = [:]

    func model(_ s: HubSubject) -> ProbabilityModel? { models[s.id] }
    func error(_ s: HubSubject) -> String? { errors[s.id] }
    func isLoading(_ s: HubSubject) -> Bool { loading.contains(s.id) }
    func updated(_ s: HubSubject) -> Date? { fetched[s.id] }

    func load(_ s: HubSubject, force: Bool = false) {
        let k = s.id
        if loading.contains(k) { return }
        if !force, let t = fetched[k], Date().timeIntervalSince(t) < 300, models[k] != nil { return }
        loading.insert(k)
        Task {
            do {
                let m: ProbabilityModel?
                switch s {
                case .asset(let a):
                    let r = try await RatesFeed.series(a, .intraday)
                    var best = ProbabilityModel(points: r.points, source: r.source, price: r.price, crypto: !a.isFiat)
                    if a.isFiat, (best?.lastClose ?? .distantPast) < Date().addingTimeInterval(-3 * 3600),
                       let y = try? await MarketData.series(WatchItem(source: .yahoo, symbol: a.yahoo), interval: "15m"),
                       let ym = ProbabilityModel(points: y.candles.suffix(1000).map { PricePoint(time: $0.openTime, value: $0.close) },
                                                 source: y.source, price: y.quote.price, crypto: false),
                       ym.lastClose > (best?.lastClose ?? .distantPast) {
                        best = ym
                    }
                    m = best
                case .item(let i):
                    let r = try await MarketData.series(i, interval: "15m")
                    m = ProbabilityModel(points: r.candles.suffix(1000).map { PricePoint(time: $0.openTime, value: $0.close) },
                                         source: r.source, price: r.quote.price, crypto: i.isCrypto)
                }
                if let m {
                    models[k] = m
                    errors[k] = nil
                    fetched[k] = Date()
                } else {
                    errors[k] = "Not enough 15-minute history for \(s.short) right now"
                }
            } catch {
                AppLog.write("probabilities \(s.short) failed:", error.localizedDescription)
                errors[k] = "No connection to the rate sources"
            }
            loading.remove(k)
        }
    }


    func eraseAll() {
        models = [:]; errors = [:]; fetched = [:]
    }
}

extension HubSubject {
    @MainActor
    static func all(_ settings: AppSettings) -> [HubSubject] {
        let assets = settings.assets
        let coins = Set(assets.filter { !$0.isFiat }.map(\.code))
        return assets.map { .asset($0) } + settings.watchItems.filter { !($0.isCrypto && coins.contains($0.short)) }.map { .item($0) }
    }

    @MainActor
    static func match(itemID: String, _ settings: AppSettings) -> HubSubject? {
        let list = all(settings)
        if let s = list.first(where: { $0.id == "i|" + itemID }) { return s }
        guard let w = WatchItem(id: itemID), w.isCrypto else { return nil }
        return list.first { if case .asset(let a) = $0 { return !a.isFiat && a.code == w.short }; return false }
    }

    @MainActor
    static func find(_ name: String, _ settings: AppSettings) -> HubSubject? {
        let n = name.trimmingCharacters(in: .whitespaces).uppercased()
        guard !n.isEmpty else { return nil }
        return all(settings).first { $0.code.uppercased() == n || $0.short.uppercased() == n }
    }
}
