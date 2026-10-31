import Foundation

enum Signal: String, Sendable, Codable {
    case buy = "BUY", sell = "SELL", hold = "HOLD"
}
