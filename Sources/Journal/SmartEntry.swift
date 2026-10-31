import Foundation

enum SmartEntry: Equatable {
    case hold(symbol: String, amount: Double, price: Double?)
    case trade(side: Signal, symbol: String, entry: Double?, stop: Double?, target: Double?, exit: Double?, qty: Double?)

    private static let holdWords: Set<String> = ["buy", "bought", "add", "hold", "купил", "купить", "добавь", "держу"]
    private static let longWords: Set<String> = ["long", "лонг"]
    private static let shortWords: Set<String> = ["short", "шорт"]
    private static let stopWords: Set<String> = ["stop", "sl", "стоп"]
    private static let targetWords: Set<String> = ["target", "tp", "take", "тейк", "цель"]
    private static let exitWords: Set<String> = ["exit", "closed", "close", "out", "закрыл", "выход"]
    private static let atWords: Set<String> = ["at", "@", "по", "entry", "вход"]
    private static let qtyWords: Set<String> = ["qty", "size", "объем", "объём"]
    private static let filler: Set<String> = ["of", "shares", "share", "units", "штук", "шт", "x"]

    static func number(_ s: Substring) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: CharacterSet(charactersIn: "$@€k"))
        guard var v = Double(t) else { return nil }
        if s.lowercased().hasSuffix("k") { v *= 1000 }
        return v > 0 ? v : nil
    }

    private static func isSymbol(_ w: Substring) -> Bool {
        w.count <= 12 && w.contains(where: \.isLetter) && w.allSatisfy { $0.isLetter || $0.isNumber || ".-^=".contains($0) }
    }

    static func parse(_ text: String) -> SmartEntry? {
        let words = text.lowercased().replacingOccurrences(of: "@", with: " @ ").split(whereSeparator: \.isWhitespace)
        guard let verb = words.first else { return nil }
        let rest = Array(words.dropFirst())
        var symbol: String?
        var numbers: [Double] = []
        var tagged: [String: Double] = [:]
        var pending: String?
        for w in rest {
            if atWords.contains(String(w)) { pending = "at"; continue }
            if stopWords.contains(String(w)) { pending = "stop"; continue }
            if targetWords.contains(String(w)) { pending = "target"; continue }
            if exitWords.contains(String(w)) { pending = "exit"; continue }
            if qtyWords.contains(String(w)) { pending = "qty"; continue }
            if filler.contains(String(w)) { continue }
            if let n = number(w) {
                if let p = pending { tagged[p] = n; pending = nil } else { numbers.append(n) }
            } else if symbol == nil, isSymbol(w) {
                symbol = w.uppercased()
            }
        }
        guard let sym = symbol else { return nil }
        let v = String(verb)
        if holdWords.contains(v) {
            guard let amount = tagged["qty"] ?? numbers.first else { return nil }
            let price = tagged["at"] ?? (tagged["qty"] == nil ? numbers.dropFirst().first : numbers.first)
            return .hold(symbol: sym, amount: amount, price: price)
        }
        let side: Signal
        if longWords.contains(v) { side = .buy } else if shortWords.contains(v) { side = .sell } else { return nil }
        return .trade(side: side, symbol: sym, entry: tagged["at"] ?? numbers.first, stop: tagged["stop"],
                      target: tagged["target"], exit: tagged["exit"], qty: tagged["qty"])
    }
}

enum SmartComplete {
    static let verbs = ["bought", "buy", "add", "hold", "long", "short", "купил", "лонг", "шорт"]
    static let keywords = ["at", "stop", "target", "closed", "qty", "по", "стоп", "тейк", "закрыл"]

    static func suggest(_ text: String, symbols: [String], price: (String) -> Double?) -> String? {
        guard !text.isEmpty, !text.hasSuffix("  ") else { return nil }
        let endsWithSpace = text.hasSuffix(" ")
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let first = words.first else { return nil }
        let head = words.dropLast().joined(separator: " ")
        let prefix = head.isEmpty ? "" : head + " "
        if words.count == 1 && !endsWithSpace {
            guard let v = verbs.first(where: { $0.hasPrefix(first.lowercased()) && $0 != first.lowercased() }) else { return nil }
            return v + " "
        }
        let verb = first.lowercased()
        let isTrade = ["long", "short", "лонг", "шорт"].contains(verb)
        let isHold = ["bought", "buy", "add", "hold", "купил"].contains(verb)
        guard isTrade || isHold else { return nil }
        let last = words.last ?? ""
        if !endsWithSpace, words.count >= 2, last.contains(where: \.isLetter) {
            let hasTicker = words.dropFirst().dropLast().contains { $0.contains(where: \.isLetter) && SmartEntry.number(Substring($0)) == nil }
            if hasTicker {
                let low = last.lowercased()
                guard let kw = keywords.first(where: { $0.hasPrefix(low) && $0 != low }) else { return nil }
                return prefix + kw + " "
            }
            let up = last.uppercased()
            guard let sym = symbols.first(where: { $0.hasPrefix(up) && $0 != up }) else { return nil }
            return prefix + sym + " "
        }
        guard endsWithSpace else { return nil }
        let ticker = words.dropFirst().first { $0.contains(where: \.isLetter) && SmartEntry.number(Substring($0)) == nil }?.uppercased()
        guard let ticker, let px = price(ticker), px > 0 else { return nil }
        let f = { (v: Double) in fmt(v, like: px) }
        let lower = text.lowercased()
        if isTrade && words.count == 2 {
            let sell = verb == "short" || verb == "шорт"
            let stop = px * (sell ? 1.01 : 0.99), target = px * (sell ? 0.98 : 1.02)
            return text + "\(f(px)) stop \(f(stop)) target \(f(target))"
        }
        if isHold, !lower.contains(" at "), !lower.contains(" по "), !lower.contains("@"), words.count >= 3,
           words.contains(where: { SmartEntry.number(Substring($0)) != nil }) {
            return text + (verb == "купил" ? "по " : "at ") + f(px)
        }
        if isHold && words.count == 2 { return text + "1 at " + f(px) }
        return nil
    }

    static func fmt(_ v: Double, like p: Double) -> String {
        let d = p >= 1000 ? 0 : p >= 10 ? 2 : p >= 1 ? 3 : 5
        return String(format: "%.\(d)f", v)
    }
}
