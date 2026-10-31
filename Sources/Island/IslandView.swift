import SwiftUI

enum IslandMode: Equatable {
    case collapsed
    case home
    case detail(String)
    case settings
    case assistant
    case teardown
    case journal
    case wallet
    case longTerm
    case trade
    case friends
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case profile = "Profile"
    case currencies = "Currencies", portfolio = "Portfolio", assistant = "Trading", chart = "Chart"
    case widget = "Widget", themes = "Themes", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .profile: return "person.crop.circle"
        case .currencies: return "dollarsign.circle"
        case .chart: return "chart.xyaxis.line"
        case .widget: return "square.grid.2x2"
        case .assistant: return "chart.line.uptrend.xyaxis"
        case .portfolio: return "briefcase"
        case .themes: return "paintpalette"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .collapsed {
        willSet {
            previous = mode
            forward = Self.order(newValue) >= Self.order(mode)
            slides = mode != .collapsed && newValue != .collapsed
        }
        didSet { if mode == .collapsed { endEditing() } }
    }
    private(set) var forward = true
    private(set) var slides = false
    private(set) var previous: IslandMode = .collapsed

    private static func order(_ m: IslandMode) -> Int {
        if let t = IslandTab.of(m), let i = IslandTab.visible.firstIndex(of: t) { return i }
        return m == .collapsed ? -1 : IslandTab.visible.count
    }
    let assistantReorder = ReorderModel()
    @Published var journalEditing = false

    func endEditing() {
        assistantReorder.editing = false
        journalEditing = false
    }
    @Published var visible = false
    @Published var notchW: CGFloat = 0
    @Published var notchH: CGFloat = 32
    @Published var settingsTab: SettingsTab = .currencies
    @Published var probDetail: String?
    @Published var pinned = false
    var detached = false
    var onDetach: (@MainActor () -> Void)?
    var onAttach: (@MainActor () -> Void)?
    var onWithdrawConsent: (@MainActor () -> Void)?
    var onReplayOnboarding: (@MainActor () -> Void)?

    @discardableResult
    func openSubject(itemID: String, settings: AppSettings) -> Bool {
        guard let s = HubSubject.match(itemID: itemID, settings) else { return false }
        probDetail = s.id
        mode = .assistant
        return true
    }

    var returnMode: IslandMode = .home

    func openSettings(_ tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        if mode != .settings && mode != .collapsed { returnMode = mode }
        mode = .settings
    }

    func closeSettings() { mode = returnMode }
}

@MainActor
struct IslandView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var journal: JournalStore
    @ObservedObject var probability: ProbabilityStore
    @ObservedObject private var desk = TradeDesk.shared
    @ObservedObject private var calendar = MarketCalendar.shared
    @ObservedObject private var idlePrefs = IdlePrefs.shared
    @StateObject private var ghost = DragGhost()
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        let mode = state.mode
        let look = settings.look
        let motion = settings.motion
        var size = Layout.size(for: mode, notchW: state.notchW, notchH: state.notchH)
        let _ = state.detached ? (size.height += Layout.detachedBottom) : ()
        let r: CGFloat = mode == .collapsed ? min(18, look.corners.island) : look.corners.island
        let top: CGFloat = state.detached ? r : 0
        let shape = UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: top, bottomLeading: r, bottomTrailing: r, topTrailing: top))

        let homeW = state.notchW > 0 ? state.notchW : Layout.pillW
        let hiddenX = min(homeW / max(size.width, 1), 1)
        let hiddenY = min(max(state.notchH, 1) / max(size.height, 1), 1)
        let glassMorph = look.glass && state.notchW > 0
        let drawn = glassMorph && !state.visible ? CGSize(width: min(homeW, size.width), height: max(state.notchH, 1)) : size

        ZStack(alignment: .top) {
            if look.glass {
                GlassBackground(shape: shape, tint: look.theme.island)
                shape.stroke(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0.08), .white.opacity(0.2)],
                                            startPoint: .bottomLeading, endPoint: .topTrailing), lineWidth: 1.5)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.3),
                                                 .init(color: .black, location: 0.75)],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(!state.visible ? 0 : mode == .collapsed ? 0.6 : 1)
            } else {
                shape.fill(look.theme.island)
                shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.05), location: 0),
                                                  .init(color: .clear, location: 0.45),
                                                  .init(color: .black.opacity(0.12), location: 1)],
                                          startPoint: .top, endPoint: .bottom))
            }
            if !look.glass && look.theme.id != Theme.midnight.id {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: 0.38),
                                       .init(color: .black.opacity(0.75), location: 0.55),
                                       .init(color: .black.opacity(0.4), location: 0.72),
                                       .init(color: .black.opacity(0.14), location: 0.87),
                                       .init(color: .black.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: state.notchH + 60)
                    .allowsHitTesting(false)
            }
            content(size: size)
                .padding(.top, state.notchH)
                .padding(.bottom, state.detached ? Layout.detachedBottom : 0)
                .frame(width: size.width, height: size.height, alignment: .top)
                .overlay(alignment: .topLeading) { DragGhostLayer(ghost: ghost) }
                .coordinateSpace(name: DragGhost.space)
                .id(settings.language)
                .environment(\.dragGhost, ghost)
                .opacity(state.visible ? 1 : 0)
                .animation(contentFade(motion), value: state.visible)
            if state.detached {
                WindowDragArea().frame(height: state.notchH).frame(maxWidth: .infinity)
            }
        }
        .frame(width: drawn.width, height: drawn.height, alignment: .top)
        .clipShape(shape)
        .contentShape(shape)
        .scaleEffect(x: state.visible || glassMorph ? 1 : hiddenX, y: state.visible || glassMorph ? 1 : hiddenY, anchor: .top)
        .opacity(state.visible || glassMorph ? 1 : 0)
        .frame(width: state.detached ? size.width : Layout.panelW, height: state.detached ? size.height : Layout.panelH, alignment: .top)
        .animation(motion.island, value: state.mode)
        .animation(motion.island, value: size)
        .foregroundStyle(.white)
        .environment(\.look, look)
        .environment(\.motion, motion)
    }

    private func contentFade(_ motion: Motion) -> Animation? {
        guard motion.enabled else { return nil }
        let k = motion.speed.factor
        return state.visible
            ? .easeOut(duration: 0.24 * k).delay(0.1 * k)
            : .easeIn(duration: 0.12 * k)
    }

    private func stageTransition(_ motion: Motion) -> AnyTransition {
        guard state.slides else {
            return .asymmetric(insertion: .opacity.animation(motion.contentIn), removal: .opacity.animation(motion.contentOut))
        }
        return .asymmetric(
            insertion: .move(edge: state.forward ? .trailing : .leading).animation(motion.page),
            removal: .move(edge: state.forward ? .leading : .trailing).animation(motion.page))
    }

    @ViewBuilder
    private func content(size: CGSize) -> some View {
        let t = stageTransition(settings.motion)
        if let tab = IslandTab.of(state.mode) {
            pager(tab)
                .transition(t)
        } else {
        switch state.mode {
        case .collapsed:
            CollapsedView(rates: rates, settings: settings)
                .frame(width: size.width, height: Layout.dropH)
                .contentShape(Rectangle())
                .onTapGesture { state.mode = desk.hasTrade || desk.pendingTag != nil ? .trade : settings.lastTab.mode }
                .onHover { inside in
                    hoverTask?.cancel()
                    guard inside, desk.hasTrade else { return }
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        if !Task.isCancelled, state.mode == .collapsed { state.mode = .trade }
                    }
                }
                .contextMenu {
                    Button(tr("New trade…")) { state.mode = .trade }
                    Button(tr("Paper trading")) {
                        UserDefaults.standard.set("Paper", forKey: "journalPage")
                        settings.lastTab = .journal
                        state.mode = .journal
                    }
                }
                .transition(t)
        case .trade:
            TradeDeskView(state: state, settings: settings)
                .transition(t)
        case .wallet:
            WalletView(state: state, rates: rates, settings: settings)
                .transition(t)
        case .detail(let id):
            DetailView(asset: settings.asset(id: id), state: state, rates: rates, settings: settings)
                .id(id + settings.baseCurrency)
                .transition(t)
        case .settings:
            SettingsView(state: state, rates: rates, settings: settings)
                .transition(t)
        case .teardown:
            EmptyView()
        default:
            EmptyView()
        }
        }
    }

    @ViewBuilder
    private func page(_ t: IslandTab) -> some View {
        switch t {
        case .home: HomeView(state: state, rates: rates, settings: settings)
        case .assistant: ProbabilityView(state: state, store: probability, journal: journal, settings: settings)
        case .longTerm: LongTermView(state: state, rates: rates, settings: settings)
        case .journal: JournalView(state: state, journal: journal, probability: probability, settings: settings)
        case .friends: FriendsView(state: state, settings: settings)
        }
    }

    private func pager(_ current: IslandTab) -> some View {
        let tabs = IslandTab.visible
        let i = tabs.firstIndex(of: current) ?? 0
        let from = IslandTab.of(state.previous).flatMap { tabs.firstIndex(of: $0) }
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                IslandTabBar(state: state, settings: settings)
                Spacer(minLength: 8)
                ProfileButton(state: state)
            }
            .frame(height: 34)
            .padding(.horizontal, Layout.gutter)
            .padding(.vertical, 12)
            .zIndex(1)
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element) { j, t in
                    Group {
                        if abs(j - i) <= 1 || j == from { page(t).environment(\.pageActive, j == i) } else { Color.clear }
                    }
                    .frame(width: Layout.pageW, height: Layout.bodyH, alignment: .top)
                }
            }
            .fixedSize()
            .offset(x: -CGFloat(i) * Layout.pageW)
            .animation(settings.motion.page, value: i)
            .frame(width: Layout.pageW, height: Layout.bodyH, alignment: .leading)
            .clipped()
            .overlay {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

@MainActor
struct CollapsedView: View {
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var desk = TradeDesk.shared
    @ObservedObject private var journal = JournalStore.shared
    @ObservedObject private var idlePrefs = IdlePrefs.shared
    @ObservedObject private var calendar = MarketCalendar.shared

    static let rotateEvery: TimeInterval = 8

    var body: some View {
        Group {
            if desk.hasTrade {
                CollapsedTradeView(paper: .shared, desk: desk, settings: settings)
            } else if let t = desk.toast {
                HStack(spacing: 6) {
                    Image(systemName: t.symbol).font(.system(size: 11))
                    Text(t.text)
                }
                .id(t.id)
                .transition(.opacity)
            } else if let e = journal.entry(desk.pendingTag) {
                HStack(spacing: 6) {
                    ModeLabel(entry: e, size: 8.5)
                    Text(e.asset)
                    if let r = e.rMultiple { Text(TradeFormat.r(r)).foregroundStyle(TradeColors.pnl(r)) }
                    Text(tr("tap to tag")).foregroundStyle(.white.opacity(0.55)).fontWeight(.medium)
                }
            } else if let e = MarketCalendar.shared.soon {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.system(size: 11))
                    TimelineView(.periodic(from: .now, by: 1)) { c in
                        Text(MarketCalendar.title(e) + " · " + MarketCalendar.countdown(e.at, now: c.date))
                    }
                }
            } else if idlePrefs.v.tape && settings.motion.enabled {
                TickerTape(rates: rates, settings: settings)
            } else {
                idle
            }
        }
        .font(.system(size: 12.5, weight: .bold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .animation(settings.motion.enabled ? .easeOut(duration: 0.25) : nil, value: desk.toast)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("Opens FinanceIsland"))
    }

    private var rotation: [Asset] {
        guard let first = settings.pillAsset else { return [] }
        let rest = settings.assets.filter { $0.id != first.id && rates.quote($0) != nil }
        return [first] + rest.prefix(2)
    }

    @ViewBuilder
    private var idle: some View {
        let list = rotation
        if list.isEmpty {
            Image(systemName: "chart.line.uptrend.xyaxis")
        } else {
            TimelineView(.periodic(from: .now, by: Self.rotateEvery)) { c in
                let a = list[Int(c.date.timeIntervalSince1970 / Self.rotateEvery) % list.count]
                if let q = rates.quote(a) {
                    HStack(spacing: 5) {
                        Text(tr("\(a.code) ") + Fmt.price(q.price, a))
                            .contentTransition(.numericText(value: q.price))
                        Text((q.isUp ? "▲" : "▼") + String(format: "%.1f", abs(q.pct)) + "%")
                            .foregroundStyle(settings.color(a, up: q.isUp))
                            .accessibilityLabel((q.isUp ? tr("up") : tr("down")) + " " + String(format: "%.1f", abs(q.pct)) + "%")
                    }
                    .id(a.id)
                    .transition(.opacity)
                    .animation(settings.motion.enabled ? .easeInOut(duration: 0.6) : nil, value: a.id)
                } else {
                    Text(rates.failed ? tr("Connection error") : tr("Loading…"))
                }
            }
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}
