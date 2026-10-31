import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let island: Color
    let card: Color
    let chip: Color
    let selected: Color
    let line: Color

    static let midnight = Theme(id: "midnight", name: "Midnight",
                                island: .black, card: Color(white: 0.07), chip: Color(white: 0.11),
                                selected: Color(white: 0.23), line: Color(white: 0.14))
    static let graphite = Theme(id: "graphite", name: "Graphite",
                                island: Color(white: 0.10), card: Color(white: 0.155), chip: Color(white: 0.2),
                                selected: Color(white: 0.31), line: Color(white: 0.22))
    static let ocean = Theme(id: "ocean", name: "Ocean",
                             island: rgb(0x07101F), card: rgb(0x0F1B30), chip: rgb(0x16253F),
                             selected: rgb(0x26395C), line: rgb(0x1B2B47))
    static let forest = Theme(id: "forest", name: "Forest",
                              island: rgb(0x07130D), card: rgb(0x0E2018), chip: rgb(0x152B20),
                              selected: rgb(0x234333), line: rgb(0x1A3326))
    static let plum = Theme(id: "plum", name: "Plum",
                            island: rgb(0x120A1A), card: rgb(0x1D1229), chip: rgb(0x261836),
                            selected: rgb(0x3B2752), line: rgb(0x2C1D3D))
    static let espresso = Theme(id: "espresso", name: "Espresso",
                                island: rgb(0x140E0A), card: rgb(0x211812), chip: rgb(0x2B2018),
                                selected: rgb(0x433326), line: rgb(0x33261C))

    static let all = [midnight, graphite, ocean, forest, plum, espresso]

    static func glass(over base: Theme, transparency: Double = 0.25) -> Theme {
        let c = base.glassColor
        return Theme(id: "glass." + base.id, name: base.name, island: base.glassTint(transparency: transparency),
                     card: c.opacity(0.06), chip: c.opacity(0.11), selected: c.opacity(0.22), line: c.opacity(0.13))
    }

    var glassColor: Color {
        switch id {
        case "graphite": return Color(white: 0.85)
        case "ocean": return rgb(0x6FA0FF)
        case "forest": return rgb(0x5FD394)
        case "plum": return rgb(0xB98AF0)
        case "espresso": return rgb(0xE0A877)
        default: return .white
        }
    }

    func glassTint(transparency: Double) -> Color {
        let a = 1 - min(max(transparency, 0.1), 0.9)
        switch id {
        case "graphite": return Color(white: 0.42).opacity(a)
        case "ocean": return rgb(0x1F5FD1).opacity(a)
        case "forest": return rgb(0x1E8A55).opacity(a)
        case "plum": return rgb(0x7A3FC0).opacity(a)
        case "espresso": return rgb(0x8A5A30).opacity(a)
        default: return Color.black.opacity(a)
        }
    }

    static func byID(_ id: String) -> Theme { all.first { $0.id == id } ?? midnight }
}

struct TrendPalette: Identifiable, Equatable {
    let id: String
    let name: String
    let red: Color
    let green: Color

    static let classic = TrendPalette(id: "classic", name: "Red & green",
                                      red: Color(red: 1.0, green: 0.41, blue: 0.38),
                                      green: Color(red: 0.19, green: 0.82, blue: 0.35))
    static let colorblind = TrendPalette(id: "colorblind", name: "Orange & blue",
                                         red: Color(red: 1.0, green: 0.62, blue: 0.04),
                                         green: Color(red: 0.25, green: 0.6, blue: 1.0))
    static let soft = TrendPalette(id: "soft", name: "Pastel",
                                   red: Color(red: 0.96, green: 0.6, blue: 0.62),
                                   green: Color(red: 0.55, green: 0.86, blue: 0.68))

    static let all = [classic, colorblind, soft]
    static func byID(_ id: String) -> TrendPalette { all.first { $0.id == id } ?? classic }
}

enum Accent: String, CaseIterable, Identifiable {
    case green, blue, purple, orange, pink, yellow
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .green: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .blue: return Color(red: 0.04, green: 0.52, blue: 1.0)
        case .purple: return Color(red: 0.75, green: 0.35, blue: 0.95)
        case .orange: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .pink: return Color(red: 1.0, green: 0.22, blue: 0.37)
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.04)
        }
    }
}

enum Corners: String, CaseIterable, Identifiable {
    case round = "Round", soft = "Soft", tight = "Tight"
    var id: String { rawValue }
    var island: CGFloat {
        switch self {
        case .round: return 34
        case .soft: return 24
        case .tight: return 14
        }
    }
    var card: CGFloat {
        switch self {
        case .round: return 20
        case .soft: return 14
        case .tight: return 8
        }
    }
}

struct Look: Equatable {
    var theme: Theme = .midnight
    var glass = false
    var trend: TrendPalette = .classic
    var accent: Color = Accent.green.color
    var corners: Corners = .round
}

private struct LookKey: EnvironmentKey {
    static let defaultValue = Look()
}

extension EnvironmentValues {
    var look: Look {
        get { self[LookKey.self] }
        set { self[LookKey.self] = newValue }
    }
}

private func rgb(_ hex: Int) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255)
}

enum MotionStyle: String, CaseIterable, Identifiable {
    case smooth = "Smooth", bouncy = "Bouncy", snappy = "Snappy", off = "Off"
    var id: String { rawValue }
}

enum MotionSpeed: String, CaseIterable, Identifiable {
    case slow = "Slow", normal = "Normal", fast = "Fast"
    var id: String { rawValue }
    var factor: Double {
        switch self {
        case .slow: return 1.45
        case .normal: return 1
        case .fast: return 0.65
        }
    }
}

struct Motion: Equatable {
    var style: MotionStyle = .smooth
    var speed: MotionSpeed = .normal
    var animateCharts = true

    var enabled: Bool { style != .off }

    var island: Animation? {
        let k = speed.factor
        switch style {
        case .smooth: return .smooth(duration: 0.52 * k, extraBounce: 0.02)
        case .bouncy: return .spring(response: 0.55 * k, dampingFraction: 0.7)
        case .snappy: return .spring(response: 0.3 * k, dampingFraction: 0.86)
        case .off: return nil
        }
    }

    var close: Animation? {
        let k = speed.factor
        switch style {
        case .smooth: return .smooth(duration: 0.44 * k)
        case .bouncy: return .spring(response: 0.46 * k, dampingFraction: 0.9)
        case .snappy: return .spring(response: 0.28 * k, dampingFraction: 1)
        case .off: return nil
        }
    }

    var contentIn: Animation? {
        enabled ? .smooth(duration: 0.32 * speed.factor).delay(0.07 * speed.factor) : nil
    }
    var contentOut: Animation? {
        enabled ? .easeOut(duration: 0.14 * speed.factor) : nil
    }

    var small: Animation? {
        enabled ? .smooth(duration: 0.24 * speed.factor) : nil
    }

    var page: Animation? {
        enabled ? .smooth(duration: 0.34 * speed.factor) : nil
    }

    var chartReveal: Animation? {
        enabled && animateCharts ? .easeOut(duration: 0.7 * speed.factor) : nil
    }
}

private struct MotionKey: EnvironmentKey {
    static let defaultValue = Motion()
}

extension EnvironmentValues {
    var motion: Motion {
        get { self[MotionKey.self] }
        set { self[MotionKey.self] = newValue }
    }
}

struct GlassBackground<S: Shape>: View {
    let shape: S
    let tint: Color

    var body: some View {
        ZStack {
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
            shape.fill(tint)
        }
        .environment(\.colorScheme, .dark)
    }
}

struct CardBackground<S: InsettableShape>: View {
    @Environment(\.look) private var look
    let shape: S
    let fill: Color

    var body: some View {
        shape.fill(fill)
            .overlay {
                if look.glass {
                    shape.strokeBorder(LinearGradient(colors: [.clear, .clear, .white.opacity(0.10), .white.opacity(0.22)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(look.glass ? 0.32 : 0), radius: look.glass ? 12 : 0, y: look.glass ? 6 : 0)
    }
}

extension Look {
    func pnl(_ v: Double) -> Color { v >= 0 ? trend.green : trend.red }
    func pnl(up: Bool) -> Color { up ? trend.green : trend.red }
}
