import SwiftUI

struct ChartOverlays: OptionSet, Hashable {
    let rawValue: Int
    static let sma20 = ChartOverlays(rawValue: 1)
    static let sma50 = ChartOverlays(rawValue: 2)
    static let sma200 = ChartOverlays(rawValue: 4)
    static let bands = ChartOverlays(rawValue: 8)
}
