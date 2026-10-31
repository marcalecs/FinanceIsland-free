import AppKit
import SwiftUI

@MainActor
final class NotchHint {
    enum Kind { case notch, virtual }

    private var panel: NSPanel?
    private var popover: NSPopover?
    private var onDismiss: (() -> Void)?

    var isShown: Bool { panel != nil || popover != nil }

    func show(kind: Kind, below notch: NotchInfo, settings: AppSettings, onDismiss: @escaping () -> Void) {
        close()
        self.onDismiss = onDismiss
        let view = NotchHintView(kind: kind, reduceMotion: settings.reduceMotion || !settings.motion.enabled,
                                 look: settings.look) { [weak self] in self?.dismiss() }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.transient, .ignoresCycle]
        p.contentView = host
        let f = notch.screen.frame
        let top = f.maxY - max(notch.height, 24) - 4
        p.setFrame(NSRect(x: f.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        panel = p
    }

    func showMenuBar(at button: NSStatusBarButton, onDismiss: @escaping () -> Void) {
        close()
        self.onDismiss = onDismiss
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: MenuBarHintView { [weak self] in self?.dismiss() })
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover = pop
    }

    func dismiss() {
        let done = onDismiss
        close()
        done?()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        popover?.performClose(nil)
        popover = nil
        onDismiss = nil
    }
}

struct NotchHintView: View {
    let kind: NotchHint.Kind
    let reduceMotion: Bool
    let look: Look
    let dismiss: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(look.accent)
                .offset(y: pulse ? -4 : 0)
                .opacity(pulse ? 1 : 0.7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr(kind == .notch ? "Hover here to open FinanceIsland" : "FinanceIsland lives here"))
                    .font(.system(size: 13, weight: .bold))
                if kind == .virtual {
                    Text(tr("This screen has no notch, so the island is virtual: move the pointer to the top centre. Choose the screen in Settings ▸ Widget ▸ Where the island lives."))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(tr("Don't show again"), action: dismiss)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(look.accent)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: kind == .virtual ? 300 : 250, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12)))
        }
        .foregroundStyle(.white)
        .padding(8)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

struct MenuBarHintView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("FinanceIsland lives here")).font(.system(size: 13, weight: .bold))
            Text(tr("Click this icon to open the island. The notch stays free for your other apps."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(tr("Got it"), action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
    }
}
