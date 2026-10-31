import Foundation

enum RiskCalculator {
    static let defaultFee = 0.0004
    static let defaultBuffer = 0.00008

    struct Plan: Equatable, Sendable {
        let qty: Double
        let stop: Double
        let target: Double
        let actualRisk: Double
    }

    static func qty(risk: Double, entry: Double, slPercent: Double, fee: Double = defaultFee) -> Double {
        let k = entry * (slPercent / 100 + 2 * fee)
        return k > 0 && risk > 0 ? risk / k : 0
    }

    static func stopPrice(side: Signal, entry: Double, slPercent: Double) -> Double {
        entry * (side == .sell ? 1 + slPercent / 100 : 1 - slPercent / 100)
    }

    static func targetPrice(side: Signal, entry: Double, slPercent: Double, rr: Double) -> Double {
        entry * (side == .sell ? 1 - slPercent * rr / 100 : 1 + slPercent * rr / 100)
    }

    static func breakeven(side: Signal, entry: Double, fee: Double = defaultFee, buffer: Double = defaultBuffer) -> Double {
        entry * (side == .sell ? 1 - (2 * fee + buffer) : 1 + (2 * fee + buffer))
    }

    static func grossPnL(side: Signal, entry: Double, exit: Double, qty: Double) -> Double {
        (side == .sell ? entry - exit : exit - entry) * qty
    }

    static func commission(entry: Double, exit: Double, qty: Double, fee: Double = defaultFee) -> Double {
        (entry + exit) * qty * fee
    }

    static func netPnL(side: Signal, entry: Double, exit: Double, qty: Double, fee: Double = defaultFee) -> Double {
        grossPnL(side: side, entry: entry, exit: exit, qty: qty) - commission(entry: entry, exit: exit, qty: qty, fee: fee)
    }

    static func r(net: Double, risk: Double) -> Double? { risk > 0 ? net / risk : nil }

    static func riskAt(side: Signal, entry: Double, stop: Double, qty: Double, fee: Double = defaultFee) -> Double {
        -netPnL(side: side, entry: entry, exit: stop, qty: qty, fee: fee)
    }

    static func roundDown(_ v: Double, step: Double) -> Double {
        guard step > 0 else { return v }
        let n = (v / step * (1 + 1e-9)).rounded(.down)
        return n * step
    }

    static func roundPrice(_ v: Double, tick: Double) -> Double {
        guard tick > 0 else { return v }
        return (v / tick).rounded() * tick
    }

    static func manualStep(price: Double) -> Double {
        guard price > 0 else { return 1 }
        return pow(10, -floor(log10(price)))
    }

    static func plan(side: Signal, risk: Double, entry: Double, slPercent: Double, rr: Double, fee: Double = defaultFee,
                     step: Double, tick: Double = 0) -> Plan {
        let stop = roundPrice(stopPrice(side: side, entry: entry, slPercent: slPercent), tick: tick)
        let target = roundPrice(targetPrice(side: side, entry: entry, slPercent: slPercent, rr: rr), tick: tick)
        let q = roundDown(qty(risk: risk, entry: entry, slPercent: slPercent, fee: fee), step: step)
        return Plan(qty: q, stop: stop, target: target, actualRisk: riskAt(side: side, entry: entry, stop: stop, qty: q, fee: fee))
    }

    static func qty(risk: Double, entry: Double, stop: Double, fee: Double = defaultFee) -> Double {
        guard entry > 0 else { return 0 }
        return qty(risk: risk, entry: entry, slPercent: abs(entry - stop) / entry * 100, fee: fee)
    }
}
