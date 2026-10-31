import Foundation

struct PriceAlert: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable { case above, below, risesBy, fallsBy }

    var id = UUID()
    var subject: String
    var name: String
    var kind: Kind
    var value: Double
    var hours: Double = 24
    var createdAt = Date()
    var active = true
    var firedAt: Date?
    var firedPrice: Double?

    var isChange: Bool { kind == .risesBy || kind == .fallsBy }

    func isMet(price: Double, reference: Double?) -> Bool {
        switch kind {
        case .above: return price >= value
        case .below: return price <= value
        case .risesBy, .fallsBy:
            guard let ref = reference, ref > 0 else { return false }
            let change = (price / ref - 1) * 100
            return kind == .risesBy ? change >= value : change <= -value
        }
    }
}
