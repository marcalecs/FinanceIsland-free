import Foundation

enum TradeAssembler {
    struct Fill: Sendable, Equatable {
        enum Market: String, Sendable { case spot, futures }
        let id: Int64
        let orderID: Int64
        let symbol: String
        let market: Market
        let isBuy: Bool
        let price: Double
        let qty: Double
        let commission: Double
        let commissionAsset: String
        let time: Date
    }

    struct Trade: Sendable, Equatable {
        let symbol: String
        let market: Fill.Market
        let side: Signal
        let qty: Double
        let entry: Double
        let exit: Double
        let openedAt: Date
        let closedAt: Date
        let commission: Double
        let fillIDs: [String]
        var gross: Double { (side == .sell ? entry - exit : exit - entry) * qty }
        var net: Double { gross - commission }
    }

    struct Result: Sendable, Equatable {
        var trades: [Trade] = []
        var stillOpen: [String] = []
        var unmatchedSells = 0
    }

    typealias FeeConverter = (_ asset: String, _ amount: Double, _ fill: Fill) -> Double?

    static func id(_ f: Fill) -> String { "binance:\(f.market.rawValue):\(f.symbol):\(f.id)" }

    private struct Execution {
        let isBuy: Bool
        let price: Double
        let qty: Double
        let fee: Double
        let time: Date
        let ids: [String]
    }

    private static func executions(_ fills: [Fill], fee: FeeConverter) -> [Execution] {
        var order: [String] = []
        var groups: [String: [Fill]] = [:]
        for f in fills.sorted(by: { ($0.time, $0.id) < ($1.time, $1.id) }) {
            let k = "\(f.orderID)|\(f.isBuy)"
            if groups[k] == nil { order.append(k) }
            groups[k, default: []].append(f)
        }
        return order.compactMap { k in
            guard let g = groups[k], let first = g.first else { return nil }
            let qty = g.map(\.qty).reduce(0, +)
            guard qty > 0 else { return nil }
            return Execution(isBuy: first.isBuy, price: g.map { $0.price * $0.qty }.reduce(0, +) / qty, qty: qty,
                             fee: g.map { fee($0.commissionAsset, $0.commission, $0) ?? 0 }.reduce(0, +),
                             time: g.map(\.time).max() ?? first.time, ids: g.map(id))
        }
    }

    static func assemble(_ fills: [Fill], fee: FeeConverter) -> Result {
        var result = Result()
        let groups = Dictionary(grouping: fills, by: { "\($0.market.rawValue)|\($0.symbol)" })
        for key in groups.keys.sorted() {
            guard let list = groups[key], let any = list.first else { continue }
            let spot = any.market == .spot
            var pos = 0.0, openedQty = 0.0, entryValue = 0.0, exitValue = 0.0, fees = 0.0
            var opened = Date(), ids: [String] = []
            var side: Signal = .buy

            func open(_ x: Execution, qty: Double, fee: Double) {
                pos = x.isBuy ? qty : -qty
                side = x.isBuy ? .buy : .sell
                openedQty = qty; entryValue = x.price * qty; exitValue = 0; fees = fee
                opened = x.time; ids = x.ids
            }

            for x in executions(list, fee: fee) {
                if abs(pos) < 1e-12 {
                    if spot && !x.isBuy { result.unmatchedSells += 1; continue }
                    open(x, qty: x.qty, fee: x.fee)
                    continue
                }
                if (pos > 0) == x.isBuy {
                    pos += x.isBuy ? x.qty : -x.qty
                    openedQty += x.qty; entryValue += x.price * x.qty; fees += x.fee; ids += x.ids
                    continue
                }
                let closing = min(x.qty, abs(pos))
                let share = closing / x.qty
                exitValue += x.price * closing
                fees += x.fee * share
                ids += x.ids
                pos += pos > 0 ? -closing : closing
                guard abs(pos) <= 1e-9 * openedQty else { continue }
                result.trades.append(Trade(symbol: any.symbol, market: any.market, side: side, qty: openedQty,
                                           entry: entryValue / openedQty, exit: exitValue / openedQty,
                                           openedAt: opened, closedAt: x.time, commission: fees, fillIDs: ids))
                pos = 0
                let rest = x.qty - closing
                if rest > 1e-12 {
                    if spot && !x.isBuy { result.unmatchedSells += 1 } else { open(x, qty: rest, fee: x.fee * (1 - share)) }
                }
            }
            if abs(pos) > 1e-12 { result.stillOpen.append(any.symbol) }
        }
        result.trades.sort { $0.closedAt < $1.closedAt }
        return result
    }
}
