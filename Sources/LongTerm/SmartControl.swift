import Foundation
import SwiftUI

struct SmartControl: Sendable {
    enum Health: String, Sendable {
        case accumulation = "Accumulation zone", healthy = "Healthy uptrend", overheated = "Overheated / take profit"
        case drawdown = "High drawdown alert", developing = "Developing"
    }
    struct Tier: Identifiable, Sendable {
        let id: Int
        let price: Double
        let gain: Double
        let action: String
        let reached: Bool
    }
    struct DCA: Sendable {
        let low: Double, high: Double
        let previews: [(share: Double, average: Double)]
    }

    let pnl: Double?
    let health: Health
    let weight: Double
    let overweight: Bool
    let trailingStop: Double
    let dca: DCA
    let tiers: [Tier]
    let directive: String
}

extension LongTermStore {
    func smart(for h: Holding, total: Double, count: Int) -> SmartControl? {
        guard let price = prices[h.symbol], price > 0 else { return nil }
        let entry = self.entry(for: h)
        let mo = trend[h.symbol]
        let score = mo?.score ?? 0
        let falling = mo?.direction == .sell, rising = mo?.direction == .buy
        let sd = max(dailySigma[h.symbol] ?? 0.02, 0.002)
        let week = sd * sqrt(5)
        let pnl = entry.map { price / $0 - 1 }
        let value = valueUSD(h) ?? price * h.amount
        let weight = total > 0 ? value / total : 0

        var trail = price * exp(-2 * week)
        if let e = entry, let p = pnl, p >= 0.5 { trail = max(trail, e) }

        let low = price * exp(-2 * week), high = price * exp(-1 * week), mid = (low + high) / 2
        let base = entry ?? price
        let previews: [(share: Double, average: Double)] = [0.25, 0.5, 1.0].map { k in (share: k, average: (base * h.amount + mid * k * h.amount) / (h.amount * (1 + k))) }

        var tiers: [SmartControl.Tier] = []
        if let e = entry {
            tiers = [
                .init(id: 1, price: e * 1.2, gain: 0.2, action: "Sell 25%", reached: price >= e * 1.2),
                .init(id: 2, price: e * 1.5, gain: 0.5, action: "Move the stop to breakeven", reached: price >= e * 1.5),
                .init(id: 3, price: e * 2.0, gain: 1.0, action: "Sell another 25%", reached: price >= e * 2.0),
            ]
        }

        let health: SmartControl.Health
        if let p = pnl {
            if p >= 0.4 || (score > 2 && p > 0.15) { health = .overheated }
            else if p <= -0.2 || (falling && p <= -0.1) { health = .drawdown }
            else if p <= -0.05 && !falling { health = .accumulation }
            else if rising || p > 0 { health = .healthy }
            else { health = .developing }
        } else {
            health = score > 2 ? .overheated : rising ? .healthy : falling ? .drawdown : .developing
        }

        let cur = currency(h.symbol)
        let f = { (v: Double) in LongTermStore.money(v, cur) }
        let since = entryDate(for: h).map { " " + tr("since your entry on \(Fmt.date($0, "d MMMM"))") } ?? ""
        let directive: String
        if let p = pnl {
            let pct = String(format: "%+.1f%%", p * 100)
            if p >= 0.2 {
                directive = tr("\(pct)\(since). Your first take-profit rule (+20 %) has triggered; the trailing stop is at \(f(trail)).")
            } else if p >= 0 {
                directive = tr("\(pct)\(since). First take-profit rule at \(f(tiers.first?.price ?? price * 1.2)); protective stop at \(f(trail)).")
            } else if p > -0.1 {
                directive = tr("\(pct)\(since). Stop at \(f(trail)); the buy-more zone is \(f(low)) – \(f(high)).")
            } else if !falling {
                directive = tr("\(pct)\(since): inside the buy-more zone. Adding 50 % at \(f(mid)) would make the average \(f(previews[1].average)).")
            } else {
                directive = tr("\(pct)\(since) and still falling; the risk limit is at \(f(trail)).")
            }
        } else {
            directive = tr("Set your entry time and price to see your rule levels.")
        }

        return SmartControl(pnl: pnl, health: health, weight: weight, overweight: count > 1 && weight > 0.4,
                            trailingStop: trail, dca: .init(low: low, high: high, previews: previews),
                            tiers: tiers, directive: directive)
    }
}

func heldFor(_ d: Date) -> String {
    let s = max(0, Date().timeIntervalSince(d))
    let days = Int(s / 86_400), hours = Int(s.truncatingRemainder(dividingBy: 86_400) / 3600)
    let mins = Int(s.truncatingRemainder(dividingBy: 3600) / 60)
    if days > 0 { return tr("\(days)d \(hours)h") }
    if hours > 0 { return tr("\(hours)h \(mins)m") }
    return tr("\(mins)m")
}
