import AppKit

enum Layout {
    static let panelW: CGFloat = pageW
    static let panelH: CGFloat = pageH + 48

    static let pageW: CGFloat = 760
    static let pageH: CGFloat = 540
    static let barH: CGFloat = 58
    static let gutter: CGFloat = 22
    static let bodyH: CGFloat = pageH - barH

    static let pillW: CGFloat = 190
    static let dropH: CGFloat = 30

    static let triggerW: CGFloat = 200
    static let triggerH: CGFloat = 40
    static let hideDelay: TimeInterval = 0.7

    static let detachedBottom: CGFloat = 14

    @MainActor
    static func size(for mode: IslandMode, notchW: CGFloat, notchH: CGFloat) -> CGSize {
        guard mode == .collapsed else { return CGSize(width: pageW, height: notchH + pageH) }
        let w = notchW > 0 ? notchW : pillW
        return CGSize(width: max(w, TradeDesk.shared.collapsedWidth ?? 0), height: notchH + dropH)
    }
}

struct NotchInfo {
    let screen: NSScreen
    let width: CGFloat
    let height: CGFloat
    let isBuiltIn: Bool
}

@MainActor
private func isBuiltInDisplay(_ s: NSScreen) -> Bool {
    guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
    return CGDisplayIsBuiltin(num.uint32Value) != 0
}

@MainActor
func displayID(_ s: NSScreen) -> String {
    (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { "\($0.uint32Value)" } ?? ""
}

@MainActor
func islandScreen(_ choice: String) -> NSScreen {
    let screens = NSScreen.screens
    let fallback = screens.first(where: { isBuiltInDisplay($0) }) ?? NSScreen.main ?? screens[0]
    switch choice {
    case "auto": return fallback
    case "cursor":
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? fallback
    default: return screens.first { displayID($0) == choice } ?? fallback
    }
}

@MainActor
func currentNotch(_ choice: String = "auto") -> NotchInfo {
    let screen = islandScreen(choice)
    let ok = isBuiltInDisplay(screen)

    if screen.safeAreaInsets.top > 0,
       let left = screen.auxiliaryTopLeftArea,
       let right = screen.auxiliaryTopRightArea {
        return NotchInfo(screen: screen,
                         width: screen.frame.width - left.width - right.width,
                         height: screen.safeAreaInsets.top,
                         isBuiltIn: ok)
    }
    let bar = screen.frame.maxY - screen.visibleFrame.maxY
    return NotchInfo(screen: screen, width: 0, height: bar > 0 ? bar : 24, isBuiltIn: ok)
}
