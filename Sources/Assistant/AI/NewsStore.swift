import Foundation

@MainActor
final class NewsStore: ObservableObject {
    static let shared = NewsStore()

    @Published private(set) var headlines: [String: [NewsItem]] = [:]
    @Published private(set) var summaries: [String: NewsSummary] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var summarizing: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    private var fetched: [String: Date] = [:]

    static func item(for s: HubSubject) -> WatchItem {
        switch s {
        case .item(let i): return i
        case .asset(let a): return a.isFiat ? WatchItem(source: .yahoo, symbol: a.yahoo) : WatchItem(source: .binance, symbol: a.code + "USDT")
        }
    }

    func load(_ s: HubSubject, settings: AppSettings) {
        let k = s.id
        if loading.contains(k) { return }
        if let t = fetched[k], Date().timeIntervalSince(t) < 1800 { return }
        loading.insert(k)
        Task {
            let news = await InsightService.news(for: Self.item(for: s))
            headlines[k] = news
            fetched[k] = Date()
            loading.remove(k)
            if settings.aiAutoInsight { summarize(s, settings: settings) }
        }
    }

    func summarize(_ s: HubSubject, settings: AppSettings, force: Bool = false) {
        let k = s.id
        guard settings.aiProvider != .off, settings.aiConsent, !summarizing.contains(k) else { return }
        let provider = settings.aiProvider, model = settings.aiModel
        let item = Self.item(for: s), name = s.name
        let label = provider.rawValue + "/" + model
        summarizing.insert(k)
        errors[k] = nil
        Task {
            if !force, let body = await AssistantDatabase.shared.cachedInsight(item: item, provider: label, maxAge: 3600),
               let data = body.data(using: .utf8), let cached = try? DataVault.decoder.decode(NewsSummary.self, from: data) {
                summaries[k] = cached
                summarizing.remove(k)
                return
            }
            var news = headlines[k] ?? []
            if news.isEmpty { news = await InsightService.news(for: item) }
            do {
                let r = try await InsightService.summarize(item, name: name, news: news, provider: provider, model: model,
                                                           key: Keychain.get(provider.rawValue))
                summaries[k] = r
                if let data = try? DataVault.encoder.encode(r), let body = String(data: data, encoding: .utf8) {
                    await AssistantDatabase.shared.storeInsight(item: item, provider: label, body: body)
                }
            } catch {
                errors[k] = error.localizedDescription
            }
            summarizing.remove(k)
        }
    }

    func eraseAll() { headlines = [:]; summaries = [:]; errors = [:]; fetched = [:] }
}
