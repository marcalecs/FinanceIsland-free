import Foundation

struct NewsItem: Identifiable, Sendable, Codable, Hashable {
    let id: String
    let title: String
    let publisher: String
    let link: String
    let published: Date
}

struct NewsSummary: Sendable, Codable {
    let summary: String
    let points: [String]
    let cited: [Int]
    let news: [NewsItem]
    let provider: String
    let createdAt: Date
}

enum InsightService {
    static func news(for item: WatchItem, limit: Int = 8) async -> [NewsItem] {
        async let feed = rss(item)
        async let search = searchNews(item)
        async let google = googleNews(item)
        var seen = Set<String>()
        let all = (await feed + (await search) + (await google)).filter { seen.insert($0.title.lowercased()).inserted }
        let keys = keywords(item)
        func relevant(_ n: NewsItem) -> Bool {
            let t = n.title.lowercased()
            return keys.contains { t.contains($0) }
        }
        let recent = all.filter { Date().timeIntervalSince($0.published) < 7 * 86_400 }
        let ranked = recent.filter(relevant).sorted { $0.published > $1.published }
            + recent.filter { !relevant($0) }.sorted { $0.published > $1.published }
        return Array(ranked.prefix(limit))
    }

    static func keywords(_ item: WatchItem) -> [String] {
        let names: [String: [String]] = [
            "BTC": ["bitcoin", "btc"], "ETH": ["ethereum", "ether", "eth"], "SOL": ["solana"], "BNB": ["bnb", "binance coin"],
            "XRP": ["xrp", "ripple"], "DOGE": ["dogecoin", "doge"], "TON": ["toncoin", "ton "], "ADA": ["cardano"],
            "AAPL": ["apple"], "MSFT": ["microsoft"], "NVDA": ["nvidia"], "TSLA": ["tesla"], "AMZN": ["amazon"],
            "SPY": ["s&p", "stock market", "stocks"], "QQQ": ["nasdaq", "tech stocks"],
        ]
        return [item.short.lowercased()] + (names[item.short] ?? [])
    }

    private static func rss(_ item: WatchItem) async -> [NewsItem] {
        let q = item.newsQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.newsQuery
        guard let url = URL(string: "https://feeds.finance.yahoo.com/rss/2.0/headline?s=\(q)&region=US&lang=en-US") else { return [] }
        guard let data = try? await HTTP.get(url, timeout: 12) else { return [] }
        return RSSParser.parse(data)
    }

    private static func googleNews(_ item: WatchItem) async -> [NewsItem] {
        let names = keywords(item).dropFirst().first.map { " OR \($0)" } ?? ""
        let q = "\(item.short)\(names) \(item.isCrypto ? "crypto" : "stock")"
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let data = try? await HTTP.get("https://news.google.com/rss/search?q=\(enc)&hl=en-US&gl=US&ceid=US:en", timeout: 12)
        else { return [] }
        return RSSParser.parse(data).map { n in
            guard let dash = n.title.range(of: " - ", options: .backwards) else { return n }
            return NewsItem(id: n.id, title: String(n.title[..<dash.lowerBound]),
                            publisher: n.publisher == "news.google.com" ? String(n.title[dash.upperBound...]) : n.publisher,
                            link: n.link, published: n.published)
        }
    }

    private static func searchNews(_ item: WatchItem) async -> [NewsItem] {
        let q = item.newsQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.newsQuery
        guard let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(q)&newsCount=8&quotesCount=0") else { return [] }
        guard let data = try? await HTTP.get(url, timeout: 12),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["news"] as? [[String: Any]] else { return [] }
        return raw.compactMap { n in
            guard let title = n["title"] as? String, let link = n["link"] as? String else { return nil }
            let t = (n["providerPublishTime"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
            return NewsItem(id: n["uuid"] as? String ?? link, title: title,
                            publisher: n["publisher"] as? String ?? "", link: link,
                            published: Date(timeIntervalSince1970: t))
        }
    }

    static func summarize(_ item: WatchItem, name: String?, news: [NewsItem], provider: AIProvider, model: String,
                          key: String?) async throws -> NewsSummary {
        let label = provider.name + (model.isEmpty ? "" : " · " + model)
        let answer = try await AIClient.complete(provider: provider, model: model, key: key,
                                                 system: systemPrompt, user: prompt(item, name: name, news: news))
        return parse(answer, news: news, provider: label)
            ?? NewsSummary(summary: clean(answer), points: [], cited: [], news: news, provider: label, createdAt: Date())
    }

    private static let systemPrompt = """
    You summarise market news for a macOS widget. Explain what happened and why, using ONLY the headlines given.
    Do not predict prices. Do not say whether the asset will rise or fall, do not call anything bullish or bearish,
    do not give a confidence score, and never tell the user to buy, sell or hold.
    If the headlines are few, old or unrelated to the asset, say so plainly.
    Reply with ONE JSON object and nothing else:
    {"summary":"what happened, max 60 words","points":["max 3 items: event — why it matters"],"cited":[headline numbers you used]}
    """

    private static func prompt(_ item: WatchItem, name: String?, news: [NewsItem]) -> String {
        var s = "Asset: \(item.display)" + (name.map { " (\($0))" } ?? "") + "\n\nHeadlines (newest first):\n"
        if news.isEmpty { s += "(none found)\n" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        for (i, n) in news.enumerated() {
            s += "\(i + 1). [\(f.string(from: n.published))] \(n.publisher): \(n.title)\n"
        }
        s += "\nToday is \(f.string(from: Date())). What happened, and why?"
        return s
    }

    private struct Raw: Decodable {
        let summary: String?
        let points: [String]?
        let cited: [Int]?
    }

    private static func parse(_ text: String, news: [NewsItem], provider: String) -> NewsSummary? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let data = String(text[start...end]).data(using: .utf8),
              let r = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        return NewsSummary(summary: r.summary ?? "", points: Array((r.points ?? []).prefix(3)),
                           cited: (r.cited ?? []).filter { $0 >= 1 && $0 <= news.count },
                           news: news, provider: provider, createdAt: Date())
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [NewsItem] = []
    private var field = ""
    private var title = "", link = "", date = "", guid = ""
    private var inItem = false

    static func parse(_ data: Data) -> [NewsItem] {
        let p = RSSParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.items
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f
    }()

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "item" { inItem = true; title = ""; link = ""; date = ""; guid = "" }
        field = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { field += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inItem else { return }
        let v = field.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title": title = v
        case "link": link = v
        case "pubDate": date = v
        case "guid": guid = v
        case "item":
            inItem = false
            if !title.isEmpty, !link.isEmpty {
                let host = URL(string: link)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
                items.append(NewsItem(id: guid.isEmpty ? link : guid, title: title, publisher: host, link: link,
                                      published: Self.dateFormat.date(from: date) ?? Date()))
            }
        default: break
        }
    }
}
