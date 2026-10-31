import AppKit
import Combine
import SwiftUI

final class DetachedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class DetachedIsland: NSObject, NSWindowDelegate {
    let state = IslandState()
    private let settings: AppSettings
    private let panel: DetachedPanel
    private var subs: Set<AnyCancellable> = []
    private var monitor: Any?
    var onClose: (@MainActor () -> Void)?

    static let titleH: CGFloat = 30

    init(mode: IslandMode, settings: AppSettings, rates: RateStore,
         journal: JournalStore, probability: ProbabilityStore, below anchor: NSRect? = nil) {
        self.settings = settings
        panel = DetachedPanel(contentRect: .zero, styleMask: [.borderless, .resizable],
                              backing: .buffered, defer: false)
        super.init()
        state.detached = true
        state.visible = true
        state.notchW = 0
        state.notchH = Self.titleH
        state.mode = mode == .collapsed ? settings.lastTab.mode : mode

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let host = NSHostingView(rootView: IslandView(state: state, rates: rates, settings: settings,
                                                      journal: journal, probability: probability))
        host.sizingOptions = []
        panel.contentView = host

        let size = currentSize()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        if let a = anchor {
            let area = NSScreen.screens.first { NSIntersectsRect($0.frame, a) }?.visibleFrame ?? screen
            let x = min(max(a.midX - size.width / 2, area.minX + 8), area.maxX - size.width - 8)
            panel.setFrame(NSRect(x: x, y: a.minY - size.height - 6, width: size.width, height: size.height), display: true)
        } else {
            panel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 40,
                                  width: size.width, height: size.height), display: true)
        }

        state.$mode.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.resize() } }
        }
        .store(in: &subs)
        state.onAttach = { [weak self] in self?.close() }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] e in
            MainActor.assumeIsolated {
                guard let self, e.window === self.panel else { return }
                let p = e.locationInWindow, h = self.panel.frame.height
                PointerTracker.shared.point = CGPoint(x: p.x, y: h - p.y)
            }
            return e
        }
        panel.acceptsMouseMovedEvents = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func currentSize() -> CGSize {
        let mode = state.mode == .collapsed ? settings.lastTab.mode : state.mode
        var s = Layout.size(for: mode, notchW: 0, notchH: Self.titleH)
        s.height += Layout.detachedBottom
        return s
    }

    private func resize() {
        if state.mode == .collapsed { state.mode = settings.lastTab.mode; return }
        let size = currentSize()
        let f = panel.frame
        guard abs(f.width - size.width) > 0.5 || abs(f.height - size.height) > 0.5 else { return }
        let next = NSRect(x: f.minX, y: f.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(next, display: true, animate: settings.motion.enabled)
    }

    func close() {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        PointerTracker.shared.point = nil
        subs.removeAll()
        onClose?()
    }
}
