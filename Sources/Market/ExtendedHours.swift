import SwiftUI

enum ExtendedHours {
    enum Session: String, Sendable { case pre = "Pre-market", post = "After hours" }

    struct Quote: Sendable, Equatable {
        let session: Session
        let price: Double
        let change: Double
        let at: Date
    }

    static func quote(_ symbol: String) async -> Quote? {
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let d = try? await HTTP.get("https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=1d&interval=5m&includePrePost=true"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let res = ((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let meta = res["meta"] as? [String: Any] else { return nil }
        let type = meta["instrumentType"] as? String ?? ""
        guard meta["exchangeTimezoneName"] as? String == "America/New_York", ["EQUITY", "ETF"].contains(type),
              let regular = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue, regular > 0,
              let period = meta["currentTradingPeriod"] as? [String: Any],
              let reg = period["regular"] as? [String: Any],
              let regStart = (reg["start"] as? NSNumber)?.doubleValue, let regEnd = (reg["end"] as? NSNumber)?.doubleValue,
              let ts = res["timestamp"] as? [Double],
              let closes = (((res["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"] as? [Any]) else { return nil }
        guard let (t, price) = zip(ts, closes).reversed().compactMap({ t, c in (c as? NSNumber).map { (t, $0.doubleValue) } }).first,
              t < regStart || t >= regEnd else { return nil }
        let reference = t < regStart ? ((meta["chartPreviousClose"] as? NSNumber)?.doubleValue ?? regular) : regular
        return Quote(session: t < regStart ? .pre : .post, price: price, change: price / reference - 1, at: Date(timeIntervalSince1970: t))
    }
}

struct ExtendedHoursTag: View {
    let symbol: String
    let format: (Double) -> String
    @State private var q: ExtendedHours.Quote?
    @Environment(\.look) private var look

    var body: some View {
        Group {
            if let q {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(q.session.rawValue) + " · " + Fmt.date(q.at, "HH:mm")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(format(q.price)).font(.system(size: 13, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                        Text(String(format: "%+.2f%%", q.change * 100)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(look.pnl(q.change))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .help(tr("Extended-hours trade outside the regular session, reported by Yahoo Finance"))
            }
        }
        .task(id: symbol) {
            while !Task.isCancelled {
                q = await ExtendedHours.quote(symbol)
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
        }
    }
}
