import SwiftUI

@MainActor
struct CircleIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.look) private var look
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(hover ? look.theme.selected : look.theme.chip))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .accessibilityLabel(label)
    }
}

@MainActor
struct EthGlyph: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.17))
            Image(systemName: "diamond")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.8))
        }
        .frame(width: 26, height: 26)
    }
}

@MainActor
struct Sparkline: View {
    let values: [Double]
    let color: Color
    let style: ChartStyle

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points(values, in: geo.size)
            ZStack {
                if values.count < 2 {
                    EmptyView()
                } else {
                    switch style {
                    case .bars:
                        Bars(values: values, size: geo.size, color: color)
                    case .area:
                        Self.area(pts, height: geo.size.height, stepped: false)
                            .fill(LinearGradient(colors: [color.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
                        Self.line(pts, stepped: false)
                            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    case .line, .step:
                        Self.line(pts, stepped: style == .step)
                            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let flat = hi - lo <= max(abs(hi), 1e-12) * 1e-7
        let span = max(hi - lo, 0.000001)
        return values.enumerated().map { i, v in
            CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                    y: flat ? size.height / 2 : 4 + (size.height - 8) * (1 - CGFloat((v - lo) / span)))
        }
    }

    static func line(_ pts: [CGPoint], stepped: Bool) -> Path {
        Path { p in
            guard let first = pts.first else { return }
            p.move(to: first)
            var prev = first
            for pt in pts.dropFirst() {
                if stepped { p.addLine(to: CGPoint(x: pt.x, y: prev.y)) }
                p.addLine(to: pt)
                prev = pt
            }
        }
    }

    static func area(_ pts: [CGPoint], height: CGFloat, stepped: Bool) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: height))
            p.addLine(to: first)
            var prev = first
            for pt in pts.dropFirst() {
                if stepped { p.addLine(to: CGPoint(x: pt.x, y: prev.y)) }
                p.addLine(to: pt)
                prev = pt
            }
            p.addLine(to: CGPoint(x: last.x, y: height))
            p.closeSubpath()
        }
    }
}

@MainActor
private struct Bars: View {
    let values: [Double]
    let size: CGSize
    let color: Color

    var body: some View {
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = max(hi - lo, 0.000001)
        let n = max(values.count, 1)
        let slot = size.width / CGFloat(n)
        let w = max(slot * 0.65, 1)
        Path { p in
            for (i, v) in values.enumerated() {
                let h = 3 + (size.height - 6) * CGFloat((v - lo) / span)
                p.addRoundedRect(in: CGRect(x: CGFloat(i) * slot + (slot - w) / 2,
                                            y: size.height - h, width: w, height: h),
                                 cornerSize: CGSize(width: min(w / 2, 2), height: min(w / 2, 2)))
            }
        }
        .fill(color.opacity(0.85))
    }
}

@MainActor
struct LineChart: View {
    let values: [Double]
    let color: Color
    let style: ChartStyle
    var showGrid = true
    var showPoints = true
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @State private var reveal: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let pts = Sparkline.points(values, in: geo.size)
            ZStack {
                if showGrid {
                    ForEach(1..<4) { i in
                        Path { p in
                            let y = geo.size.height * CGFloat(i) / 4
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(look.theme.line, lineWidth: 1)
                    }
                }
                ZStack {
                    Sparkline(values: values, color: color, style: style)
                    if showPoints && style != .bars {
                        let step = max(pts.count / 8, 1)
                        ForEach(Array(stride(from: 0, to: max(pts.count - 1, 0), by: step)), id: \.self) { i in
                            Circle()
                                .fill(look.theme.card)
                                .overlay(Circle().stroke(color, lineWidth: 1.5))
                                .frame(width: 6, height: 6)
                                .position(pts[i])
                        }
                    }
                    if let last = pts.last, style != .bars {
                        Circle()
                            .fill(color)
                            .frame(width: 9, height: 9)
                            .position(last)
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(geo.size.width * reveal + 6, 0))
                }
            }
        }
        .onAppear { replay() }
        .onChange(of: values) { _, _ in replay() }
    }

    private func replay() {
        guard let anim = motion.chartReveal, values.count > 1 else { reveal = 1; return }
        reveal = 0
        DispatchQueue.main.async { withAnimation(anim) { reveal = 1 } }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}

@MainActor
struct PillPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    var minWidth: CGFloat = 40
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                Button { selection = o } label: {
                    Text(tr(label(o)))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(minWidth: minWidth, minHeight: 28)
                        .background {
                            if selection == o {
                                Capsule().fill(look.theme.selected).matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .foregroundStyle(.white.opacity(selection == o ? 1 : 0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(look.theme.chip))
        .animation(motion.enabled ? .spring(response: 0.3 * motion.speed.factor, dampingFraction: 0.85) : nil,
                   value: selection)
    }
}

@MainActor
struct AppLogo: View {
    var size: CGFloat = 56
    var color: Color = Accent.green.color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.286, style: .continuous).fill(Color.black)
            RoundedRectangle(cornerRadius: size * 0.286, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: max(size / 56, 0.5))
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }
}

enum IslandTab: String, CaseIterable, Identifiable {
    case home = "Home", assistant = "Scalping", longTerm = "Portfolio", journal = "Trade"
    case friends = "Friends"
    var id: String { rawValue }

    static var visible: [IslandTab] { allCases }

    static var signalsOn: Bool {
        false
    }

    var title: String { self == .assistant && !Self.signalsOn ? "Markets" : rawValue }

    static func of(_ mode: IslandMode) -> IslandTab? {
        visible.first { $0.mode == mode }
    }

    var hint: String {
        let n = (Self.visible.firstIndex(of: self) ?? 0) + 1
        return tr(title) + " · ⌘" + String(n)
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .assistant: return Self.signalsOn ? "bolt.fill" : "chart.bar.xaxis"
        case .longTerm: return "briefcase"
        case .journal: return "book.pages"
        case .friends: return "person.2"
        }
    }
    var mode: IslandMode {
        switch self {
        case .home: return .home
        case .assistant: return .assistant
        case .longTerm: return .longTerm
        case .journal: return .journal
        case .friends: return .friends
        }
    }
}

@MainActor
struct IslandTabBar: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 10) {
            AppLogo(size: 30, color: look.accent)
            if IslandTab.visible.count > 1 {
            HStack(spacing: 2) {
                ForEach(IslandTab.visible) { t in
                    let on = current == t
                    Button { select(t) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: t.symbol)
                                .font(.system(size: on ? 12.5 : 13, weight: on ? .semibold : .regular))
                            if on {
                                Text(tr(t.title))
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                            }
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, on ? 12 : 10)
                        .frame(height: 28)
                        .background {
                            if on { Capsule().fill(look.theme.selected).matchedGeometryEffect(id: "tab", in: ns) }
                        }
                        .foregroundStyle(.white.opacity(on ? 1 : 0.45))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(t.hint)
                    .accessibilityLabel(tr(t.title))
                }
            }
            .padding(3)
            .background(Capsule().fill(look.theme.chip))
            .animation(motion.enabled ? .spring(response: 0.3 * motion.speed.factor, dampingFraction: 0.86) : nil,
                       value: current)
            }
            WindowControls(state: state)
        }
    }

    private var current: IslandTab {
        switch state.mode {
        case .assistant, .teardown: return .assistant
        case .journal: return .journal
        case .longTerm: return .longTerm
        case .friends: return .friends
        default: return .home
        }
    }

    private func select(_ t: IslandTab) {
        settings.lastTab = t
        if t == .assistant && state.mode == .assistant && state.probDetail != nil {
            withAnimation(motion.page) { state.probDetail = nil }
            return
        }
        state.mode = t.mode
    }
}

enum RenderFlags {
    nonisolated(unsafe) static var noScroll = false
}

@MainActor
struct PageScroll<Content: View>: View {
    var showsIndicators = false
    var fadesBottom = true
    @ViewBuilder let content: Content
    @State private var scrolled = false

    var body: some View {
        if RenderFlags.noScroll {
            content
        } else {
            ScrollView(.vertical, showsIndicators: showsIndicators) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0)
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .named("pageScroll")).minY < -2 } action: { scrolled = $0 }
                    content
                }
            }
            .coordinateSpace(name: "pageScroll")
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(scrolled ? 0 : 1), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 26)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(fadesBottom ? 0 : 1)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                }
                .animation(.easeOut(duration: 0.2), value: scrolled)
            }
        }
    }
}

@MainActor
struct EditDoneButton: View {
    @Binding var editing: Bool
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @State private var hover = false

    var body: some View {
        Button { withAnimation(motion.small) { editing.toggle() } } label: {
            Image(systemName: editing ? "checkmark" : "pencil")
                .font(.system(size: 13, weight: editing ? .bold : .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(editing ? look.accent : (hover ? look.theme.selected : look.theme.chip)))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .help(tr(editing ? "Finish editing" : "Reorder and remove items"))
        .accessibilityLabel(tr(editing ? "Done" : "Edit"))
    }
}

@MainActor
final class PointerTracker: ObservableObject {
    static let shared = PointerTracker()
    @Published var point: CGPoint?
}

extension View {
    func islandHover(_ action: @escaping (CGPoint?) -> Void) -> some View {
        modifier(IslandHover(action: action))
    }
}

private struct IslandHover: ViewModifier {
    let action: (CGPoint?) -> Void
    @State private var frame = FrameBox()
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.rect = $0 }
            .onReceive(PointerTracker.shared.$point) { p in
                let frame = self.frame.rect
                guard let p, frame.contains(p) else {
                    if inside { inside = false; action(nil) }
                    return
                }
                inside = true
                action(CGPoint(x: p.x - frame.minX, y: p.y - frame.minY))
            }
    }
}

struct WindowControls: View {
    @ObservedObject var state: IslandState
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 0) {
            if !state.detached {
                control(state.pinned ? "pin.fill" : "pin", state.pinned ? "Unpin from the notch" : "Pin open at the notch",
                        on: state.pinned) { state.pinned.toggle() }
            }
            control(state.detached ? "rectangle.inset.topleft.filled" : "macwindow.on.rectangle",
                    state.detached ? "Back to the notch" : "Open in a window", on: false) {
                if state.detached { state.onAttach?() } else { state.onDetach?() }
            }
        }
    }

    private func control(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(on ? look.accent : .white.opacity(0.4))
                .frame(width: 24, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverLift()
        .help(tr(label))
        .accessibilityLabel(tr(label))
    }
}

private struct HoverLift: ViewModifier {
    @Environment(\.motion) private var motion
    @State private var over = false
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(over ? scale : 1)
            .animation(motion.enabled ? .spring(response: 0.25, dampingFraction: 0.7) : nil, value: over)
            .onHover { over = $0 }
    }
}

extension View {
    func hoverLift(_ scale: CGFloat = 1.04) -> some View { modifier(HoverLift(scale: scale)) }
}

struct RowHover: ViewModifier {
    var radius: CGFloat = 10
    var fill = 0.06
    var stroke = 0.0
    var chevron = false
    var editing = false
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(on ? fill : 0)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(on ? stroke : 0), lineWidth: 1))
            .overlay(alignment: .trailing) {
                if chevron && on && !editing {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                        .padding(.trailing, 14).allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(perform: track)
    }

    private func track(_ phase: HoverPhase) {
        switch phase {
        case .active:
            if !on { on = true }
            (editing ? NSCursor.openHand : NSCursor.pointingHand).set()
        case .ended:
            on = false
            NSCursor.arrow.set()
        }
    }
}

struct PageTitle: View {
    let tab: IslandTab

    var body: some View {
        Text(tr(tab.title)).font(.system(size: 17, weight: .bold)).lineLimit(1)
    }
}

private struct PageActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var pageActive: Bool {
        get { self[PageActiveKey.self] }
        set { self[PageActiveKey.self] = newValue }
    }
}

struct FooterNote: View {
    let text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(text).multilineTextAlignment(.center)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.white.opacity(0.4))
        .lineLimit(2)
        .minimumScaleFactor(0.85)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct UndoBar: View {
    let text: String
    let since: Date
    let undo: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = Int(ceil(10 - ctx.date.timeIntervalSince(since)))
            if left > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "trash").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    Text(tr(text)).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(left)s").font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                    Button(tr("Undo"), action: undo)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(look.accent)
                }
                .padding(.horizontal, 14).frame(height: 34)
                .background(Capsule().fill(look.theme.chip))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}
