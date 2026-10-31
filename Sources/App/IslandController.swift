import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class ClickHostingView<Content: View>: NSHostingView<Content> {
    private var alwaysTracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if alwaysTracking == nil {
            let area = NSTrackingArea(rect: .zero,
                                      options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            alwaysTracking = area
        }
    }
}

@MainActor
final class IslandController {
    private let state = IslandState()
    private let settings: AppSettings
    private let rates: RateStore
    private let journal = JournalStore.shared
    private let probability = ProbabilityStore()
    private let onboarding = OnboardingWindow()
    private var subs: Set<AnyCancellable> = []
    private var panel: IslandPanel!
    private var notch = currentNotch()
    private var statusItem: NSStatusItem?
    private var monitors: [Any] = []
    private var swipeX: CGFloat = 0
    private var swipeDone = false

    private var shown = false
    private var activity: NSObjectProtocol?
    private var hideTimer: Timer?
    private var openTimer: Timer?
    private let hint = NotchHint()
    private var detachedWindow: DetachedIsland?
    private var enabled: Bool { settings.hasAcceptedTerms && detachedWindow == nil && !settings.menuBarMode }

    init() {
        settings = AppSettings()
        rates = RateStore(settings: settings)
    }

    func start() {
        panel = IslandPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let host = ClickHostingView(rootView: IslandView(state: state, rates: rates, settings: settings,
                                                         journal: journal,
                                                         probability: probability))
        host.sizingOptions = []
        panel.contentView = host

        place()
        installMonitors()
        rates.start()
        AlertStore.shared.start()
        TradeDesk.shared.start(settings: settings, rates: rates)
        PortfolioPulse.shared.start(settings: settings, rates: rates)
        MarketCalendar.shared.start()
        MacroStore.shared.start()
        WalletPerps.shared.start()
        _ = PowerState.shared

        state.$mode.sink { [weak self] mode in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.modeChanged(mode) }
            }
        }
        .store(in: &subs)
        settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.shown else { return }
                    self.updateHitTesting(NSEvent.mouseLocation)
                }
            }
        }
        .store(in: &subs)
        settings.$islandScreen.combineLatest(settings.$menuBarMode).dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.place(); self?.updateStatusItem(); self?.offerHint() } }
        }
        .store(in: &subs)
        updateStatusItem()
        TradeDesk.shared.$menuTitle.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateStatusTitle() } }
        }
        .store(in: &subs)
        Timer.publish(every: 20, on: .main, in: .common).autoconnect()
            .merge(with: IdlePrefs.shared.$v.map { _ in Date() }.eraseToAnyPublisher())
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.updateStatusTitle() } }
            }
            .store(in: &subs)
        TradeDesk.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.shown else { return }
                    self.updateHitTesting(NSEvent.mouseLocation)
                }
            }
        }
        .store(in: &subs)
        TradeDesk.shared.$attention.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.flash() } }
        }
        .store(in: &subs)
        TradeDesk.shared.$hotkeysActive.sink { [weak self] on in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, on, self.shown, self.panel.allowsKey else { return }
                    self.panel.makeKey()
                }
            }
        }
        .store(in: &subs)

        state.onWithdrawConsent = { [weak self] in self?.withdrawConsent() }
        state.onDetach = { [weak self] in self?.detach() }
        state.onReplayOnboarding = { [weak self] in
            guard let self else { return }
            self.settings.notchHintDone = false
            self.settings.hintScreens = []
            self.hint.close()
            self.onboarding.show(settings: self.settings, rates: self.rates)
        }
        onboarding.onFinished = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated { self?.offerHint() } }
        }

        if !settings.hasAcceptedTerms || !settings.onboarded { onboarding.show(settings: settings, rates: rates) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated { self.offerHint() } } }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.place()
                if self.shown || (self.settings.look.glass && self.notch.width > 0) { self.panel.orderFrontRegardless() }
            }
        }
    }

    private func detach() {
        guard detachedWindow == nil else { return }
        let mode = state.mode
        state.pinned = false
        hide()
        let w = DetachedIsland(mode: mode, settings: settings, rates: rates,
                               journal: journal, probability: probability)
        w.onClose = { [weak self] in
            self?.detachedWindow = nil
        }
        detachedWindow = w
    }

    private func withdrawConsent() {
        hide()
        settings.eraseAll()
        rates.reset()
        journal.eraseAll()
        PortfolioStore.shared.eraseAll()
        LongTermStore.shared.eraseAll()
        probability.eraseAll()
        DataVault.deleteBackups()
        LicenseStore.shared.remove()
        NewsStore.shared.eraseAll()
        AlertStore.shared.eraseAll()
        TradeDesk.shared.eraseAll()
        IdlePrefs.shared.reset()
        HolderPrefs.shared.reset()
        onboarding.show(settings: settings, rates: rates)
    }

    private func modeChanged(_ mode: IslandMode) {
        let typing = mode == .settings || mode == .assistant || mode == .journal || mode == .longTerm || mode == .trade
        panel.allowsKey = true
        if !typing && panel.isKeyWindow { panel.makeFirstResponder(nil) }
        guard shown else { return }
        updateHitTesting(NSEvent.mouseLocation)
    }

    private func updateStatusItem() {
        if settings.menuBarMode, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "FinanceIsland")
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            statusItem = item
            updateStatusTitle()
        } else if !settings.menuBarMode, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func updateStatusTitle() {
        guard let item = statusItem else { return }
        let t = MenuBarPins.title(settings: settings, rates: rates)
        item.length = t.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
        item.button?.title = t.isEmpty ? "" : " " + t
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        item.button?.imagePosition = t.isEmpty ? .imageOnly : .imageLeading
    }

    @objc private func statusItemClicked() {
        if hint.isShown { hint.dismiss() }
        if let w = detachedWindow { w.close(); return }
        guard settings.hasAcceptedTerms, let button = statusItem?.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let w = DetachedIsland(mode: settings.lastTab.mode, settings: settings, rates: rates,
                               journal: journal, probability: probability, below: anchor)
        w.onClose = { [weak self] in self?.detachedWindow = nil }
        detachedWindow = w
    }

    private func offerHint() {
        guard settings.hasAcceptedTerms, settings.onboarded, !settings.notchHintDone, !shown, detachedWindow == nil else { return }
        if settings.menuBarMode {
            guard let button = statusItem?.button else { return }
            hint.showMenuBar(at: button) { [weak self] in self?.settings.notchHintDone = true }
            return
        }
        let id = displayID(notch.screen)
        hint.show(kind: notch.width > 0 ? .notch : .virtual, below: notch, settings: settings) { [weak self] in
            self?.settings.notchHintDone = true
        }
        if !settings.hintScreens.contains(id) { settings.hintScreens.append(id) }
    }

    private func offerScreenHint() {
        guard settings.notchHintDone, !settings.menuBarMode, settings.islandScreen == "cursor", notch.width == 0, !shown else { return }
        let id = displayID(notch.screen)
        guard !settings.hintScreens.contains(id) else { return }
        settings.hintScreens.append(id)
        hint.show(kind: .virtual, below: notch, settings: settings) {}
    }

    private func place() {
        let previous = displayID(notch.screen)
        notch = currentNotch(settings.islandScreen)
        state.notchW = notch.width
        state.notchH = notch.height
        let f = notch.screen.frame
        panel.setFrame(NSRect(x: f.midX - Layout.panelW / 2,
                              y: f.maxY - Layout.panelH,
                              width: Layout.panelW,
                              height: Layout.panelH),
                       display: true)
        if !enabled { hide() }
        if displayID(notch.screen) != previous {
            if !settings.notchHintDone, hint.isShown, !settings.menuBarMode { offerHint() } else { offerScreenHint() }
        }
    }

    private func triggerRect() -> NSRect {
        let f = notch.screen.frame
        let w = max(Layout.triggerW, notch.width + 24)
        let h = max(Layout.triggerH, notch.height + 2)
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
            .insetBy(dx: -2, dy: -2)
    }

    private func visibleRect() -> NSRect {
        let f = notch.screen.frame
        let size = Layout.size(for: state.mode, notchW: notch.width, notchH: notch.height)
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func isInsideActiveArea(_ p: NSPoint) -> Bool {
        triggerRect().contains(p) || visibleRect().insetBy(dx: -2, dy: -2).contains(p)
    }

    private func cursorMoved() {
        guard enabled else { return }
        let p = NSEvent.mouseLocation
        if !shown {
            if settings.islandScreen == "cursor", !NSMouseInRect(p, notch.screen.frame, false) { place() }
            guard triggerRect().contains(p) else { cancelOpen(); return }
            guard !settings.openByClick else { return }
            scheduleOpen()
            return
        }
        let f = panel.frame
        PointerTracker.shared.point = CGPoint(x: p.x - f.minX, y: f.maxY - p.y)
        updateHitTesting(p)
        if isInsideActiveArea(p) || state.mode == .settings { cancelHide() } else { scheduleHide() }
    }

    private func scheduleOpen() {
        let delay = settings.openDelayMs / 1000
        guard delay > 0.01 else { show(); return }
        guard openTimer == nil else { return }
        openTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.openTimer = nil
                if !self.shown, self.triggerRect().contains(NSEvent.mouseLocation) { self.show() }
            }
        }
    }

    private func cancelOpen() {
        openTimer?.invalidate()
        openTimer = nil
    }

    private func flash() {
        guard enabled, !shown else { return }
        show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shown, self.state.mode == .collapsed, !self.state.pinned,
                      !self.isInsideActiveArea(NSEvent.mouseLocation) else { return }
                self.hide()
            }
        }
    }

    private func escape(from window: NSWindow?) -> Bool {
        guard window === panel, shown else { return false }
        if TradeDesk.shared.pendingTag != nil, state.mode == .trade || state.mode == .journal {
            TradeDesk.shared.pendingTag = nil
            return true
        }
        switch state.mode {
        case .wallet: state.mode = .longTerm; return true
        case .detail: state.mode = .home; return true
        default: break
        }
        guard !state.pinned, state.mode != .settings, !(state.mode == .assistant && state.probDetail != nil) else { return false }
        hide()
        return true
    }


    private func swipe(_ e: NSEvent) -> Bool {
        guard e.window === panel, shown, e.hasPreciseScrollingDeltas, let tab = IslandTab.of(state.mode) else { return false }
        if e.phase == .began { swipeX = 0; swipeDone = false }
        guard e.phase == .began || e.phase == .changed else { return false }
        guard abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 1.5 else { return false }
        swipeX += e.isDirectionInvertedFromDevice ? e.scrollingDeltaX : -e.scrollingDeltaX
        guard !swipeDone, abs(swipeX) > 70 else { return true }
        swipeDone = true
        let tabs = IslandTab.visible
        guard let i = tabs.firstIndex(of: tab) else { return true }
        let next = i + (swipeX < 0 ? 1 : -1)
        guard tabs.indices.contains(next) else { return true }
        settings.lastTab = tabs[next]
        withAnimation(settings.motion.page) { state.mode = tabs[next].mode }
        return true
    }

    private func shortcut(_ c: String) -> Bool {
        guard shown, state.mode != .collapsed else { return false }
        if c == "," { state.openSettings(); return true }
        guard let n = Int(c), n >= 1, n <= IslandTab.visible.count else { return false }
        let tab = IslandTab.visible[n - 1]
        settings.lastTab = tab
        state.mode = tab.mode
        return true
    }

    private func updateHitTesting(_ p: NSPoint) {
        let over = shown && visibleRect().insetBy(dx: -2, dy: -2).contains(p)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    private func scheduleHide() {
        guard hideTimer == nil else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: Layout.hideDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideTimerFired() }
        }
    }

    private func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func hideTimerFired() {
        hideTimer = nil
        guard shown else { return }
        if isInsideActiveArea(NSEvent.mouseLocation) || state.mode == .settings || state.pinned { return }
        hide()
    }

    private func show() {
        guard enabled, !shown else { return }
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                             reason: "Island open: tracking the pointer")
        }
        if settings.effectiveEnergy != .normal {
            rates.refreshIfStale()
        }
        shown = true
        cancelHide()
        cancelOpen()
        if hint.isShown { hint.dismiss() }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.shown else { return }
                withAnimation(self.settings.motion.island) {
                    self.state.visible = true
                    if self.settings.expandOnHover && self.state.mode == .collapsed {
                        self.state.mode = TradeDesk.shared.hasTrade ? .trade : self.settings.lastTab.mode
                    }
                }
            }
        }
        updateHitTesting(NSEvent.mouseLocation)
    }

    private func hide() {
        PointerTracker.shared.point = nil
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        guard shown else { return }
        shown = false
        cancelHide()
        panel.ignoresMouseEvents = true
        guard let anim = settings.motion.close else {
            state.visible = false
            finishHide()
            return
        }
        withAnimation(anim, completionCriteria: .logicallyComplete) {
            state.visible = false
        } completion: { [weak self] in
            MainActor.assumeIsolated { self?.finishHide() }
        }
    }

    private func finishHide() {
        guard !shown else { return }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { state.mode = .collapsed }
        if !(settings.look.glass && notch.width > 0) { panel.orderOut(nil) }
    }

    private func installMonitors() {
        let hover: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: hover) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.cursorMoved() }
            return e
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] e in
            MainActor.assumeIsolated {
                if let self, e.window === self.panel, self.shown, !self.panel.isKeyWindow { self.panel.makeKey() }
            }
            return e
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53, e.window?.firstResponder is NSTextView == false {
                let used = MainActor.assumeIsolated { self?.escape(from: e.window) ?? false }
                if used { return nil }
            }
            if e.modifierFlags.intersection([.command, .control, .option]) == .command, let c = e.charactersIgnoringModifiers {
                let used = MainActor.assumeIsolated { self?.shortcut(c) ?? false }
                if used { return nil }
            }
            let typing = e.window.map { !$0.isKeyWindow || $0.firstResponder is NSTextView } ?? true
            guard !typing, e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let c = e.charactersIgnoringModifiers?.lowercased() else { return e }
            let used = MainActor.assumeIsolated { TradeDesk.shared.hotkeysActive && TradeDesk.shared.hotkey(c) }
            return used ? nil : e
        }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            let used = MainActor.assumeIsolated { self?.swipe(e) ?? false }
            return used ? nil : e
        }) {
            monitors.append(m)
        }
        let outside: (NSEvent) -> Void = { [weak self] e in
            let left = e.type == .leftMouseDown
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.shown {
                    if left, self.enabled, self.settings.openByClick, self.triggerRect().contains(NSEvent.mouseLocation) { self.show() }
                    return
                }
                guard !self.state.pinned else { return }
                if self.triggerRect().contains(NSEvent.mouseLocation) {
                    if self.state.mode != .collapsed { self.state.mode = .collapsed }
                } else {
                    self.hide()
                }
            }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside) {
            monitors.append(m)
        }
    }
}
