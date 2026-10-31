import AppKit
import SwiftUI

@MainActor
struct ChartPlan {
    var drift = 0.0
    var momentum: Double?
    var levels: (stop: Double, target: Double, pStop: Double, pTarget: Double)?
    var scenarios: [(percentile: Double, path: [Double])] = []
}


@MainActor
struct PlanChart: View {
    let model: ProbabilityModel
    let horizon: Int
    let chart: ChartPlan
    let format: (Double) -> String
    let onDrag: (String, Double) -> Void
    var showLevels: Bool { chart.levels != nil }
    fileprivate var stopV: Double { chart.levels?.stop ?? model.price }
    fileprivate var targetV: Double { chart.levels?.target ?? model.price }
    @Environment(\.look) private var look
    @State private var hoverBox = PlanHover()
    @State private var dragging: String?

    fileprivate var edge: Double { chart.drift }

    fileprivate struct Geo {
        let w: CGFloat, plotH: CGFloat, histW: CGFloat, lo: Double, hi: Double, hist: [PricePoint], sma: [Double?]
        func y(_ v: Double) -> CGFloat { CGFloat((hi - v) / (hi - lo)) * plotH }
        func value(_ y: CGFloat) -> Double { hi - Double(y / plotH) * (hi - lo) }
    }

    fileprivate func geo(_ size: CGSize) -> Geo {
        let hist = Array(model.closes.suffix(60))
        let sma = Array(model.sma50Series.suffix(60))
        let wide = model.range(horizon, z: 1.645, drift: edge)
        let vals = hist.map(\.value) + sma.compactMap { $0 } + [wide.lo, wide.hi] + (showLevels ? [stopV, targetV] : [])
        let span = max(vals.max()! - vals.min()!, vals.max()! * 0.0005)
        let lo = vals.min()! - span * 0.08, hi = vals.max()! + span * 0.12
        let w = size.width - 56
        return Geo(w: w, plotH: size.height - 22, histW: w * 0.6, lo: lo, hi: hi, hist: hist, sma: sma)
    }

    var body: some View {
        GeometryReader { g in
            let G = geo(g.size)
            let box = hoverBox
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(ctx, G) }
                    .drawingGroup()
                PlanHoverLayer(box: box, chart: self, G: G, size: g.size, dragging: dragging != nil)
            }
            .contentShape(Rectangle())
            .islandHover { point in
                if let p = point, p.x <= G.w {
                    box.point = p
                    let onLine = showLevels && p.x >= G.histW - 10 && min(abs(G.y(targetV) - p.y), abs(G.y(stopV) - p.y)) < 18
                    let want = onLine || dragging != nil ? NSCursor.resizeUpDown : NSCursor.crosshair
                    if NSCursor.current !== want { want.set() }
                } else {
                    box.point = nil
                    NSCursor.arrow.set()
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    if dragging == nil {
                        guard showLevels, d.startLocation.x >= G.histW - 10 else { return }
                        let near = [("target", abs(G.y(targetV) - d.startLocation.y)),
                                    ("stop", abs(G.y(stopV) - d.startLocation.y))].min { $0.1 < $1.1 }!
                        guard near.1 < 18 else { return }
                        dragging = near.0
                    }
                    if let id = dragging {
                        onDrag(id, max(G.lo, min(G.hi, G.value(min(max(d.location.y, 0), G.plotH)))))
                    }
                }
                .onEnded { _ in dragging = nil })
        }
    }

    fileprivate func xf(_ G: Geo, _ d: Double) -> CGFloat { G.histW + (G.w - G.histW) * CGFloat(d / Double(horizon)) }

    private func draw(_ ctx: GraphicsContext, _ G: Geo) {
        let label = { (s: String, at: CGPoint, anchor: UnitPoint) in
            ctx.draw(Text(s).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.42)), at: at, anchor: anchor)
        }
        let step = niceStep((G.hi - G.lo) / 4)
        var v = (G.lo / step).rounded(.up) * step
        while v <= G.hi {
            var p = Path(); p.move(to: CGPoint(x: 0, y: G.y(v))); p.addLine(to: CGPoint(x: G.w, y: G.y(v)))
            ctx.stroke(p, with: .color(look.theme.line), lineWidth: 1)
            label(format(v), CGPoint(x: G.w + 6, y: G.y(v)), .leading)
            v += step
        }
        for (z, op) in [(1.645, 0.15), (0.674, 0.26)] {
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            for d in 0...horizon {
                let r = model.range(d, z: z, drift: edge)
                top.append(CGPoint(x: xf(G, Double(d)), y: G.y(r.hi)))
                bottom.append(CGPoint(x: xf(G, Double(d)), y: G.y(r.lo)))
            }
            var p = Path(); p.addLines(top + bottom.reversed()); p.closeSubpath()
            ctx.fill(p, with: .color(Accent.blue.color.opacity(op)))
        }
        let entryY = G.y(model.price)
        if showLevels {
        ctx.fill(Path(CGRect(x: G.histW, y: G.y(targetV), width: G.w - G.histW, height: entryY - G.y(targetV)).standardized),
                 with: .color(look.trend.green.opacity(0.07)))
        ctx.fill(Path(CGRect(x: G.histW, y: entryY, width: G.w - G.histW, height: G.y(stopV) - entryY).standardized),
                 with: .color(look.trend.red.opacity(0.07)))
        for (id, lv, color, text) in [
            ("target", targetV, look.trend.green, tr("target \(format(targetV)) · reaches \(pct(chart.levels?.pTarget ?? 0))")),
            ("stop", stopV, look.trend.red, tr("stop \(format(stopV)) · hits \(pct(chart.levels?.pStop ?? 0))")),
        ] {
            let y = G.y(lv), on = dragging == id
            var p = Path(); p.move(to: CGPoint(x: G.histW, y: y)); p.addLine(to: CGPoint(x: G.w, y: y))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: on ? 2.2 : 1.6, dash: [5, 4]))
            ctx.fill(Path(roundedRect: CGRect(x: G.w - 8, y: y - 7, width: 8, height: 14), cornerRadius: 3), with: .color(color))
            var ty = lv > model.price ? y - 10 : y + 11
            if ty < 8 { ty = y + 11 }
            if ty > G.plotH - 6 { ty = y - 10 }
            ctx.draw(Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(.white),
                     at: CGPoint(x: G.w - 14, y: ty), anchor: .trailing)
        }
        }
        let n = max(G.hist.count - 1, 1)
        var path = Path()
        path.addLines(G.hist.enumerated().map { CGPoint(x: G.histW * CGFloat($0.offset) / CGFloat(n), y: G.y($0.element.value)) })
        ctx.stroke(path, with: .color(look.trend.green), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        var smaPath = Path(), started = false
        for (i, v) in G.sma.enumerated() {
            guard let v else { started = false; continue }
            let pt = CGPoint(x: G.histW * CGFloat(i) / CGFloat(n), y: G.y(v))
            if started { smaPath.addLine(to: pt) } else { smaPath.move(to: pt); started = true }
        }
        ctx.stroke(smaPath, with: .color(Accent.orange.color.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        for sc in chart.scenarios where !sc.path.isEmpty {
            var sp = Path(); sp.move(to: CGPoint(x: G.histW, y: entryY))
            for (d, v) in sc.path.enumerated() { sp.addLine(to: CGPoint(x: xf(G, Double(d + 1)), y: G.y(v))) }
            let c: Color = sc.percentile < 0.4 ? look.trend.red : sc.percentile > 0.6 ? look.trend.green : .white
            ctx.stroke(sp, with: .color(c.opacity(sc.percentile == 0.5 ? 0.55 : 0.4)),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
        }
        if let score = chart.momentum {
            let endV = model.price * exp(edge * Double(horizon))
            var mp = Path(); mp.move(to: CGPoint(x: G.histW, y: entryY)); mp.addLine(to: CGPoint(x: G.w, y: G.y(endV)))
            ctx.stroke(mp, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [2, 4]))
            ctx.draw(Text(tr("momentum") + String(format: " %+.1f · %+.1f%%", score, (endV / model.price - 1) * 100))
                        .font(.system(size: 10.5, weight: .semibold)).foregroundColor(.white.opacity(0.85)),
                     at: CGPoint(x: G.w - 14, y: G.y(endV) + (endV >= model.price ? -9 : 9)), anchor: .trailing)
        }
        var today = Path(); today.move(to: CGPoint(x: G.histW, y: 0)); today.addLine(to: CGPoint(x: G.histW, y: G.plotH))
        ctx.stroke(today, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        ctx.fill(Path(ellipseIn: CGRect(x: G.histW - 5, y: entryY - 5, width: 10, height: 10)), with: .color(.white))
        let px = ctx.resolve(Text(format(model.price)).font(.system(size: 10.5, weight: .bold).monospacedDigit()).foregroundColor(.black))
        let ps = px.measure(in: CGSize(width: 200, height: 40))
        let axis = CGRect(x: G.w + 3, y: entryY - 9, width: ps.width + 10, height: 18)
        ctx.fill(Path(roundedRect: axis, cornerRadius: 5), with: .color(.white))
        ctx.draw(px, at: CGPoint(x: axis.midX, y: axis.midY), anchor: .center)
        let ty = G.plotH + 12
        let fmt = model.intraday ? "HH:mm" : "d MMM"
        if let first = G.hist.first { label(Fmt.date(first.time, model.intraday ? "d MMM HH:mm" : "d MMM"), CGPoint(x: 0, y: ty), .leading) }
        if G.hist.count > 30 {
            let t = G.hist[G.hist.count / 2].time
            label(Fmt.date(t, model.intraday && !Calendar.current.isDateInToday(t) ? "d MMM HH:mm" : fmt), CGPoint(x: G.histW / 2, y: ty), .center)
        }
        let lastDay = G.hist.last?.time ?? Date()
        ctx.draw(Text(!model.intraday ? Fmt.date(lastDay, "d MMM")
                      : tr("now") + " " + Fmt.date(Date(), "HH:mm")
                        + (model.isLive ? "" : " · " + tr("last \(Fmt.date(model.lastClose, "d MMM HH:mm"))"))).font(.system(size: 10.5, weight: .bold)).foregroundColor(.white.opacity(0.75)),
                 at: CGPoint(x: G.histW, y: ty), anchor: .center)
        if horizon >= 10 { label(Fmt.date(model.sessionDate(horizon / 2), fmt), CGPoint(x: xf(G, Double(horizon) / 2), y: ty), .center) }
        label(Fmt.date(model.sessionDate(horizon), fmt), CGPoint(x: G.w, y: ty), .trailing)
    }

    fileprivate func hoverDot(_ G: Geo, _ h: CGPoint) -> CGPoint? {
        guard h.x <= G.histW, !G.hist.isEmpty else { return nil }
        let n = max(G.hist.count - 1, 1)
        let i = min(max(Int((h.x / G.histW * CGFloat(n)).rounded()), 0), G.hist.count - 1)
        return CGPoint(x: G.histW * CGFloat(i) / CGFloat(n), y: G.y(G.hist[i].value))
    }

    fileprivate func tooltip(_ G: Geo, _ h: CGPoint, size: CGSize) -> some View {
        let lines: [String]
        if h.x <= G.histW, !G.hist.isEmpty {
            let n = max(G.hist.count - 1, 1)
            let i = min(max(Int((h.x / G.histW * CGFloat(n)).rounded()), 0), G.hist.count - 1)
            lines = [Fmt.date(G.hist[i].time, model.intraday ? "d MMM HH:mm" : "d MMM") + "  " + format(G.hist[i].value)]
        } else {
            let d = max(1, Int(((h.x - G.histW) / (G.w - G.histW) * CGFloat(horizon)).rounded()))
            let r5 = model.range(d, z: 0.674, drift: edge), r9 = model.range(d, z: 1.645, drift: edge)
            lines = [Fmt.date(model.sessionDate(d), model.intraday ? "HH:mm" : "EEE d MMM") + " · " + tr("in \(model.spanText(d))")]
                + (chart.momentum != nil ? [tr("momentum path \(format(model.price * exp(edge * Double(d))))")] : [])
                + ["50%: " + format(r5.lo) + " – " + format(r5.hi) + "  ·  90%: " + format(r9.lo) + " – " + format(r9.hi)]
                + (showLevels ? [tr("target by this day \(pct(model.touch(targetV, h: d))) · stop \(pct(model.touch(stopV, h: d)))")] : [])
        }
        let right = h.x > size.width * 0.55
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                Text(l).font(.system(size: 11, weight: i == 0 ? .bold : .regular).monospacedDigit())
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.85)))
        .fixedSize()
        .alignmentGuide(.leading) { d in right ? d.width - h.x + 14 : -h.x - 14 }
        .offset(y: 6)
        .allowsHitTesting(false)
    }

    private func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }

    private func niceStep(_ x: Double) -> Double {
        let p = pow(10, floor(log10(max(x, 1e-9))))
        let m = x / p
        return (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10) * p
    }
}

@MainActor
final class PlanHover: ObservableObject {
    @Published var point: CGPoint?
}

@MainActor
private struct PlanHoverLayer: View {
    @ObservedObject var box: PlanHover
    let chart: PlanChart
    let G: PlanChart.Geo
    let size: CGSize
    let dragging: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let h = box.point, !dragging {
                Rectangle().fill(Color.white.opacity(0.5))
                    .frame(width: 1, height: G.plotH)
                    .offset(x: h.x - 0.5)
                if let d = chart.hoverDot(G, h) {
                    Circle().fill(Color.white).frame(width: 9, height: 9)
                        .offset(x: d.x - 4.5, y: d.y - 4.5)
                }
                chart.tooltip(G, h, size: size).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: box.point == nil)
        .allowsHitTesting(false)
    }
}
