import SwiftUI

@MainActor
struct DetailView: View {
    let asset: Asset
    @ObservedObject var state: IslandState
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @Environment(\.look) private var look

    @State private var tf: Timeframe

    init(asset: Asset, state: IslandState, rates: RateStore, settings: AppSettings) {
        self.asset = asset
        self.state = state
        self.rates = rates
        self.settings = settings
        _tf = State(initialValue: settings.defaultTimeframe)
    }
    @State private var points: [PricePoint] = []
    @State private var selection: ClosedRange<Int>?
    @State private var hoverBox = HoverIndex()
    @State private var loading = false
    @State private var failed: String?
    @State private var source: DataSource?
    @State private var note: String?
    @State private var latestOnly: Double?

    private struct Row: Identifiable {
        let id: Int
        let time: Date
        let value: Double
        let change: Double?
    }

    var body: some View {
        let values = points.map(\.value)
        let first = values.first
        let last = values.last
        let up = (last ?? 0) >= (first ?? 0)
        let color = settings.color(asset, up: up)

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CircleIconButton(symbol: "chevron.left", label: "Back") { state.mode = .home }
                AssetIcon(symbol: asset.code, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(tr(asset.code)).font(.system(size: 18, weight: .bold))
                        Text(tr(asset.name)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Text(tr(subtitle))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                ChartToggleButton(subject: .asset(asset), settings: settings)
                CircleIconButton(symbol: "gearshape", label: "Settings") { state.openSettings(.chart) }
            }

            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(tr(priceText))
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                    if let first, let last, first != 0 {
                        Text(changeText(first: first, last: last))
                            .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(color)
                    }
                }
                Spacer()
                PillPicker(options: Timeframe.allCases, selection: $tf, label: \.rawValue)
            }

            VStack(spacing: 6) {
                readout(values: values)
                    .frame(height: 22)
                HStack(spacing: 10) {
                    ZStack {
                        if values.count > 1 {
                            ChartInspector(values: values, color: color, style: settings.chartStyle,
                                           showGrid: settings.showGrid, showPoints: settings.showPoints,
                                           rangeColor: rangeColor, selection: $selection, hover: hoverBox)
                        } else if loading {
                            ProgressView().controlSize(.small)
                        } else if let failed {
                            Text(tr(failed))
                                .font(.system(size: 12.5))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 30)
                        } else if values.count < 2, latestOnly != nil || values.count == 1 {
                            Text(tr("Only the latest rate is available from \(source?.name ?? "this source")"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if values.count > 1 { PriceAxis(values: values, asset: asset).frame(width: 66) }
                }
                .frame(height: 160)
                HStack {
                    ForEach(Array(axisLabels.enumerated()), id: \.offset) { i, label in
                        if i > 0 { Spacer() }
                        Text(tr(label))
                    }
                }
                .padding(.trailing, values.count > 1 ? 76 : 0)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
                if let note, values.count > 1 {
                    Label(tr(note), systemImage: "info.circle")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
            .opacity(loading && values.count > 1 ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.2), value: loading)

            VStack(spacing: 0) {
                HStack {
                    Text(tr("TIME"))
                    Spacer()
                    Text(tr("PRICE")).frame(width: 150, alignment: .trailing)
                    Text(tr("CHANGE")).frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 4).padding(.bottom, 8)

                ForEach(rows) { row in
                    Rectangle().fill(look.theme.line).frame(height: 1)
                    HStack {
                        Text(Fmt.date(row.time, tf.tableFormat))
                        Spacer()
                        Text(Fmt.price(row.value, asset))
                            .frame(width: 150, alignment: .trailing)
                        changeCell(row.change)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.system(size: 13).monospacedDigit())
                    .padding(.horizontal, 4).padding(.vertical, 9)
                }
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(width: Layout.pageW, height: Layout.pageH, alignment: .top)
        .task(id: tf) { await load() }
        .onChange(of: tf) { _, _ in selection = nil; hoverBox.index = nil }
    }

    private func rangeColor(_ r: ClosedRange<Int>) -> Color {
        let v = points.map(\.value)
        guard v.indices.contains(r.lowerBound), v.indices.contains(r.upperBound) else { return .white }
        return settings.color(asset, up: v[r.upperBound] >= v[r.lowerBound])
    }

    @ViewBuilder
    private func readout(values: [Double]) -> some View {
        HStack(spacing: 10) {
            if let r = selection, values.indices.contains(r.lowerBound), values.indices.contains(r.upperBound) {
                let a = points[r.lowerBound], b = points[r.upperBound]
                Image(systemName: "arrow.left.and.right")
                    .foregroundStyle(.white.opacity(0.5))
                Text(Fmt.date(a.time, tf.tableFormat) + "  →  " + Fmt.date(b.time, tf.tableFormat))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 8)
                Text(Fmt.price(a.value, asset) + "  →  " + Fmt.price(b.value, asset))
                    .foregroundStyle(.white.opacity(0.75))
                if a.value != 0 {
                    Text(changeText(first: a.value, last: b.value))
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(rangeColor(r))
                        .contentTransition(.numericText())
                }
                Button { selection = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(look.theme.chip))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(tr("Clear selection"))
            } else if values.count > 1 {
                HoverReadout(box: hoverBox, points: points, asset: asset, tf: tf, settings: settings)
            } else {
                Spacer(minLength: 0)
            }
        }
        .font(.system(size: 12.5).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .animation(.easeOut(duration: 0.12), value: selection)
    }

    @ViewBuilder
    private func changeCell(_ change: Double?) -> some View {
        if let c = change {
            Text(tr(String(format: "%+.2f%%", c)))
                .foregroundStyle(settings.color(asset, up: c >= 0))
        } else {
            Text(tr("—")).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func changeText(first: Double, last: Double) -> String {
        let ch = last - first
        let pct = String(format: "%+.2f%%", ch / first * 100)
        return pct + " (" + (ch >= 0 ? "+" : "−") + Fmt.amount(abs(ch)) + ")"
    }

    private var subtitle: String {
        if asset.id == Asset.ethID, let addr = settings.walletAddress {
            var s = "Watching " + Fmt.shortAddress(addr)
            if let b = rates.ethBalance { s += " · " + Fmt.number(b, min: 2, max: 4) + " ETH" }
            return s
        }
        let from = (source ?? rates.source(asset)).map { " · " + $0.name } ?? ""
        return (asset.isFiat ? tr("Rate in \(settings.baseCurrency)") : tr("Price in USD")) + from
    }

    private var priceText: String {
        if let p = rates.quote(asset)?.price { return Fmt.price(p, asset) }
        if let p = points.last?.value { return Fmt.price(p, asset) }
        return "—"
    }

    private var axisLabels: [String] {
        guard points.count > 1 else { return [] }
        let n = 5
        return (0..<n).map { k in
            let i = (points.count - 1) * k / (n - 1)
            if k == n - 1 && tf != .all && Date().timeIntervalSince(points[i].time) < 2 * 3600 { return "Now" }
            let t = points[i].time
            if tf.axisFormat.contains("HH") && !tf.axisFormat.contains("d") && !Calendar.current.isDateInToday(t) {
                return Fmt.date(t, "d MMM HH:mm")
            }
            return Fmt.date(t, tf.axisFormat)
        }
    }

    private var rows: [Row] {
        guard points.count >= 2 else { return [] }
        let n = min(4, points.count)
        let idx = (0..<n).map { k in (points.count - 1) * k / max(n - 1, 1) }
        var out: [Row] = []
        for (k, i) in idx.enumerated() {
            let p = points[i]
            var change: Double? = nil
            if k > 0 {
                let prev = points[idx[k - 1]].value
                if prev != 0 { change = (p.value - prev) / prev * 100 }
            }
            out.append(Row(id: k, time: p.time, value: p.value, change: change))
        }
        return out.reversed()
    }

    private func load() async {
        selection = nil
        hoverBox.index = nil
        loading = true
        failed = nil
        do {
            let s = try await RatesFeed.series(asset, .timeframe(tf))
            points = s.points
            source = s.source
            note = s.note
            latestOnly = s.points.count < 2 ? s.price : nil
            if s.points.isEmpty, s.price == nil { failed = "Couldn't load data" }
        } catch {
            AppLog.write("series \(asset.code) \(tf.rawValue) failed:", error.localizedDescription)
            points = []
            note = nil
            latestOnly = nil
            failed = error.localizedDescription
        }
        loading = false
    }
}

@MainActor
struct PriceAxis: View {
    let values: [Double]
    let asset: Asset

    var body: some View {
        let lo = values.min() ?? 0, hi = values.max() ?? 0
        GeometryReader { geo in
            let pts = Sparkline.points([lo, (lo + hi) / 2, hi], in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array([hi, (lo + hi) / 2, lo].enumerated()), id: \.offset) { i, v in
                    Text(Fmt.amount(v))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(i == 1 ? 0.3 : 0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: geo.size.width, alignment: .leading)
                        .position(x: geo.size.width / 2, y: pts.isEmpty ? 0 : pts[2 - i].y)
                }
            }
        }
        .accessibilityLabel(tr("Price range \(Fmt.amount(lo)) to \(Fmt.amount(hi))"))
    }
}

@MainActor
struct ChartInspector: View {
    let values: [Double]
    let color: Color
    let style: ChartStyle
    let showGrid: Bool
    let showPoints: Bool
    let rangeColor: (ClosedRange<Int>) -> Color
    @Binding var selection: ClosedRange<Int>?
    let hover: HoverIndex
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                LineChart(values: values, color: color, style: style, showGrid: showGrid, showPoints: showPoints)

                if let r = selection {
                    let x0 = x(r.lowerBound, size), x1 = x(r.upperBound, size)
                    let c = rangeColor(r)
                    Rectangle()
                        .fill(c.opacity(0.13))
                        .frame(width: max(x1 - x0, 1), height: size.height)
                        .offset(x: x0)
                    edge(x0, size, c)
                    edge(x1, size, c)
                    marker(r.lowerBound, size, c)
                    marker(r.upperBound, size, c)
                }

                HoverMarker(box: hover, values: values, style: style, size: size, show: selection == nil || isDragging)
            }
            .contentShape(Rectangle())
            .islandHover { point in
                guard let p = point else { hover.index = nil; return }
                hover.x = p.x
                let i = index(p.x, size)
                if hover.index != i { hover.index = i }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isDragging = true
                        hover.x = v.location.x
                        let i = index(v.location.x, size)
                        if hover.index != i { hover.index = i }
                        guard abs(v.translation.width) > 3 else { return }
                        let a = index(v.startLocation.x, size), b = index(v.location.x, size)
                        if a != b { selection = min(a, b)...max(a, b) }
                    }
                    .onEnded { v in
                        isDragging = false
                        if abs(v.translation.width) <= 3 { selection = nil }
                    }
            )
        }
    }

    @State private var isDragging = false

    private func x(_ i: Int, _ size: CGSize) -> CGFloat {
        let n = values.count
        guard n > 1 else { return 0 }
        if style == .bars { return size.width * (CGFloat(i) + 0.5) / CGFloat(n) }
        return size.width * CGFloat(i) / CGFloat(n - 1)
    }

    private func index(_ px: CGFloat, _ size: CGSize) -> Int {
        let n = values.count
        guard n > 1, size.width > 0 else { return 0 }
        let t = min(max(px / size.width, 0), 1)
        let i = style == .bars ? Int(t * CGFloat(n)) : Int((t * CGFloat(n - 1)).rounded())
        return min(max(i, 0), n - 1)
    }

    private func y(_ i: Int, _ size: CGSize) -> CGFloat {
        let pts = Sparkline.points(values, in: size)
        guard pts.indices.contains(i) else { return size.height / 2 }
        return pts[i].y
    }

    private func edge(_ x: CGFloat, _ size: CGSize, _ c: Color, dashed: Bool = false) -> some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(c.opacity(dashed ? 1 : 0.7), style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : []))
    }

    private func marker(_ i: Int, _ size: CGSize, _ c: Color) -> some View {
        Circle()
            .fill(look.theme.card)
            .overlay(Circle().stroke(c, lineWidth: 2))
            .frame(width: 10, height: 10)
            .position(x: x(i, size), y: style == .bars ? size.height - 5 : y(i, size))
    }
}

@MainActor
final class HoverIndex: ObservableObject {
    @Published var index: Int? { didSet { if index == nil { x = nil } } }
    @Published var x: CGFloat?
}

@MainActor
private struct HoverReadout: View {
    @ObservedObject var box: HoverIndex
    let points: [PricePoint]
    let asset: Asset
    let tf: Timeframe
    let settings: AppSettings

    var body: some View {
        if let h = box.index, points.indices.contains(h), let first = points.first?.value {
            let p = points[h]
            Text(Fmt.date(p.time, tf.tableFormat))
                .foregroundStyle(.white.opacity(0.75))
            Text(Fmt.price(p.value, asset))
                .font(.system(size: 13, weight: .bold).monospacedDigit())
            Spacer(minLength: 8)
            if first != 0 {
                Text(tr("since start ") + String(format: "%+.2f%%", (p.value - first) / first * 100))
                    .foregroundStyle(settings.color(asset, up: p.value >= first))
            }
        } else {
            Image(systemName: "hand.draw")
                .foregroundStyle(.white.opacity(0.4))
            Text(tr("Drag across the chart to measure the change between two moments"))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
        }
    }
}

@MainActor
private struct HoverMarker: View {
    @ObservedObject var box: HoverIndex
    let values: [Double]
    let style: ChartStyle
    let size: CGSize
    let show: Bool
    @Environment(\.look) private var look

    var body: some View {
        if show, let h = box.index, values.indices.contains(h) {
            let n = values.count
            let x = n > 1 ? (style == .bars ? size.width * (CGFloat(h) + 0.5) / CGFloat(n) : size.width * CGFloat(h) / CGFloat(n - 1)) : 0
            let pts = Sparkline.points(values, in: size)
            let y = pts.indices.contains(h) ? pts[h].y : size.height / 2
            let lineX = box.x ?? x
            Path { p in p.move(to: CGPoint(x: 0.5, y: 0)); p.addLine(to: CGPoint(x: 0.5, y: size.height)) }
                .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 1, height: size.height)
                .offset(x: lineX - 0.5)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .allowsHitTesting(false)
            Circle()
                .fill(look.theme.card)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .frame(width: 10, height: 10)
                .position(x: x, y: y)
                .allowsHitTesting(false)
        }
    }
}
