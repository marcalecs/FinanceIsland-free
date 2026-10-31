import Foundation

struct CatalogItem: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable { case index = "Index", commodity = "Commodity", etf = "ETF", stock = "Stock", crypto = "Crypto" }
    let symbol: String
    let name: String
    let kind: Kind
    var aliases: [String] = []
    var id: String { kind.rawValue + ":" + symbol }
    var source: MarketSource { kind == .crypto ? .binance : .yahoo }
}

enum SearchCatalog {
    static let items: [CatalogItem] = [
        .init(symbol: "^GSPC", name: "S&P 500", kind: .index, aliases: ["sp500", "spx", "snp", "s&p"]),
        .init(symbol: "^NDX", name: "Nasdaq 100", kind: .index, aliases: ["nasdaq", "ndx"]),
        .init(symbol: "^IXIC", name: "Nasdaq Composite", kind: .index, aliases: ["nasdaq composite"]),
        .init(symbol: "^DJI", name: "Dow Jones", kind: .index, aliases: ["dow", "djia"]),
        .init(symbol: "^RUT", name: "Russell 2000", kind: .index, aliases: ["russell"]),
        .init(symbol: "^VIX", name: "VIX volatility index", kind: .index, aliases: ["vix", "fear index"]),
        .init(symbol: "^GDAXI", name: "DAX", kind: .index, aliases: ["germany"]),
        .init(symbol: "^FTSE", name: "FTSE 100", kind: .index, aliases: ["uk"]),
        .init(symbol: "^N225", name: "Nikkei 225", kind: .index, aliases: ["japan"]),
        .init(symbol: "^HSI", name: "Hang Seng", kind: .index, aliases: ["hong kong"]),
        .init(symbol: "GC=F", name: "Gold", kind: .commodity, aliases: ["xau"]),
        .init(symbol: "SI=F", name: "Silver", kind: .commodity, aliases: ["xag"]),
        .init(symbol: "CL=F", name: "Crude oil WTI", kind: .commodity, aliases: ["oil", "wti"]),
        .init(symbol: "BZ=F", name: "Brent crude oil", kind: .commodity, aliases: ["brent"]),
        .init(symbol: "NG=F", name: "Natural gas", kind: .commodity, aliases: ["gas"]),
        .init(symbol: "HG=F", name: "Copper", kind: .commodity),
        .init(symbol: "PL=F", name: "Platinum", kind: .commodity),
        .init(symbol: "ZW=F", name: "Wheat", kind: .commodity),
        .init(symbol: "SPY", name: "SPDR S&P 500 ETF", kind: .etf, aliases: ["sp500", "s&p"]),
        .init(symbol: "VOO", name: "Vanguard S&P 500 ETF", kind: .etf, aliases: ["sp500", "s&p"]),
        .init(symbol: "QQQ", name: "Invesco QQQ (Nasdaq 100)", kind: .etf, aliases: ["nasdaq"]),
        .init(symbol: "DIA", name: "SPDR Dow Jones ETF", kind: .etf, aliases: ["dow"]),
        .init(symbol: "IWM", name: "iShares Russell 2000 ETF", kind: .etf, aliases: ["russell"]),
        .init(symbol: "GLD", name: "SPDR Gold Shares", kind: .etf, aliases: ["gold"]),
        .init(symbol: "SLV", name: "iShares Silver Trust", kind: .etf, aliases: ["silver"]),
        .init(symbol: "TLT", name: "iShares 20+ Year Treasury Bond", kind: .etf, aliases: ["bonds"]),
        .init(symbol: "VTI", name: "Vanguard Total Stock Market", kind: .etf),
        .init(symbol: "ARKK", name: "ARK Innovation ETF", kind: .etf),
        .init(symbol: "AAPL", name: "Apple", kind: .stock),
        .init(symbol: "MSFT", name: "Microsoft", kind: .stock),
        .init(symbol: "NVDA", name: "Nvidia", kind: .stock),
        .init(symbol: "GOOGL", name: "Alphabet (Google)", kind: .stock, aliases: ["google"]),
        .init(symbol: "AMZN", name: "Amazon", kind: .stock),
        .init(symbol: "META", name: "Meta (Facebook)", kind: .stock, aliases: ["facebook"]),
        .init(symbol: "TSLA", name: "Tesla", kind: .stock),
        .init(symbol: "AVGO", name: "Broadcom", kind: .stock),
        .init(symbol: "BRK-B", name: "Berkshire Hathaway", kind: .stock, aliases: ["berkshire"]),
        .init(symbol: "JPM", name: "JPMorgan Chase", kind: .stock),
        .init(symbol: "V", name: "Visa", kind: .stock),
        .init(symbol: "MA", name: "Mastercard", kind: .stock),
        .init(symbol: "NFLX", name: "Netflix", kind: .stock),
        .init(symbol: "AMD", name: "AMD", kind: .stock),
        .init(symbol: "INTC", name: "Intel", kind: .stock),
        .init(symbol: "KO", name: "Coca-Cola", kind: .stock),
        .init(symbol: "DIS", name: "Disney", kind: .stock),
        .init(symbol: "XOM", name: "Exxon Mobil", kind: .stock),
        .init(symbol: "BA", name: "Boeing", kind: .stock),
        .init(symbol: "PLTR", name: "Palantir", kind: .stock),
        .init(symbol: "COIN", name: "Coinbase", kind: .stock),
        .init(symbol: "BABA", name: "Alibaba", kind: .stock),
        .init(symbol: "TSM", name: "TSMC", kind: .stock),
        .init(symbol: "BTC", name: "Bitcoin", kind: .crypto),
        .init(symbol: "ETH", name: "Ethereum", kind: .crypto),
        .init(symbol: "SOL", name: "Solana", kind: .crypto),
        .init(symbol: "BNB", name: "BNB", kind: .crypto),
        .init(symbol: "XRP", name: "XRP", kind: .crypto, aliases: ["ripple"]),
        .init(symbol: "DOGE", name: "Dogecoin", kind: .crypto),
        .init(symbol: "TON", name: "Toncoin", kind: .crypto),
        .init(symbol: "ADA", name: "Cardano", kind: .crypto),
        .init(symbol: "TRX", name: "TRON", kind: .crypto),
        .init(symbol: "AVAX", name: "Avalanche", kind: .crypto),
        .init(symbol: "LINK", name: "Chainlink", kind: .crypto),
        .init(symbol: "DOT", name: "Polkadot", kind: .crypto),
        .init(symbol: "LTC", name: "Litecoin", kind: .crypto),
        .init(symbol: "SHIB", name: "Shiba Inu", kind: .crypto),
        .init(symbol: "PEPE", name: "Pepe", kind: .crypto),
        .init(symbol: "SUI", name: "Sui", kind: .crypto),
        .init(symbol: "NEAR", name: "NEAR Protocol", kind: .crypto),
        .init(symbol: "APT", name: "Aptos", kind: .crypto),
        .init(symbol: "ARB", name: "Arbitrum", kind: .crypto),
        .init(symbol: "OP", name: "Optimism", kind: .crypto),
    ]

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static func search(_ q: String) -> [CatalogItem] {
        let n = normalize(q)
        guard !n.isEmpty else { return [] }
        var scored: [(CatalogItem, Int)] = []
        for it in items {
            let keys = [it.symbol, it.name] + it.aliases
            let ns = keys.map(normalize)
            let ticker = normalize(it.symbol.replacingOccurrences(of: "^", with: ""))
            var score = 0
            if ticker == n || ns.contains(n) { score = 3 }
            else if ns.contains(where: { $0.hasPrefix(n) }) || ticker.hasPrefix(n) { score = 2 }
            else if ns.contains(where: { $0.contains(n) }) { score = 1 }
            if score > 0 { scored.append((it, score)) }
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func yahoo(_ q: String) async -> [CatalogItem] {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(enc)&quotesCount=8&newsCount=0") else { return [] }
        guard let d = try? await HTTP.get(url, timeout: 6),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let quotes = j["quotes"] as? [[String: Any]] else { return [] }
        return quotes.compactMap { qd in
            guard let sym = qd["symbol"] as? String else { return nil }
            let name = (qd["shortname"] as? String) ?? (qd["longname"] as? String) ?? sym
            let kind: CatalogItem.Kind
            switch (qd["quoteType"] as? String ?? "").uppercased() {
            case "INDEX": kind = .index
            case "ETF", "MUTUALFUND": kind = .etf
            case "FUTURE": kind = .commodity
            case "CRYPTOCURRENCY": return nil
            case "CURRENCY": return nil
            default: kind = .stock
            }
            return CatalogItem(symbol: sym, name: name, kind: kind)
        }
    }
}
