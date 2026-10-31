import SwiftUI

struct ReorderGeometry {
    var columns: Int = 1
    var colStride: CGFloat = 0
    var rowStride: CGFloat

    func offset(from a: Int, to b: Int) -> CGSize {
        let c = max(columns, 1)
        return CGSize(width: CGFloat(b % c - a % c) * colStride, height: CGFloat(b / c - a / c) * rowStride)
    }

    func target(from i: Int, translation t: CGSize, count: Int) -> Int {
        let c = max(columns, 1)
        let dc = colStride > 0 ? Int((t.width / colStride).rounded()) : 0
        let dr = rowStride > 0 ? Int((t.height / rowStride).rounded()) : 0
        let col = min(max(i % c + dc, 0), c - 1)
        let row = max(i / c + dr, 0)
        return min(max(row * c + col, 0), max(count - 1, 0))
    }
}

@MainActor
final class DragGhost: ObservableObject {
    nonisolated static let space = "island"
    @Published var view: AnyView?
    @Published var frame: CGRect = .zero
    @Published var translation: CGSize = .zero
}

private struct DragGhostKey: EnvironmentKey {
    static let defaultValue: DragGhost? = nil
}

extension EnvironmentValues {
    var dragGhost: DragGhost? {
        get { self[DragGhostKey.self] }
        set { self[DragGhostKey.self] = newValue }
    }
}

@MainActor
struct DragGhostLayer: View {
    @ObservedObject var ghost: DragGhost

    var body: some View {
        if let v = ghost.view {
            v.frame(width: ghost.frame.width, height: ghost.frame.height)
                .scaleEffect(1.05)
                .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
                .position(x: ghost.frame.midX + ghost.translation.width, y: ghost.frame.midY + ghost.translation.height)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

@MainActor
final class ReorderModel: ObservableObject {
    @Published var dragging: String?
    @Published var translation: CGSize = .zero
    @Published var target = 0
    @Published var editing = false
    var heldRecently: String?

    func offset(for id: String, index: Int, ids: [String], geo: ReorderGeometry) -> CGSize {
        guard let d = dragging, let from = ids.firstIndex(of: d) else { return .zero }
        if id == d { return translation }
        var preview = ids
        preview.remove(at: from)
        preview.insert(d, at: min(target, preview.count))
        guard let to = preview.firstIndex(of: id) else { return .zero }
        return geo.offset(from: index, to: to)
    }
}

private struct ReorderableModifier: ViewModifier {
    let id: String
    let index: Int
    let ids: [String]
    @ObservedObject var model: ReorderModel
    let geo: ReorderGeometry
    let enabled: Bool
    let onMove: (String, Int) -> Void
    let onHold: (() -> Void)?
    let onTap: (() -> Void)?
    let onDoubleTap: (() -> Void)?
    let snapshot: AnyView

    @GestureState private var pressed = false
    @State private var pendingTap: DispatchWorkItem?
    @State private var frame = FrameBox()
    @Environment(\.dragGhost) private var ghost

    func body(content: Content) -> some View {
        let isDragged = model.dragging == id
        let lifted = isDragged && ghost != nil
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DragGhost.space)) } action: { frame.rect = $0 }
            .scaleEffect(isDragged ? 1.04 : (pressed ? 0.97 : 1))
            .animation(.easeOut(duration: 0.1), value: pressed)
            .opacity(lifted ? 0 : 1)
            .shadow(color: .black.opacity(isDragged && !lifted ? 0.45 : 0), radius: isDragged ? 14 : 0, y: isDragged ? 6 : 0)
            .offset(model.offset(for: id, index: index, ids: ids, geo: geo))
            .zIndex(isDragged ? 10 : 0)
            .animation(isDragged ? nil : .spring(response: 0.28, dampingFraction: 0.85), value: model.target)
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: model.dragging)
            .simultaneousGesture(TapGesture(count: 1).onEnded { tapped() })
            .gesture(holdAndDrag(content), including: enabled ? .all : .subviews)
    }

    private func tapped() {
        guard model.dragging == nil, model.heldRecently != id else { return }
        guard let onDoubleTap else { onTap?(); return }
        if let p = pendingTap, !p.isCancelled {
            p.cancel()
            pendingTap = nil
            onDoubleTap()
            return
        }
        let work = DispatchWorkItem { onTap?() }
        pendingTap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func holdAndDrag(_ content: Content) -> some Gesture {
        LongPressGesture(minimumDuration: model.editing ? 0.01 : 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($pressed) { value, state, _ in
                if case .first(true) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if model.dragging == nil {
                    model.dragging = id
                    model.target = index
                    ghost?.frame = frame.rect
                    ghost?.translation = .zero
                    ghost?.view = snapshot
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                guard let drag else { return }
                model.translation = geo.columns <= 1 ? CGSize(width: 0, height: drag.translation.height) : drag.translation
                ghost?.translation = model.translation
                let t = geo.target(from: index, translation: drag.translation, count: ids.count)
                if t != model.target {
                    model.target = t
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
            .onEnded { value in
                guard case .second(true, let drag) = value else { return }
                model.heldRecently = id
                let held = id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if model.heldRecently == held { model.heldRecently = nil }
                }
                let moved = (drag.map { abs($0.translation.width) + abs($0.translation.height) } ?? 0) > 4
                let target = model.target
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                    if moved && target != index { onMove(id, target) }
                    model.dragging = nil
                    model.translation = .zero
                }
                ghost?.view = nil
                if !moved { onHold?() }
            }
    }
}

extension View {
    func verticalOnly() -> some View {
        scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    func reorderable(id: String, index: Int, ids: [String], model: ReorderModel, geo: ReorderGeometry,
                     enabled: Bool = true, onMove: @escaping (String, Int) -> Void,
                     onHold: (() -> Void)? = nil, onTap: (() -> Void)? = nil,
                     onDoubleTap: (() -> Void)? = nil) -> some View {
        modifier(ReorderableModifier(id: id, index: index, ids: ids, model: model, geo: geo, enabled: enabled,
                                     onMove: onMove, onHold: onHold, onTap: onTap, onDoubleTap: onDoubleTap,
                                     snapshot: AnyView(self)))
    }
}

@MainActor
struct RemoveBadge: View {
    let label: String
    let action: () -> Void
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(look.trend.red))
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(tr("Remove ") + label)
        .transition(.scale.combined(with: .opacity))
    }
}

final class FrameBox {
    var rect: CGRect = .zero
}
