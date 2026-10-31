import SwiftUI

enum AssetFormat {
    static func compact(_ v: Double) -> String {
        switch v {
        case 1e12...: return String(format: "%.1fT", v / 1e12)
        case 1e9...: return String(format: "%.1fB", v / 1e9)
        case 1e6...: return String(format: "%.1fM", v / 1e6)
        case 1e3...: return String(format: "%.0fK", v / 1e3)
        default: return String(format: "%.0f", v)
        }
    }

    static func price(_ p: Double) -> String {
        switch abs(p) {
        case 1000...: return Fmt.number(p, min: 2, max: 2)
        case 1..<1000: return Fmt.number(p, min: 2, max: 4)
        default: return Fmt.number(p, min: 4, max: 8)
        }
    }
}


@MainActor
struct SignalBadgeView: View {
    let signal: Signal
    var size: CGFloat = 11
    @Environment(\.look) private var look

    var body: some View {
        Text(tr(signal.rawValue))
            .font(.system(size: size, weight: .heavy))
            .kerning(0.6)
            .foregroundStyle(.white)
            .frame(width: size * 4.8, height: size * 1.9)
            .background(Capsule().fill(color.opacity(0.9)))
    }

    private var color: Color {
        switch signal {
        case .buy: return look.trend.green
        case .sell: return look.trend.red
        case .hold: return Color(white: 0.4)
        }
    }
}


struct PillLink: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Label(tr(title), systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(look.theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

struct PercentBar: View {
    let value: Double
    let color: Color
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(look.theme.selected.opacity(0.6))
                Capsule().fill(color).frame(width: max(geo.size.width * CGFloat(min(max(value, 0), 100) / 100), 3))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
            }
        }
        .frame(height: 6)
    }
}
