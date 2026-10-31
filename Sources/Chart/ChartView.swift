import AppKit
import SwiftUI

struct TVGeo {
    static let axisW: CGFloat = 72, timeH: CGFloat = 24
    let plotW: CGFloat, priceH: CGFloat, volTop: CGFloat, volH: CGFloat, height: CGFloat
    let rsiTop: CGFloat, rsiH: CGFloat, macdTop: CGFloat, macdH: CGFloat
    let first: Double, visible: Double, bw: CGFloat
    let lo: Int, hi: Int
    let pMin: Double, pMax: Double, vMax: Double

    @MainActor
    init(_ m: ChartModel, _ size: CGSize) {
        let c = m.candles
        plotW = max(size.width - Self.axisW, 10)
        let plotH = max(size.height - Self.timeH, 10)
        volH = m.indicators.contains(.volume) ? plotH * 0.17 : 0
        rsiH = m.indicators.contains(.rsi) ? plotH * 0.17 : 0
        macdH = m.indicators.contains(.macd) ? plotH * 0.17 : 0
        priceH = plotH - volH - rsiH - macdH
        volTop = priceH
        rsiTop = priceH + volH
        macdTop = rsiTop + rsiH
        height = plotH
        first = m.first; visible = m.visible
        bw = plotW / CGFloat(max(visible, 1))
        lo = max(0, Int(first.rounded(.down)))
        hi = min(c.count - 1, Int((first + visible).rounded(.up)))
        var a = Double.greatestFiniteMagnitude, b = -Double.greatestFiniteMagnitude, vm = 0.0
        if lo <= hi {
            for i in lo...hi { a = min(a, c[i].low); b = max(b, c[i].high); vm = max(vm, c[i].volume) }
        } else if let l = c.last { a = l.low; b = l.high }
        if a > b { a = 0; b = 1 }
        let pad = max((b - a) * 0.08, b * 0.0005)
        let mid = (a + b) / 2, half = ((b - a) / 2 + pad) / m.priceScale
        pMin = mid - half; pMax = mid + half
        vMax = vm
    }

    func x(_ i: Double) -> CGFloat { CGFloat(i - first) * bw + bw / 2 }
    func index(_ x: CGFloat) -> Double { Double(x / bw - 0.5) + first }
    func y(_ p: Double) -> CGFloat { CGFloat((pMax - p) / max(pMax - pMin, 1e-12)) * priceH }
    func price(_ y: CGFloat) -> Double { pMax - Double(y / priceH) * (pMax - pMin) }

    static func niceStep(_ x: Double) -> Double {
        let p = pow(10, floor(log10(max(x, 1e-12))))
        let m = x / p
        return (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10) * p
    }

    static func fmt(_ v: Double) -> String {
        let a = abs(v)
        return a >= 10_000 ? Fmt.number(v, min: 0, max: 0) : a >= 100 ? Fmt.number(v, min: 2, max: 2)
            : a >= 1 ? Fmt.number(v, min: 2, max: 4) : Fmt.number(v, min: 4, max: 6)
    }
}

private let up = Color(red: 0.16, green: 0.74, blue: 0.47)
private let down = Color(red: 0.95, green: 0.33, blue: 0.33)

@MainActor
struct ChartWindowView: View {
    @ObservedObject var model: ChartModel
    let hover: ChartHover

    var body: some View {
        VStack(spacing: 0) {
            ChartToolbar(model: model)
            Divider().overlay(Color.white.opacity(0.08))
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    ChartCanvas(model: model)
                    ChartCrosshair(model: model, hover: hover)
                    ChartGestures(model: model, hover: hover)
                    if model.loading && model.candles.isEmpty {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let e = model.error, model.candles.isEmpty {
                        Text(tr(e)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { ChartWindows.plotFrames[model.subject.id] = $0 }
                .frame(width: g.size.width, height: g.size.height)
            }
            .padding(.leading, 10)
        }
        .background(Color(red: 0.07, green: 0.07, blue: 0.08))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private struct ChartToolbar: View {
    @ObservedObject var model: ChartModel
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            Text(model.subject.short).font(.system(size: 15, weight: .bold))
            if model.live { LiveDot() }
            if !model.source.isEmpty {
                Text(model.source).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
            PillPicker(options: ChartTF.allCases, selection: $model.tf, label: { $0.rawValue }, minWidth: 30)
            PillPicker(options: ChartModel.Style.allCases, selection: $model.style, label: { $0.rawValue }, minWidth: 40)
            Menu {
                ForEach(ChartModel.Indicator.allCases) { ind in
                    if ind != .plan || model.plan != nil {
                        Toggle(tr(ind.rawValue), isOn: Binding(
                            get: { model.indicators.contains(ind) },
                            set: { on in if on { model.indicators.insert(ind) } else { model.indicators.remove(ind) } }))
                    }
                }
            } label: {
                Label(tr("Indicators"), systemImage: "waveform.path.ecg").font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .padding(.horizontal, 10).frame(height: 30)
            .background(Capsule().fill(look.theme.chip))
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(ChartModel.Tool.allCases) { t in
                    Button { model.tool = t } label: {
                        Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 28)
                            .background(Capsule().fill(model.tool == t ? look.theme.selected : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr(t.title))
                }
            }
            .padding(3)
            .background(Capsule().fill(look.theme.chip))
            if !model.drawings.isEmpty {
                CircleIconButton(symbol: "arrow.uturn.backward", label: "Undo drawing") { _ = model.drawings.popLast() }
                    .help(tr("Undo the last drawing"))
                CircleIconButton(symbol: "trash", label: "Clear drawings") { model.drawings.removeAll() }
                    .help(tr("Remove all drawings"))
            }
            CircleIconButton(symbol: "arrow.up.left.and.down.right.magnifyingglass", label: "Fit") {
                withAnimation(.smooth(duration: 0.3)) { model.fit() }
            }
            .help(tr("Fit the chart (or double-click it)"))
            CircleIconButton(symbol: "arrow.clockwise", label: "Refresh") { model.load() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

@MainActor
private struct ChartCanvas: View {
    @ObservedObject var model: ChartModel

    var body: some View {
        Canvas { ctx, size in draw(ctx, size) }
            .drawingGroup()
            .allowsHitTesting(false)
    }

    private func drawPanes(_ ctx: GraphicsContext, _ clip: GraphicsContext, _ G: TVGeo, _ m: ChartModel) {
        let label = Color.white.opacity(0.55), sep = Color.white.opacity(0.12)
        func separator(_ y: CGFloat) {
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: G.plotW, y: y))
            ctx.stroke(p, with: .color(sep), lineWidth: 1)
        }
        func series(_ v: [Double?], _ y: (Double) -> CGFloat, _ color: Color) {
            var p = Path(), started = false
            for i in G.lo...G.hi where i < v.count {
                guard let x = v[i] else { started = false; continue }
                let pt = CGPoint(x: G.x(Double(i)), y: y(x))
                if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
            }
            clip.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
        }
        if G.rsiH > 0 {
            let top = G.rsiTop, h = G.rsiH
            let y = { (v: Double) in top + 4 + (h - 8) * CGFloat(1 - v / 100) }
            separator(top)
            for level in [30.0, 70.0] {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y(level))); p.addLine(to: CGPoint(x: G.plotW, y: y(level)))
                ctx.stroke(p, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ctx.draw(Text("\(Int(level))").font(.system(size: 10).monospacedDigit()).foregroundColor(label),
                         at: CGPoint(x: G.plotW + 8, y: y(level)), anchor: .leading)
            }
            series(m.rsi14, y, Color(red: 0.7, green: 0.5, blue: 1))
            let last = m.rsi14.last.flatMap { $0 }.map { String(format: "%.1f", $0) } ?? "—"
            ctx.draw(Text("RSI 14  " + last).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundColor(label),
                     at: CGPoint(x: 6, y: top + 10), anchor: .leading)
        }
        if G.macdH > 0 {
            let top = G.macdTop, h = G.macdH
            var peak = 1e-12
            for i in G.lo...G.hi where i < m.macdLine.count {
                if let a = m.macdLine[i] { peak = max(peak, abs(a)) }
                if let b = m.macdSignal[i] { peak = max(peak, abs(b)) }
            }
            let mid = top + h / 2
            let y = { (v: Double) in mid - CGFloat(v / peak) * (h / 2 - 6) }
            separator(top)
            var zero = Path(); zero.move(to: CGPoint(x: 0, y: mid)); zero.addLine(to: CGPoint(x: G.plotW, y: mid))
            ctx.stroke(zero, with: .color(.white.opacity(0.15)), lineWidth: 1)
            for i in G.lo...G.hi where i < m.macdLine.count {
                guard let a = m.macdLine[i], let b = m.macdSignal[i] else { continue }
                let hv = a - b, yh = y(hv)
                let r = CGRect(x: G.x(Double(i)) - G.bw * 0.3, y: min(yh, mid), width: max(G.bw * 0.6, 1), height: max(abs(mid - yh), 0.5))
                clip.fill(Path(r), with: .color((hv >= 0 ? up : down).opacity(0.45)))
            }
            series(m.macdLine, y, Color(red: 0.3, green: 0.6, blue: 1))
            series(m.macdSignal, y, Color.orange)
            let last = m.macdLine.last.flatMap { $0 }.map { TVGeo.fmt($0) } ?? "—"
            ctx.draw(Text("MACD 12 26 9  " + last).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundColor(label),
                     at: CGPoint(x: 6, y: top + 10), anchor: .leading)
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let m = model, c = m.candles
        guard !c.isEmpty else { return }
        let G = TVGeo(m, size)
        let grid = Color.white.opacity(0.06), label = Color.white.opacity(0.45)
        var clip = ctx
        clip.clip(to: Path(CGRect(x: 0, y: 0, width: G.plotW, height: G.height)))

        let step = TVGeo.niceStep((G.pMax - G.pMin) / 7)
        var v = (G.pMin / step).rounded(.up) * step
        while v <= G.pMax {
            let y = G.y(v)
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: G.plotW, y: y))
            ctx.stroke(p, with: .color(grid), lineWidth: 1)
            ctx.draw(Text(TVGeo.fmt(v)).font(.system(size: 10.5).monospacedDigit()).foregroundColor(label),
                     at: CGPoint(x: G.plotW + 8, y: y), anchor: .leading)
            v += step
        }
        if G.lo <= G.hi {
            let every = max(1, Int((110 / G.bw).rounded(.up)))
            let cal = Calendar.current
            var prevDay: Date?
            var i = (G.lo / every) * every
            while i <= G.hi {
                let x = G.x(Double(i))
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: G.height))
                clip.stroke(p, with: .color(grid), lineWidth: 1)
                let t = c[i].openTime, day = cal.startOfDay(for: t)
                let text = !m.tf.intraday ? Fmt.date(t, "d MMM") : (prevDay == nil || day != prevDay ? Fmt.date(t, "d MMM HH:mm") : Fmt.date(t, "HH:mm"))
                prevDay = day
                if x > 20 && x < G.plotW - 20 {
                    ctx.draw(Text(text).font(.system(size: 10.5).monospacedDigit()).foregroundColor(label),
                             at: CGPoint(x: x, y: G.height + 12), anchor: .center)
                }
                i += every
            }
        }
        guard G.lo <= G.hi else { return }

        if m.indicators.contains(.bands) {
            var top: [CGPoint] = [], bot: [CGPoint] = []
            for i in G.lo...G.hi { if let u = m.bandUp[i], let d = m.bandDown[i] {
                top.append(CGPoint(x: G.x(Double(i)), y: G.y(u))); bot.append(CGPoint(x: G.x(Double(i)), y: G.y(d))) } }
            if top.count > 1 {
                var p = Path(); p.addLines(top + bot.reversed()); p.closeSubpath()
                clip.fill(p, with: .color(Color.blue.opacity(0.08)))
                var t = Path(); t.addLines(top); clip.stroke(t, with: .color(.blue.opacity(0.5)), lineWidth: 1)
                var b = Path(); b.addLines(bot); clip.stroke(b, with: .color(.blue.opacity(0.5)), lineWidth: 1)
            }
        }
        if G.volH > 0, G.vMax > 0 {
            for i in G.lo...G.hi {
                let k = c[i], h = CGFloat(k.volume / G.vMax) * (G.volH - 4)
                let r = CGRect(x: G.x(Double(i)) - G.bw * 0.35, y: G.volTop + G.volH - h, width: max(G.bw * 0.7, 1), height: h)
                clip.fill(Path(r), with: .color((k.close >= k.open ? up : down).opacity(0.35)))
            }
        }
        drawPanes(ctx, clip, G, m)
        if m.style == .candles {
            let body = max(G.bw * 0.68, 1)
            var upWicks = Path(), downWicks = Path(), upBodies = Path(), downBodies = Path()
            for i in G.lo...G.hi {
                let k = c[i], x = G.x(Double(i)), isUp = k.close >= k.open
                let yo = G.y(k.open), yc = G.y(k.close)
                let r = CGRect(x: x - body / 2, y: min(yo, yc), width: body, height: max(abs(yc - yo), 1))
                if isUp {
                    upWicks.move(to: CGPoint(x: x, y: G.y(k.high))); upWicks.addLine(to: CGPoint(x: x, y: G.y(k.low)))
                    upBodies.addRect(r)
                } else {
                    downWicks.move(to: CGPoint(x: x, y: G.y(k.high))); downWicks.addLine(to: CGPoint(x: x, y: G.y(k.low)))
                    downBodies.addRect(r)
                }
            }
            clip.stroke(upWicks, with: .color(up), lineWidth: 1)
            clip.stroke(downWicks, with: .color(down), lineWidth: 1)
            clip.fill(upBodies, with: .color(up))
            clip.fill(downBodies, with: .color(down))
        } else {
            var p = Path()
            p.addLines((G.lo...G.hi).map { CGPoint(x: G.x(Double($0)), y: G.y(c[$0].close)) })
            clip.stroke(p, with: .color(Color(red: 0.3, green: 0.55, blue: 1)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
        func line(_ s: [Double?], _ color: Color) {
            var p = Path(), started = false
            for i in G.lo...G.hi {
                guard i < s.count, let v = s[i] else { started = false; continue }
                let pt = CGPoint(x: G.x(Double(i)), y: G.y(v))
                if started { p.addLine(to: pt) } else { p.move(to: pt); started = true }
            }
            clip.stroke(p, with: .color(color), lineWidth: 1.4)
        }
        if m.indicators.contains(.ma20) { line(m.ma20, .orange) }
        if m.indicators.contains(.ma50) { line(m.ma50, .purple) }
        if m.indicators.contains(.ema9) { line(m.ema9, .cyan) }
        if m.indicators.contains(.plan), let plan = m.plan {
            for (v, col, name) in [(plan.target, up, tr("target")), (plan.entry, Color.white, tr("Entry")), (plan.stop, down, tr("stop"))] {
                let y = G.y(v)
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: G.plotW, y: y))
                clip.stroke(p, with: .color(col.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                clip.draw(Text(name + " " + TVGeo.fmt(v)).font(.system(size: 10.5, weight: .semibold)).foregroundColor(col),
                          at: CGPoint(x: 8, y: y - 8), anchor: .leading)
            }
        }
        for d in m.drawings { drawShape(d, clip, G, m, color: Color(red: 0.98, green: 0.8, blue: 0.3)) }
        if let l = c.last {
            let y = G.y(l.close), col = l.close >= l.open ? up : down
            var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: G.plotW, y: y))
            clip.stroke(p, with: .color(col.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            axisTag(ctx, TVGeo.fmt(l.close), y: y, x: G.plotW, fill: col, text: .white)
        }
    }
}

func axisTag(_ ctx: GraphicsContext, _ s: String, y: CGFloat, x: CGFloat, fill: Color, text: Color) {
    let width = TVGeo.axisW - 4
    var size: CGFloat = 10.5
    var t = ctx.resolve(Text(s).font(.system(size: size, weight: .bold).monospacedDigit()).foregroundColor(text))
    while t.measure(in: CGSize(width: 300, height: 30)).width > width - 8, size > 7.5 {
        size -= 0.5
        t = ctx.resolve(Text(s).font(.system(size: size, weight: .bold).monospacedDigit()).foregroundColor(text))
    }
    let r = CGRect(x: x + 2, y: y - 9, width: width, height: 18)
    ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(fill))
    ctx.draw(t, at: CGPoint(x: r.minX + 4, y: r.midY), anchor: .leading)
}

@MainActor
private func drawShape(_ d: ChartModel.Drawing, _ ctx: GraphicsContext, _ G: TVGeo, _ m: ChartModel, color: Color) {
    switch d.kind {
    case .hline(let v):
        let y = G.y(v)
        var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: G.plotW, y: y))
        ctx.stroke(p, with: .color(color), lineWidth: 1.4)
        ctx.draw(Text(TVGeo.fmt(v)).font(.system(size: 10.5, weight: .semibold)).foregroundColor(color),
                 at: CGPoint(x: G.plotW - 6, y: y - 8), anchor: .trailing)
    case .trend(let t1, let p1, let t2, let p2):
        let a = CGPoint(x: G.x(m.index(of: t1)), y: G.y(p1)), b = CGPoint(x: G.x(m.index(of: t2)), y: G.y(p2))
        var p = Path(); p.move(to: a); p.addLine(to: b)
        ctx.stroke(p, with: .color(color), lineWidth: 1.6)
        for q in [a, b] { ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)), with: .color(color)) }
        ctx.draw(Text(String(format: "%+.2f%%", (p2 / p1 - 1) * 100)).font(.system(size: 10.5, weight: .semibold)).foregroundColor(color),
                 at: CGPoint(x: b.x + 6, y: b.y), anchor: .leading)
    }
}

@MainActor
private struct ChartCrosshair: View {
    @ObservedObject var model: ChartModel
    @ObservedObject var hover: ChartHover

    var body: some View {
        GeometryReader { g in
            let G = TVGeo(model, g.size)
            ZStack(alignment: .topLeading) {
                if let d = hover.draft {
                    Canvas { ctx, _ in drawShape(d, ctx, G, model, color: .white) }
                }
                if let p = hover.point, p.x <= G.plotW, p.y <= G.height {
                    DashLine(vertical: true).frame(width: 1, height: G.height).offset(x: p.x - 0.5)
                    DashLine(vertical: false).frame(width: G.plotW, height: 1).offset(y: p.y - 0.5)
                    if p.y <= G.priceH {
                        Text(TVGeo.fmt(G.price(p.y))).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 4).frame(width: TVGeo.axisW - 4, height: 18, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.3)))
                            .offset(x: G.plotW + 2, y: p.y - 9)
                    }
                    tag(Fmt.date(model.date(at: G.index(p.x).rounded()), model.tf.intraday ? "EEE d MMM HH:mm" : "EEE d MMM yyyy"))
                        .fixedSize()
                        .alignmentGuide(.leading) { d in d.width / 2 - p.x }
                        .offset(y: G.height + 3)
                }
                legend(G).padding(.leading, 8).padding(.top, 6)
            }
        }
        .allowsHitTesting(false)
    }

    private func tag(_ s: String) -> some View {
        Text(s).font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            .padding(.horizontal, 6).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.3)))
    }

    @ViewBuilder
    private func legend(_ G: TVGeo) -> some View {
        let c = model.candles
        if !c.isEmpty {
            let i = hover.point.map { min(max(Int(G.index($0.x).rounded()), 0), c.count - 1) } ?? c.count - 1
            let k = c[i], prev = i > 0 ? c[i - 1].close : k.open
            let ch = (k.close / prev - 1) * 100, col = k.close >= k.open ? up : down
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    pair("O", k.open, col); pair("H", k.high, col); pair("L", k.low, col); pair("C", k.close, col)
                    Text(String(format: "%+.2f%%", ch)).foregroundStyle(col)
                    if k.volume > 0 { Text("Vol " + AssetFormat.compact(k.volume)).foregroundStyle(.white.opacity(0.55)) }
                }
                HStack(spacing: 10) {
                    if model.indicators.contains(.ma20), let v = model.ma20[i] { Text("MA20 " + TVGeo.fmt(v)).foregroundStyle(.orange) }
                    if model.indicators.contains(.ma50), let v = model.ma50[i] { Text("MA50 " + TVGeo.fmt(v)).foregroundStyle(.purple) }
                    if model.indicators.contains(.ema9), let v = model.ema9[i] { Text("EMA9 " + TVGeo.fmt(v)).foregroundStyle(.cyan) }
                }
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
        }
    }

    private func pair(_ k: String, _ v: Double, _ c: Color) -> some View {
        HStack(spacing: 3) { Text(k).foregroundStyle(.white.opacity(0.5)); Text(TVGeo.fmt(v)).foregroundStyle(c) }
    }
}

@MainActor
private struct ChartGestures: View {
    @ObservedObject var model: ChartModel
    let hover: ChartHover
    @State private var lastDrag: CGSize = .zero
    @State private var mode: DragMode?
    private enum DragMode { case pan, axis, draw }

    var body: some View {
        GeometryReader { g in
            let G = TVGeo(model, g.size)
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        hover.point = p
                        let want = p.x > G.plotW ? NSCursor.resizeUpDown : NSCursor.crosshair
                        if NSCursor.current !== want { want.set() }
                    case .ended:
                        hover.point = nil
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { d in
                            if mode == nil {
                                mode = d.startLocation.x > G.plotW ? .axis : model.tool == .cursor ? .pan : .draw
                                lastDrag = .zero
                            }
                            let dx = d.translation.width - lastDrag.width, dy = d.translation.height - lastDrag.height
                            lastDrag = d.translation
                            hover.point = d.location
                            switch mode {
                            case .pan:
                                model.pan(bars: Double(dx / G.bw))
                                NSCursor.closedHand.set()
                            case .axis:
                                model.priceScale = min(max(model.priceScale * exp(Double(-dy) * 0.006), 0.2), 20)
                            case .draw:
                                let p0 = d.startLocation, p1 = d.location
                                if model.tool == .trend {
                                    hover.draft = .init(kind: .trend(model.date(at: G.index(p0.x)), G.price(p0.y),
                                                                     model.date(at: G.index(p1.x)), G.price(p1.y)))
                                } else {
                                    hover.draft = .init(kind: .hline(G.price(p1.y)))
                                }
                            case nil: break
                            }
                        }
                        .onEnded { d in
                            if mode == .draw, let draft = hover.draft {
                                if case .trend = draft.kind, hypot(d.translation.width, d.translation.height) < 6 {
                                } else {
                                    model.drawings.append(draft)
                                }
                            }
                            hover.draft = nil
                            mode = nil
                            NSCursor.crosshair.set()
                        }
                )
                .simultaneousGesture(TapGesture(count: 2).onEnded { withAnimation(.smooth(duration: 0.3)) { model.fit() } })
        }
    }
}

@MainActor
enum ChartWindows {
    private final class Entry: NSObject, NSWindowDelegate {
        let window: NSWindow
        let model: ChartModel
        var monitor: Any?
        init(window: NSWindow, model: ChartModel) { self.window = window; self.model = model }
        func windowDidMiniaturize(_ notification: Notification) { MainActor.assumeIsolated { model.stop() } }
        func windowDidDeminiaturize(_ notification: Notification) { MainActor.assumeIsolated { model.resume() } }
        func windowDidChangeOcclusionState(_ notification: Notification) {
            MainActor.assumeIsolated {
                if window.occlusionState.contains(.visible) { model.resume() } else { model.stop() }
            }
        }

        func windowWillClose(_ notification: Notification) {
            MainActor.assumeIsolated {
                model.stop()
                if let m = monitor { NSEvent.removeMonitor(m) }
                ChartWindows.entries[model.subject.id] = nil
                ChartWindowsState.shared.open.remove(model.subject.id)
            }
        }
    }

    private static var entries: [String: Entry] = [:]
    static var plotFrames: [String: CGRect] = [:]

    static func open(_ s: HubSubject, plan: (entry: Double, stop: Double, target: Double)? = nil, settings: AppSettings,
                     tf: ChartTF = .m15) {
        NSApp.activate(ignoringOtherApps: true)
        if let e = entries[s.id] { e.window.makeKeyAndOrderFront(nil); return }
        let model = ChartModel(subject: s, plan: plan, tf: tf)
        if !model.hasSavedIndicators { model.indicators = [.ma20, .volume, .plan] }
        let hover = ChartHover()
        let root = ChartWindowView(model: model, hover: hover)
            .environment(\.look, settings.look)
            .environment(\.motion, settings.motion)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = s.short + " · FinanceIsland"
        w.titlebarAppearsTransparent = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 760, height: 440)
        w.contentView = NSHostingView(rootView: root.padding(.top, 26))
        w.center()
        w.setFrameAutosaveName("FinanceIslandChart")
        let entry = Entry(window: w, model: model)
        w.delegate = entry
        entry.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .keyDown, .rightMouseDown]) { [weak w] e in
            let box = EventBox(event: e)
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let w, box.event.window === w else { return false }
                return handle(box.event, window: w, model: model, hover: hover)
            }
            return handled ? nil : e
        }
        entries[s.id] = entry
        ChartWindowsState.shared.open.insert(s.id)
        w.makeKeyAndOrderFront(nil)
    }

    static func close(_ s: HubSubject) { entries[s.id]?.window.close() }

    private static func handle(_ e: NSEvent, window: NSWindow, model: ChartModel, hover: ChartHover) -> Bool {
        if e.type == .keyDown {
            switch e.keyCode {
            case 123: model.pan(bars: 5); return true
            case 124: model.pan(bars: -5); return true
            case 126: model.zoom(1.2, anchor: 1); return true
            case 125: model.zoom(1 / 1.2, anchor: 1); return true
            case 53: model.tool = .cursor; hover.draft = nil; return true
            default:
                if e.charactersIgnoringModifiers == "f" { model.fit(); return true }
                return false
            }
        }
        guard let frame = plotFrames[model.subject.id], let content = window.contentView else { return false }
        let p = CGPoint(x: e.locationInWindow.x - frame.minX, y: content.bounds.height - e.locationInWindow.y - frame.minY)
        let plotW = frame.width - TVGeo.axisW
        guard p.x >= 0, p.y >= 0, p.x <= frame.width, p.y <= frame.height else { return false }
        let anchor = Double(min(max(p.x / max(plotW, 1), 0), 1))
        if e.type == .rightMouseDown {
            let G = TVGeo(model, frame.size)
            guard p.y <= G.priceH, let last = model.candles.last?.close else { return false }
            AlertMenu.show(subject: model.subject, level: G.price(p.y), current: last, event: e, in: content)
            return true
        }
        if e.type == .magnify {
            model.zoom(1 + Double(e.magnification) * 1.5, anchor: anchor)
            return true
        }
        let dx = Double(e.scrollingDeltaX), dy = Double(e.scrollingDeltaY)
        if e.hasPreciseScrollingDeltas {
            let bw = Double(plotW) / max(model.visible, 1)
            if abs(dx) > abs(dy) { model.pan(bars: dx / bw) } else { model.zoom(exp(dy * 0.01), anchor: anchor) }
        } else {
            model.zoom(exp(dy * 0.1), anchor: anchor)
        }
        return true
    }
}

private struct DashLine: View {
    let vertical: Bool
    var body: some View {
        GeometryReader { g in
            Path { p in
                if vertical { p.move(to: CGPoint(x: 0.5, y: 0)); p.addLine(to: CGPoint(x: 0.5, y: g.size.height)) }
                else { p.move(to: CGPoint(x: 0, y: 0.5)); p.addLine(to: CGPoint(x: g.size.width, y: 0.5)) }
            }
            .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}

@MainActor
final class ChartWindowsState: ObservableObject {
    static let shared = ChartWindowsState()
    @Published var open: Set<String> = []
}

@MainActor
struct ChartToggleButton: View {
    let subject: HubSubject
    var plan: (entry: Double, stop: Double, target: Double)? = nil
    let settings: AppSettings
    @ObservedObject private var windows = ChartWindowsState.shared

    var body: some View {
        let isOpen = windows.open.contains(subject.id)
        PillLink(title: isOpen ? "Close chart" : "Open chart", symbol: isOpen ? "xmark" : "chart.xyaxis.line") {
            if isOpen { ChartWindows.close(subject) } else { ChartWindows.open(subject, plan: plan, settings: settings) }
        }
        .help(tr(isOpen ? "Close the chart window" : "A full chart in its own window: candles, timeframes, zoom, indicators and drawing tools"))
        .animation(.smooth(duration: 0.2), value: isOpen)
    }
}

private struct LiveDot: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.red).frame(width: 7, height: 7)
                .opacity(on ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            Text("LIVE").font(.system(size: 10, weight: .heavy)).foregroundStyle(.red.opacity(0.9))
        }
        .onAppear { on = true }
        .help(tr("Real-time updates"))
    }
}

private struct EventBox: @unchecked Sendable {
    let event: NSEvent
}

@MainActor
private final class AlertMenu: NSObject {
    static let shared = AlertMenu()
    private var pending: PriceAlert?

    static func show(subject: HubSubject, level: Double, current: Double, event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        let above = level >= current
        let a = PriceAlert(subject: subject.id, name: subject.short, kind: above ? .above : .below, value: level)
        if AlertStore.shared.canAdd {
            shared.pending = a
            let item = NSMenuItem(title: tr("Alert: ") + AlertStore.describe(a, format: { subject.format($0) }),
                                  action: #selector(add), keyEquivalent: "")
            item.target = shared
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: tr("Free limit of \(ProFeature.freePriceAlerts) alerts reached · Open in the bot"),
                                  action: #selector(openBot), keyEquivalent: "")
            item.target = shared
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func add() {
        if let a = pending { AlertStore.shared.add(a) }
        pending = nil
    }

    @objc private func openBot() { NSWorkspace.shared.open(DeviceIdentity.activateURL) }
}
