import AppKit
import SwiftUI

@MainActor
final class BenchmarkStore: ObservableObject {
    static let shared = BenchmarkStore()

    enum Range: String, CaseIterable { case month = "1M", quarter = "3M", year = "1Y", all = "All" }

    struct Result: Equatable {
        var portfolio: [Double]
        var spx: [Double]
        var btc: [Double]
        var from: Date
    }

    @Published private(set) var results: [Range: Result] = [:]
    @Published private(set) var loading: Set<Range> = []
    private var loaded: [Range: (Date, String)] = [:]

    nonisolated static let stable: Set<String> = ["USDT", "USDC", "FDUSD", "DAI", "BUSD", "TUSD", "PYUSD", "USDE"]

    func load(_ range: Range, holdings: [Holding]) {
        let store = LongTermStore.shared
        let key = holdings.map { "\($0.symbol)\($0.amount)" }.sorted().joined()
        if let l = loaded[range], l.1 == key, Date().timeIntervalSince(l.0) < 1800 { return }
        guard !loading.contains(range) else { return }
        let now = Date()
        let start: Date
        switch range {
        case .month: start = now.addingTimeInterval(-30 * 86_400)
        case .quarter: start = now.addingTimeInterval(-91 * 86_400)
        case .year: start = now.addingTimeInterval(-365 * 86_400)
        case .all: start = holdings.compactMap { store.entryDate(for: $0) }.min() ?? now.addingTimeInterval(-365 * 86_400)
        }
        let parts = holdings.map { (symbol: $0.symbol, crypto: $0.crypto, amount: $0.amount, usd: store.toUSD(1, store.currency($0.symbol)) ?? 1) }
        loading.insert(range)
        Task {
            let r = await Self.compute(parts, from: min(start, now.addingTimeInterval(-7 * 86_400)))
            if let r { results[range] = r }
            loaded[range] = (Date(), key)
            loading.remove(range)
        }
    }

    nonisolated static func compute(_ parts: [(symbol: String, crypto: Bool, amount: Double, usd: Double)], from: Date) async -> Result? {
        let symbols = Dictionary(parts.filter { !stable.contains($0.symbol) }.map { ($0.symbol, $0.crypto) }, uniquingKeysWith: { a, _ in a })
        var closes: [String: [String: Double]] = [:]
        await withTaskGroup(of: (String, [String: Double]).self) { g in
            for (s, c) in symbols { g.addTask { (s, await daily(s, crypto: c, from: from)) } }
            g.addTask { ("^GSPC#", await daily("^GSPC", crypto: false, from: from)) }
            g.addTask { ("BTC#", await daily("BTC", crypto: true, from: from)) }
            for await (s, v) in g { closes[s] = v }
        }
        var days: [String] = []
        var d = from
        while d <= Date() { days.append(dayKey(d)); d = d.addingTimeInterval(86_400) }
        func filled(_ m: [String: Double]) -> [Double?] {
            var last: Double?
            return days.map { k in if let v = m[k] { last = v }; return last }
        }
        let spx = filled(closes["^GSPC#"] ?? [:]), btc = filled(closes["BTC#"] ?? [:])
        let series = parts.map { p in (p, stable.contains(p.symbol) ? days.map { _ in Double?(1) } : filled(closes[p.symbol] ?? [:])) }
        var pv: [Double?] = []
        for i in days.indices {
            var sum = 0.0, ok = true
            for (p, s) in series { if let v = s[i] { sum += v * p.amount * p.usd } else { ok = false } }
            pv.append(ok && sum > 0 ? sum : nil)
        }
        guard let first = days.indices.first(where: { pv[$0] != nil && spx[$0] != nil && btc[$0] != nil }) else { return nil }
        func pct(_ s: [Double?]) -> [Double] {
            guard let base = s[first] else { return [] }
            var last = base
            return s[first...].map { v in if let v { last = v }; return last / base - 1 }
        }
        let start = from.addingTimeInterval(Double(first) * 86_400)
        return Result(portfolio: pct(pv), spx: pct(spx), btc: pct(btc), from: start)
    }

    nonisolated static func dayKey(_ d: Date) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let x = c.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", x.year ?? 0, x.month ?? 0, x.day ?? 0)
    }

    nonisolated static func daily(_ symbol: String, crypto: Bool, from: Date) async -> [String: Double] {
        var out: [String: Double] = [:]
        if crypto {
            let ms = Int(from.addingTimeInterval(-86_400).timeIntervalSince1970 * 1000)
            guard let d = try? await HTTP.get("https://api.binance.com/api/v3/klines?symbol=\(symbol)USDT&interval=1d&startTime=\(ms)&limit=1000"),
                  let a = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { return [:] }
            for k in a where k.count > 6 {
                guard let t = (k[6] as? NSNumber)?.doubleValue, let c = Double(k[4] as? String ?? "") else { continue }
                out[dayKey(Date(timeIntervalSince1970: t / 1000))] = c
            }
            return out
        }
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let d = try? await HTTP.get("https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?period1=\(Int(from.timeIntervalSince1970) - 5 * 86_400)&period2=\(Int(Date().timeIntervalSince1970))&interval=1d"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let res = ((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let ts = res["timestamp"] as? [Double],
              let cl = (((res["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"] as? [Any]) else { return [:] }
        let offset = ((res["meta"] as? [String: Any])?["gmtoffset"] as? NSNumber)?.doubleValue ?? 0
        for (t, c) in zip(ts, cl) { if let v = (c as? NSNumber)?.doubleValue { out[dayKey(Date(timeIntervalSince1970: t + offset))] = v } }
        return out
    }
}

@MainActor
struct BenchmarkCard: View {
    let holdings: [Holding]
    @ObservedObject private var store = BenchmarkStore.shared
    @AppStorage("benchmarkRange") private var range: BenchmarkStore.Range = .quarter
    @Environment(\.look) private var look

    var body: some View {
        let r = store.results[range]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Compared with the S&P 500 and BTC")).font(.system(size: 14, weight: .bold))
                Spacer()
                PillPicker(options: BenchmarkStore.Range.allCases, selection: $range, label: { $0 == .all ? "Since start" : $0.rawValue }, minWidth: 36)
            }
            if let r, !r.portfolio.isEmpty {
                HStack(spacing: 14) {
                    legend("Portfolio", r.portfolio.last ?? 0, look.accent, dash: false)
                    legend("S&P 500", r.spx.last ?? 0, .white.opacity(0.75), dash: false)
                    legend("BTC", r.btc.last ?? 0, .white.opacity(0.75), dash: true)
                    Spacer()
                    Text(tr("since \(Fmt.date(r.from, "d MMM yyyy"))")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                chart(r).frame(height: 120)
            } else {
                Text(store.loading.contains(range) ? tr("Loading daily closes…") : tr("Not enough price history yet."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, minHeight: 60)
            }
            Text(tr("Your current holdings valued at each day's close; buys and sells in between aren't counted. Past returns say nothing about the future."))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        .onAppear { store.load(range, holdings: holdings) }
        .onChange(of: range) { _, r in store.load(r, holdings: holdings) }
    }

    private func legend(_ name: String, _ v: Double, _ c: Color, dash: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(c).frame(width: 14, height: dash ? 1.5 : 2.5).opacity(dash ? 0.8 : 1)
            Text(tr(name)).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7))
            Text(String(format: "%+.1f%%", v * 100)).font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(look.pnl(v))
        }
    }

    private func chart(_ r: BenchmarkStore.Result) -> some View {
        let all = r.portfolio + r.spx + r.btc
        let lo = min(all.min() ?? 0, 0), hi = max(all.max() ?? 0, 0)
        let span = max(hi - lo, 0.0001)
        return GeometryReader { g in
            ZStack {
                Path { p in
                    let y0 = g.size.height * CGFloat(1 - (0 - lo) / span)
                    p.move(to: CGPoint(x: 0, y: y0)); p.addLine(to: CGPoint(x: g.size.width, y: y0))
                }
                .stroke(look.theme.line, lineWidth: 1)
                Self.path(r.btc, g.size, lo, span).stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))
                Self.path(r.spx, g.size, lo, span).stroke(.white.opacity(0.75), lineWidth: 1.5)
                Self.path(r.portfolio, g.size, lo, span).stroke(look.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private static func path(_ s: [Double], _ size: CGSize, _ lo: Double, _ span: Double) -> Path {
        Path { p in
            for (i, v) in s.enumerated() {
                let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(max(s.count - 1, 1)), y: size.height * CGFloat(1 - (v - lo) / span))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }
}

@MainActor
final class PortfolioNews: ObservableObject {
    static let shared = PortfolioNews()
    @Published private(set) var items: [(symbol: String, news: NewsItem)] = []
    @Published private(set) var loading = false
    private var loadedAt: Date?
    private var key = ""

    func load(_ holdings: [Holding]) {
        let store = LongTermStore.shared
        let top = Dictionary(holdings.filter { !BenchmarkStore.stable.contains($0.symbol) }.map { ($0.symbol, ($0.crypto, store.valueUSD($0) ?? 0)) },
                             uniquingKeysWith: { a, b in (a.0, a.1 + b.1) })
            .sorted { $0.value.1 > $1.value.1 }.prefix(5).map { ($0.key, $0.value.0) }
        let k = top.map(\.0).joined(separator: ",")
        if k == key, let t = loadedAt, Date().timeIntervalSince(t) < 1800 { return }
        guard !loading else { return }
        key = k
        loading = true
        Task {
            var all: [(String, NewsItem)] = []
            await withTaskGroup(of: [(String, NewsItem)].self) { g in
                for (sym, crypto) in top {
                    g.addTask {
                        let item = crypto ? WatchItem(source: .binance, symbol: sym + "USDT") : WatchItem(source: .yahoo, symbol: sym)
                        return await InsightService.news(for: item, limit: 4).map { (sym, $0) }
                    }
                }
                for await r in g { all += r }
            }
            var seen = Set<String>()
            items = all.filter { seen.insert($0.1.title.lowercased()).inserted }.sorted { $0.1.published > $1.1.published }
                .prefix(8).map { (symbol: $0.0, news: $0.1) }
            loadedAt = Date()
            loading = false
        }
    }
}

@MainActor
struct PortfolioNewsCard: View {
    let holdings: [Holding]
    @ObservedObject private var news = PortfolioNews.shared
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Headlines for your positions")).font(.system(size: 14, weight: .bold))
            if news.items.isEmpty {
                Text(news.loading ? tr("Loading headlines…") : tr("No recent headlines."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(news.items, id: \.news.id) { n in
                Button { if let u = URL(string: n.news.link) { NSWorkspace.shared.open(u) } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(n.symbol).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white.opacity(0.6)).frame(width: 46, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.news.title).font(.system(size: 12.5)).lineLimit(2).multilineTextAlignment(.leading)
                            Text(n.news.publisher + " · " + Fmt.date(n.news.published, "d MMM HH:mm"))
                                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { ($0 ? NSCursor.pointingHand : NSCursor.arrow).set() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        .onAppear { news.load(holdings) }
    }
}
