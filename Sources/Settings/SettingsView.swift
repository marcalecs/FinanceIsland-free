import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @Namespace private var tabNS
    @ObservedObject var state: IslandState
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CircleIconButton(symbol: "chevron.left", label: "Back") { state.closeSettings() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Settings")).font(.system(size: 17, weight: .bold))
                    Text(tr("Changes apply instantly"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button { state.closeSettings() } label: {
                    Text(tr("Done"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16).frame(height: 32)
                        .background(Capsule().fill(Color(white: 0.96)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 16) {
                sidebar
                PageScroll {
                    Group {
                        switch state.settingsTab {
                        case .profile: ProfileTab()
                        case .currencies: CurrenciesTab(rates: rates, settings: settings)
                        case .chart: ChartTab(settings: settings)
                        case .widget:
                            VStack(alignment: .leading, spacing: 16) {
                                WidgetTab(state: state, settings: settings)
                                EnergyTab(settings: settings)
                            }
                        case .assistant: AssistantSettingsTab(state: state, settings: settings)
                        case .themes: ThemesTab(settings: settings)
                        case .portfolio:
                        VStack(alignment: .leading, spacing: 16) {
                            HolderSettings(state: state)
                            WalletTab(rates: rates, settings: settings)
                        }
                        case .about:
                            VStack(alignment: .leading, spacing: 16) {
                                AboutTab(state: state, settings: settings)
                                LogsTab()
                            }
                        }
                    }
                    .id(state.settingsTab)
                    .transition(.opacity.animation(motion.small))
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.never)
                .verticalOnly()
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(width: Layout.pageW, height: RenderFlags.noScroll ? nil : Layout.pageH, alignment: .top)
        .onExitCommand { state.closeSettings() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { t in
                let on = state.settingsTab == t
                Button { state.settingsTab = t } label: {
                    HStack(spacing: 8) {
                        Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                        Text(tr(t.rawValue)).font(.system(size: 12.5, weight: on ? .semibold : .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background {
                        if on { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.selected).matchedGeometryEffect(id: "tab", in: tabNS) }
                    }
                    .foregroundStyle(.white.opacity(on ? 1 : 0.62))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr(t.rawValue))
            }
        }
        .frame(width: 150)
        .animation(motion.enabled ? .spring(response: 0.32 * motion.speed.factor, dampingFraction: 0.86) : nil, value: state.settingsTab)
    }

}

@MainActor
struct SettingsSection<Content: View>: View {
    @Environment(\.look) private var look
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(title).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
        .padding(.top, 10)
    }
}

@MainActor
struct Row<Control: View>: View {
    @Environment(\.look) private var look
    let title: String
    var subtitle: String? = nil
    var divider = true
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(title)).font(.system(size: 13.5))
                    if let subtitle {
                        Text(tr(subtitle)).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 8)
                control
            }
            .padding(.vertical, 9)
            if divider { Rectangle().fill(look.theme.line).frame(height: 1) }
        }
    }
}

@MainActor
private struct GlassSlider: View {
    @Environment(\.look) private var look
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { g in
            let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(look.theme.selected).frame(height: 6)
                Capsule().fill(look.accent).frame(width: max(6, g.size.width * f), height: 6)
                Circle().fill(.white).frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: (g.size.width - 18) * f)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let k = min(max(d.location.x / max(g.size.width, 1), 0), 1)
                value = range.lowerBound + k * (range.upperBound - range.lowerBound)
            })
        }
        .frame(height: 24)
    }
}

struct Switch: View {
    @Environment(\.look) private var look
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? look.accent : look.theme.selected)
                Circle().fill(.white).padding(2.5)
            }
            .frame(width: 40, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

@MainActor
private struct Field: View {
    @Environment(\.look) private var look
    let placeholder: String
    @Binding var text: String
    var mono = false
    var error = false
    var pasteButton = false
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, design: mono ? .monospaced : .default))
            if pasteButton {
                Button {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        text = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } label: {
                    Label(tr("Paste"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9).frame(height: 24)
                        .background(Capsule().fill(look.theme.chip))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .help(tr("Paste from the clipboard"))
            }
        }
            .padding(.leading, 12).padding(.trailing, pasteButton ? 6 : 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.island))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(error ? look.trend.red : Color.white.opacity(0.14)))
            .onSubmit(onSubmit)
    }
}

@MainActor
private struct CurrenciesTab: View {
    @Environment(\.look) private var look
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @State private var query = ""
    @StateObject private var reorder = ReorderModel()

    static let rowHeight: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "In your widget · \(settings.assetIDs.count) · hold and drag to reorder") {
                if settings.assetIDs.isEmpty {
                    Text(tr("Nothing yet. Pick currencies below."))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                let ids = settings.assetIDs
                ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                    let a = settings.asset(id: id)
                    let sameAsBase = a.isFiat && a.code == settings.baseCurrency
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(reorder.dragging == id ? 0.9 : 0.35))
                            .frame(width: 16)
                        Row(title: a.code + "  ·  " + tr(a.name),
                            subtitle: sameAsBase ? "Hidden: same as base currency" : priceLine(a),
                            divider: i < ids.count - 1 && reorder.dragging == nil) {
                            HStack(spacing: 4) {
                                Text(tr("\(i + 1)"))
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.35))
                                    .frame(minWidth: 18)
                                smallButton("arrow.up.to.line", "Move to top", disabled: i == 0) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { settings.moveToTop(id) }
                                }
                                smallButton("xmark", "Remove") {
                                    withAnimation(.easeOut(duration: 0.2)) { settings.toggle(id) }
                                }
                            }
                        }
                    }
                    .frame(height: Self.rowHeight)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(reorder.dragging == id ? look.theme.chip : .clear))
                    .contentShape(Rectangle())
                    .reorderable(id: id, index: i, ids: ids, model: reorder, geo: ReorderGeometry(rowStride: Self.rowHeight),
                                 onMove: { settings.move($0, to: $1) })
                    .contextMenu {
                        Button(tr("Move to Top")) { settings.moveToTop(id) }.disabled(i == 0)
                        Button(tr("Move to Bottom")) { settings.moveToBottom(id) }.disabled(i == ids.count - 1)
                        Divider()
                        Button(tr("Remove")) { settings.toggle(id) }
                    }
                }
            }

            SettingsSection(title: "Data sources") {
                Row(title: "Currencies", subtitle: sourceNote(settings.fiatSource, .fiat)) {
                    sourcePicker($settings.fiatSource, DataSource.fiatChain)
                }
                Row(title: "Crypto", subtitle: sourceNote(settings.cryptoSource, .crypto), divider: false) {
                    sourcePicker($settings.cryptoSource, DataSource.cryptoChain)
                }
            }

            SettingsSection(title: "Fiat rates are shown in") {
                Row(title: "Base currency", subtitle: "Each card shows what 1 unit costs in \(settings.baseCurrency)", divider: false) {
                    PillPicker(options: Catalog.bases, selection: $settings.baseCurrency,
                               label: { Catalog.symbol($0) == $0 ? $0 : Catalog.symbol($0) }, minWidth: 30)
                }
            }

            SettingsSection(title: "Add currencies") {
                VStack(alignment: .leading, spacing: 12) {
                    Field(placeholder: "Search or type any code (SEK, DOT…)", text: $query) { addTyped() }
                        .padding(.top, 10)
                    if showCustom {
                        HStack(spacing: 8) {
                            customButton("Add \(typed) as currency", kind: .fiat).disabled(typed.count != 3)
                            customButton("Add \(typed) as crypto", kind: .crypto)
                        }
                    }
                    group("Currencies", Catalog.fiat)
                    group("Crypto · in USD", Catalog.crypto)
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var typed: String { query.trimmingCharacters(in: .whitespaces).uppercased() }

    private var showCustom: Bool {
        !typed.isEmpty && !(Catalog.fiat + Catalog.crypto).contains { $0.code == typed }
    }

    private func matches(_ e: CatalogEntry) -> Bool {
        typed.isEmpty || e.code.contains(typed) || e.name.uppercased().contains(typed)
    }

    private func addTyped() {
        if let exact = (Catalog.fiat + Catalog.crypto).first(where: { $0.code == typed }) {
            if !settings.contains(exact.id) { settings.toggle(exact.id) }
            query = ""
        }
    }

    private func priceLine(_ a: Asset) -> String {
        guard let q = rates.quote(a) else { return a.isFiat ? tr("In \(settings.baseCurrency)") : tr("In USD") }
        return Fmt.price(q.price, a) + String(format: "  %@%.2f%%", q.isUp ? "▲ " : "▼ ", abs(q.pct))
    }

    @ViewBuilder
    private func group(_ title: String, _ entries: [CatalogEntry]) -> some View {
        let shown = entries.filter(matches)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr(title)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                    ForEach(shown) { e in chip(e) }
                }
            }
        }
    }

    private func chip(_ e: CatalogEntry) -> some View {
        let on = settings.contains(e.id)
        let isBase = e.kind == .fiat && e.code == settings.baseCurrency
        return Button { settings.toggle(e.id) } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(on ? look.accent : .white.opacity(0.5))
                Text(tr(e.code)).font(.system(size: 12.5, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(on ? look.theme.selected : look.theme.chip))
            .contentShape(Capsule())
            .opacity(isBase ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isBase)
        .help(e.name)
    }

    private func customButton(_ title: String, kind: AssetKind) -> some View {
        Button {
            if settings.addCustom(typed, kind: kind) != nil { query = "" }
        } label: {
            Label(tr(title), systemImage: "plus")
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(look.theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sourceNote(_ s: DataSource?, _ kind: InstrumentKind) -> String {
        let chain = SourcePrefs.chain(kind)
        let order = (s.map { [$0] } ?? []) + chain.filter { $0 != s }
        return tr(s?.note ?? "Automatic") + tr(" · then ") + order.dropFirst().map { tr($0.name) }.joined(separator: " → ")
    }

    private func sourcePicker(_ b: Binding<DataSource?>, _ options: [DataSource]) -> some View {
        Picker("", selection: b) {
            Text(tr("Automatic")).tag(DataSource?.none)
            Divider()
            ForEach(options) { Text($0.name).tag(DataSource?.some($0)) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 160, alignment: .trailing)
    }

    private func smallButton(_ symbol: String, _ label: String, disabled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(look.theme.chip))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(label)
    }
}

@MainActor
private struct ChartTab: View {
    @Environment(\.look) private var look
    @ObservedObject var settings: AppSettings

    private static let sample: [Double] = [3, 4.2, 3.6, 5.1, 4.4, 6, 5.2, 6.8, 6.1, 7.4, 6.9, 8.2]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Chart style") {
                HStack(spacing: 8) {
                    ForEach(ChartStyle.allCases) { s in
                        let on = settings.chartStyle == s
                        Button { settings.chartStyle = s } label: {
                            VStack(spacing: 8) {
                                Sparkline(values: Self.sample, color: on ? look.accent : Color(white: 0.5), style: s)
                                    .frame(height: 42)
                                Text(tr(s.rawValue)).font(.system(size: 12.5, weight: .semibold))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? look.theme.chip : look.theme.island))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(on ? look.accent.opacity(0.7) : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 10)
            }

            SettingsSection(title: "Detail chart") {
                Row(title: "Grid lines") { Switch(isOn: $settings.showGrid) }
                Row(title: "Data points", subtitle: "Dots along the line") { Switch(isOn: $settings.showPoints) }
                Row(title: "Opens on", subtitle: "Timeframe when you click a card", divider: false) {
                    PillPicker(options: Timeframe.allCases, selection: $settings.defaultTimeframe, label: \.rawValue)
                }
            }

            SettingsSection(title: "Cards") {
                Row(title: "When a fiat rate rises", subtitle: "Crypto going up is always green", divider: false) {
                    PillPicker(options: [false, true], selection: $settings.riseIsRed,
                               label: { $0 ? tr("Red · \(settings.baseCurrency) weaker") : tr("Green") })
                }
            }
        }
    }
}

@MainActor
private struct WidgetTab: View {
    @Environment(\.look) private var look
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @ObservedObject private var idle = IdlePrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Where the island lives") {
                Row(title: "Menu bar icon instead",
                    subtitle: "For Macs where NotchNook, DynamicLake or Boring Notch already use the notch: click the icon to open the island") {
                    Switch(isOn: $settings.menuBarMode)
                }
                if settings.menuBarMode {
                    Row(title: "Next to the icon", subtitle: "Up to three values; an open trade always comes first") {
                        HStack(spacing: 4) {
                            ForEach(IdlePrefsValues.Pin.allCases, id: \.self) { p in
                                let on = idle.v.pins.contains(p)
                                Button {
                                    if on { idle.v.pins.removeAll { $0 == p } } else if idle.v.pins.count < 3 { idle.v.pins.append(p) }
                                } label: {
                                    Text(tr(p.rawValue)).font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(on ? 1 : 0.6))
                                        .padding(.horizontal, 10).frame(height: 26)
                                        .background(Capsule().fill(on ? look.theme.selected : look.theme.chip))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Row(title: "Screen", subtitle: "Without a notch the island sits at the top centre, as tall as the menu bar", divider: false) {
                    Picker("", selection: $settings.islandScreen) {
                        Text(tr("Automatic")).tag("auto")
                        Text(tr("Screen with the pointer")).tag("cursor")
                        Divider()
                        ForEach(NSScreen.screens, id: \.self) { s in Text(s.localizedName).tag(displayID(s)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                    .disabled(settings.menuBarMode)
                }
            }

            SettingsSection(title: "Under the notch") {
                Row(title: "Ticker tape", subtitle: "Scrolls your quotes and the portfolio's day P&L when nothing else is shown; pauses under the pointer") {
                    Switch(isOn: $idle.v.tape)
                }
                if idle.v.tape {
                    Row(title: "Tape speed") {
                        PillPicker(options: IdlePrefsValues.Speed.allCases, selection: $idle.v.speed, label: \.rawValue)
                    }
                    Row(title: "Quotes from the widget") { Switch(isOn: $idle.v.tapeQuotes) }
                    Row(title: "Portfolio P&L today") { Switch(isOn: $idle.v.tapePnL) }
                }
                Row(title: "Collapsed island shows", subtitle: idle.v.tape ? "First quote when the tape is off" : "Visible when you first hover the notch", divider: false) {
                    Picker("", selection: pillBinding) {
                        ForEach(settings.assets) { a in Text(tr(a.code)).tag(Optional(a.id)) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 110)
                    .disabled(settings.assets.isEmpty)
                }
            }

            SettingsSection(title: "Data") {
                Row(title: "Refresh every", divider: false) {
                    PillPicker(options: [5, 15, 30, 60], selection: $settings.refreshMinutes, label: { "\($0) min" })
                }
            }

            SettingsSection(title: "Motion") {
                Row(title: "Animation style", subtitle: "How the island opens, closes and resizes") {
                    PillPicker(options: MotionStyle.allCases, selection: $settings.motionStyle, label: \.rawValue)
                }
                Row(title: "Speed") {
                    PillPicker(options: MotionSpeed.allCases, selection: $settings.motionSpeed, label: \.rawValue)
                        .disabled(!settings.motion.enabled)
                        .opacity(settings.motion.enabled ? 1 : 0.4)
                }
                Row(title: "Draw charts in", subtitle: "Charts sweep in from the left when they load") {
                    Switch(isOn: $settings.animateCharts)
                }
                Row(title: "Open overview on hover", subtitle: "Skip the small pill under the notch") {
                    Switch(isOn: $settings.expandOnHover)
                }
                Row(title: "Open the island", subtitle: settings.openByClick ? "Click the notch area; hovering does nothing" : "Hover the notch area") {
                    PillPicker(options: [false, true], selection: $settings.openByClick, label: { $0 ? "By click" : "By hover" }, minWidth: 70)
                }
                Row(title: "Opening delay", subtitle: "The pointer must rest at the notch this long, so passing by opens nothing", divider: false) {
                    HStack(spacing: 10) {
                        GlassSlider(value: Binding(get: { settings.openDelayMs }, set: { settings.openDelayMs = ($0 / 10).rounded() * 10 }),
                                    range: 0...600)
                            .frame(width: 140)
                        Text(tr("\(Int(settings.openDelayMs)) ms")).font(.system(size: 12).monospacedDigit()).frame(width: 52, alignment: .trailing)
                    }
                    .disabled(settings.openByClick)
                    .opacity(settings.openByClick ? 0.4 : 1)
                }
                if settings.reduceMotion {
                    Text(tr("Reduce motion is on in System Settings: the island, the ticker tape and charts don't animate."))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.bottom, 8)
                }
            }
        }
    }

    private var pillBinding: Binding<String?> {
        Binding(get: { settings.pillAsset?.id }, set: { settings.pillAssetID = $0 })
    }
}

@MainActor
private struct EnergyTab: View {
    @Environment(\.look) private var look
    @ObservedObject var settings: AppSettings
    @ObservedObject private var power = PowerState.shared

    var body: some View {
        let effective = settings.effectiveEnergy
        let base = settings.requestsPerHour(.normal)
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Energy mode") {
                HStack(spacing: 8) {
                    ForEach(EnergyMode.allCases) { m in modeTile(m, base: base) }
                }
                .padding(.vertical, 12)
            }

            SettingsSection(title: "Automatic") {
                Row(title: "Low power on battery", subtitle: "Switches to Low power while the Mac is unplugged") {
                    Switch(isOn: $settings.energyOnBattery)
                }
                Row(title: "Follow macOS Low Power Mode", subtitle: "Uses Low power whenever macOS saves energy", divider: false) {
                    Switch(isOn: $settings.energyFollowSystem)
                }
            }

            SettingsSection(title: "Now") {
                Row(title: tr("In use: \(tr(effective.title))"),
                    subtitle: settings.energyReason.map { tr("Because \(tr($0))") } ?? power.status,
                    divider: false) {
                    Image(systemName: effective.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(color(effective))
                }
            }

            SettingsSection(title: "What changes") {
                HStack(spacing: 6) {
                    Spacer()
                    ForEach(EnergyMode.allCases) { m in
                        Text(tr(m.title))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(width: 92, alignment: .trailing)
                    }
                }
                .padding(.top, 8)
                detail("Currency cards refresh", { m in
                    tr("every \(Int(Double(max(settings.refreshMinutes, 1)) * m.slowdown)) min")
                })
                detail("Signals refresh", { _ in tr("every 15 s while the Scalping tab is open") })
                detail("AI engine", { m in m == .normal ? tr("daily") : m == .balanced ? tr("daily, plugged in") : tr("manual only") })
                detail("Animations", { m in m.animations ? tr("on") : tr("off") }, divider: false)
            }
        }
    }

    private func color(_ m: EnergyMode) -> Color {
        switch m {
        case .normal: return look.accent
        case .balanced: return Accent.yellow.color
        case .low: return look.trend.green
        }
    }

    private func modeTile(_ m: EnergyMode, base: Double) -> some View {
        let on = settings.energyMode == m
        let share = base > 0 ? settings.requestsPerHour(m) / base : 1
        return Button { settings.energyMode = m } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: m.symbol).foregroundStyle(color(m))
                    Text(tr(m.title)).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(look.accent) }
                }
                Text(tr(m.summary))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                PercentBar(value: share * 100, color: color(m))
                Text(tr("≈ \(max(Int((share * 100).rounded()), 1))% of normal activity"))
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? look.theme.selected : look.theme.island))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(on ? color(m).opacity(0.8) : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func detail(_ title: String, _ value: @escaping (EnergyMode) -> String, divider: Bool = true) -> some View {
        Row(title: title, divider: divider) {
            HStack(spacing: 6) {
                ForEach(EnergyMode.allCases) { m in
                    Text(value(m))
                        .font(.system(size: 11, weight: settings.effectiveEnergy == m ? .bold : .regular))
                        .foregroundStyle(.white.opacity(settings.effectiveEnergy == m ? 0.95 : 0.45))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 92, alignment: .trailing)
                }
            }
        }
    }
}

extension PowerState {
    var status: String {
        var parts: [String] = [tr(onBattery ? tr("On battery") : tr("Plugged in"))]
        if let b = batteryPercent { parts.append("\(b)%") }
        if systemLowPower { parts.append(tr("macOS Low Power Mode on")) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
private struct WalletTab: View {
    @Environment(\.look) private var look
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @State private var address = ""
    @State private var error: String?
    @ObservedObject private var portfolio = PortfolioStore.shared
    @State private var newChain: Chain = .btc
    @State private var newAddress = ""
    @State private var newLabel = ""
    @State private var walletError: String?
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var connecting = false
    @State private var accountError: String?
    @State private var solanaRPC = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            totalSection
            SettingsSection(title: settings.walletAddress == nil ? tr("Guest mode") : tr("Watching")) {
                VStack(alignment: .leading, spacing: 10) {
                    if let addr = settings.walletAddress {
                        HStack(spacing: 10) {
                            EthGlyph()
                            Text(Fmt.shortAddress(addr)).font(.system(size: 13).monospacedDigit())
                            Spacer()
                            if let b = rates.ethBalance {
                                Text(Fmt.number(b, min: 2, max: 4) + " ETH")
                                    .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                            }
                        }
                    } else {
                        Text(tr("All currencies work without a wallet. Add a public address to also see your ETH balance."))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 12)
            }

            SettingsSection(title: "Public wallet address") {
                VStack(alignment: .leading, spacing: 10) {
                    Field(placeholder: "0x…", text: $address, mono: true, error: error != nil, pasteButton: true) { watch() }
                    Text(tr(error ?? "Read-only. Nothing to sign, no keys ever leave your Mac."))
                        .font(.system(size: 12))
                        .foregroundStyle(error == nil ? Color.white.opacity(0.5) : look.trend.red)
                    HStack(spacing: 8) {
                        Button { watch() } label: {
                            Label(settings.walletAddress == nil ? tr("Watch wallet") : tr("Update"), systemImage: "wallet.pass")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16).frame(height: 32)
                                .background(Capsule().fill(Color(white: 0.96)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        if settings.walletAddress != nil {
                            Button { remove() } label: {
                                Text(tr("Remove wallet"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(look.trend.red)
                                    .padding(.horizontal, 16).frame(height: 32)
                                    .background(Capsule().fill(look.theme.chip))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            walletsSection
            tokensSection
            accountsSection
        }
        .onAppear {
            address = settings.walletAddress ?? ""
            portfolio.refresh()
        }
    }

    private var tokensSection: some View {
        SettingsSection(title: "Tokens") {
            Row(title: "ERC-20, SPL and TON tokens", subtitle: "Found automatically for watched Ethereum, Solana and TON addresses through public services; only tokens with a price, worth $1 or more") {
                EmptyView()
            }
            Row(title: "Own Solana RPC (optional)",
                subtitle: "The free public Solana node is rate-limited. Paste an RPC URL with your key (e.g. Helius); it is stored in the Keychain.",
                divider: false) {
                SecureField("https://", text: $solanaRPC)
                    .textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
                    .padding(.horizontal, 10).frame(width: 220, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                    .onSubmit { AccountKeychain.set("solana.rpc", solanaRPC.trimmingCharacters(in: .whitespaces)); portfolio.refresh() }
                    .onAppear { solanaRPC = AccountKeychain.get("solana.rpc") ?? "" }
            }
        }
    }

    private var totalSection: some View {
        let eth = (rates.ethBalance ?? 0) * (portfolio.prices[.eth] ?? 0)
        let total = portfolio.totalUSD + eth
        return SettingsSection(title: "Portfolio") {
            Row(title: "$" + Fmt.number(total, min: 2, max: 2),
                subtitle: tr("Wallets and accounts together, in US dollars") + (portfolio.updated.map { " · " + Fmt.date($0, "HH:mm") } ?? ""),
                divider: false) {
                PillButton(title: portfolio.loading ? "Updating…" : "Refresh") { portfolio.refresh(); rates.walletChanged() }
            }
        }
    }

    private var walletsSection: some View {
        SettingsSection(title: "More wallets (watch-only)") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(portfolio.wallets) { w in
                    HStack(spacing: 10) {
                        Text(w.chain.symbol).font(.system(size: 10.5, weight: .heavy))
                            .frame(width: 38, height: 22)
                            .background(Capsule().fill(look.theme.selected))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.label).font(.system(size: 13, weight: .semibold))
                            Text(Fmt.shortAddress(w.address)).font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            if let b = portfolio.balances[w.id] {
                                Text(Fmt.number(b, min: 2, max: 6) + " " + w.chain.symbol)
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                if let u = portfolio.usd(w) {
                                    Text("$" + Fmt.number(u, min: 2, max: 2)).font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            } else if let e = portfolio.errors[w.id] {
                                Text(tr(e)).font(.system(size: 11.5)).foregroundStyle(look.trend.red)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        Button { withAnimation(.smooth(duration: 0.2)) { portfolio.remove(w) } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                .frame(width: 22, height: 22).background(Circle().fill(look.theme.chip)).contentShape(Circle())
                        }
                        .buttonStyle(PressStyle())
                        .help(tr("Stop watching this wallet"))
                    }
                }
                PillPicker(options: Chain.allCases, selection: $newChain, label: { $0.name }, minWidth: 60)
                HStack(spacing: 8) {
                    Field(placeholder: newChain.placeholder, text: $newAddress, mono: true, error: walletError != nil, pasteButton: true) { addWallet() }
                    Field(placeholder: tr("Name (optional)"), text: $newLabel).frame(width: 150)
                }
                if newChain == .ton {
                    Text(tr("Address from Wallet in Telegram: Wallet ▸ TON wallet ▸ Receive. Tokens such as USDT on TON show up on their own."))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
                Text(walletError ?? tr("Public addresses only: the app reads balances and can never move funds."))
                    .font(.system(size: 12))
                    .foregroundStyle(walletError == nil ? Color.white.opacity(0.5) : look.trend.red)
                PillButton(title: "Add wallet") { addWallet() }
            }
            .padding(.vertical, 12)
        }
    }

    private func addWallet() {
        let a = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newChain.isValid(a) else {
            walletError = tr("That doesn't look like a \(newChain.name) address.")
            return
        }
        guard !portfolio.wallets.contains(where: { $0.chain == newChain && $0.address == a }) else {
            walletError = tr("This wallet is already on the list.")
            return
        }
        walletError = nil
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        withAnimation(.smooth(duration: 0.2)) { portfolio.add(newChain, a, label: label.isEmpty && newChain == .ton ? "Wallet" : label) }
        newAddress = ""; newLabel = ""
    }

    private var accountsSection: some View {
        SettingsSection(title: "Accounts") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("B").font(.system(size: 13, weight: .heavy)).foregroundStyle(.black)
                        .frame(width: 26, height: 26).background(Circle().fill(Color(red: 0.95, green: 0.73, blue: 0.18)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Binance").font(.system(size: 13.5, weight: .semibold))
                        Text(portfolio.binanceConnected ? tr("Signed in · read-only key") : tr("Not signed in"))
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    if portfolio.binanceConnected {
                        Text("$" + Fmt.number(portfolio.binanceUSD, min: 2, max: 2))
                            .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                        PillButton(title: "Sign out", destructive: true) { portfolio.disconnectBinance() }
                    }
                }
                if portfolio.binanceConnected {
                    if let e = portfolio.binanceError {
                        Text(tr(e)).font(.system(size: 12)).foregroundStyle(look.trend.red)
                    }
                    ForEach(portfolio.binanceHoldings.prefix(10)) { h in
                        HStack {
                            Text(h.asset).font(.system(size: 12.5, weight: .semibold)).frame(width: 70, alignment: .leading)
                            Text(Fmt.number(h.amount, min: 2, max: 8)).font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            Text(h.usd.map { "$" + Fmt.number($0, min: 2, max: 2) } ?? "—")
                                .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                } else {
                    Field(placeholder: tr("API key"), text: $apiKey, mono: true, pasteButton: true)
                    HStack(spacing: 6) {
                        SecureField(tr("Secret key"), text: $apiSecret)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5).monospacedDigit())
                        Button {
                            if let s = NSPasteboard.general.string(forType: .string) { apiSecret = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                        } label: {
                            Label(tr("Paste"), systemImage: "doc.on.clipboard")
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 9).frame(height: 24)
                                .background(Capsule().fill(look.theme.chip))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                        .padding(.leading, 12).padding(.trailing, 6).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.island))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.14)))
                    Text(accountError ?? tr("Create a key in Binance ▸ API Management with only “Enable Reading”. Keys that can trade or withdraw are refused. The key stays in this Mac's Keychain."))
                        .font(.system(size: 12))
                        .foregroundStyle(accountError == nil ? Color.white.opacity(0.5) : look.trend.red)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        PillButton(title: connecting ? "Checking the key…" : "Sign in with API key") { connect() }
                            .disabled(connecting || apiKey.isEmpty || apiSecret.isEmpty)
                        Spacer()
                    }
                }
                Rectangle().fill(look.theme.line).frame(height: 1).padding(.vertical, 4)
                WalletAccountRow()
            }
            .padding(.vertical, 12)
        }
    }

    private func connect() {
        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines), s = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        connecting = true
        accountError = nil
        Task {
            let e = await portfolio.connectBinance(key: k, secret: s)
            connecting = false
            if let e { accountError = e } else { apiKey = ""; apiSecret = "" }
        }
    }

    private func watch() {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppSettings.isValidAddress(a) else {
            error = "That doesn't look like an Ethereum address (0x + 40 hex characters)."
            return
        }
        error = nil
        settings.walletAddress = a
        rates.walletChanged()
    }

    private func remove() {
        settings.walletAddress = nil
        address = ""
        error = nil
        rates.walletChanged()
    }
}

@MainActor
private struct ThemesTab: View {
    @Environment(\.look) private var look
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Island") {
                glassButton
                    .padding(.top, 12)
                if settings.liquidGlass {
                    Row(title: "Transparency", subtitle: "How much of the desktop shows through the glass") {
                        HStack(spacing: 10) {
                            GlassSlider(value: $settings.glassTransparency, range: 0.1...0.9)
                                .frame(width: 180)
                            Text(String(format: "%.0f%%", settings.glassTransparency * 100))
                                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(Theme.all) { t in themeTile(t) }
                }
                .padding(.vertical, 12)
            }

            SettingsSection(title: "Accent colour") {
                Row(title: "Switches, checkmarks, highlights", divider: false) {
                    HStack(spacing: 8) {
                        ForEach(Accent.allCases) { a in
                            let on = settings.accent == a
                            Button { settings.accent = a } label: {
                                Circle().fill(a.color)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(.white, lineWidth: on ? 2 : 0).padding(-3))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(PressStyle())
                            .accessibilityLabel(a.rawValue)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }

            SettingsSection(title: "Rising & falling") {
                HStack(spacing: 10) {
                    ForEach(TrendPalette.all) { p in
                        let on = settings.trendID == p.id
                        Button { settings.trendID = p.id } label: {
                            HStack(spacing: 8) {
                                Text(tr("▲")).foregroundStyle(p.green)
                                Text(tr("▼")).foregroundStyle(p.red)
                                Text(tr(p.name)).font(.system(size: 12.5, weight: .semibold))
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(on ? look.theme.selected : look.theme.chip))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(on ? look.accent.opacity(0.8) : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.vertical, 12)
            }

            SettingsSection(title: "Shape") {
                Row(title: "Corners", subtitle: "Island and card roundness", divider: false) {
                    PillPicker(options: Corners.allCases, selection: $settings.corners, label: \.rawValue)
                }
            }
        }
    }

    private var glassButton: some View {
        let on = settings.liquidGlass
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { settings.liquidGlass.toggle() } label: {
            HStack(spacing: 14) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.45, blue: 0.95), Color(red: 0.55, green: 0.3, blue: 0.85),
                                            Color(red: 0.95, green: 0.55, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    GlassBackground(shape: shape, tint: Color.black.opacity(0.25))
                        .frame(width: 46, height: 30)
                        .overlay(Capsule().fill(Color.white.opacity(0.5)).frame(width: 22, height: 4))
                }
                .frame(width: 70, height: 46)
                .clipShape(shape)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("Liquid Glass")).font(.system(size: 14, weight: .semibold))
                    Text(tr(settings.reduceTransparency ? "Reduce transparency is on in System Settings: the island uses the solid theme"
                            : on ? "On · the theme colour tints the glass" : "Translucent island that shows your desktop through it"))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Switch(isOn: $settings.liquidGlass)
                    .allowsHitTesting(false)
            }
            .padding(10)
            .background(shape.fill(on ? look.theme.selected : look.theme.chip))
            .overlay(shape.stroke(on ? look.accent.opacity(0.8) : .clear, lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
    }

    private func themeTile(_ base: Theme) -> some View {
        let on = settings.themeID == base.id
        let t = settings.liquidGlass ? Theme.glass(over: base, transparency: settings.glassTransparency) : base
        return Button { settings.themeID = base.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 5) {
                    HStack(spacing: 5) {
                        Capsule().fill(t.chip).frame(width: 34, height: 8)
                        Spacer()
                        Circle().fill(t.chip).frame(width: 8, height: 8)
                    }
                    HStack(spacing: 5) {
                        ForEach(0..<3) { i in
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(t.card)
                                .overlay(alignment: .bottom) {
                                    Sparkline(values: [3, 4, 3.5, 5, 4.6, 6].map { $0 + Double(i) },
                                              color: i == 1 ? settings.look.trend.red : settings.look.trend.green,
                                              style: .line)
                                        .frame(height: 12).padding(4)
                                }
                        }
                    }
                }
                .padding(8)
                .frame(height: 70)
                .background(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 12,
                                                                      bottomTrailing: 12, topTrailing: 0))
                    .fill(t.island))
                .overlay(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 12,
                                                                   bottomTrailing: 12, topTrailing: 0))
                    .stroke(Color.white.opacity(0.08)))
                Text(tr(t.name)).font(.system(size: 12.5, weight: .semibold))
                    .padding(.leading, 2)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? look.theme.selected.opacity(0.6) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(on ? look.accent.opacity(0.8) : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

@MainActor
private struct AboutTab: View {
    @Environment(\.look) private var look
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @State private var showTerms = false
    @State private var confirmWithdraw = false
    @AppStorage("signalAlerts") private var alerts = true
    @State private var dataMessage: String?

    private func exportData() {
        dataMessage = DataVault.runExport() ? tr("Exported") : nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LicenseSection()

            SettingsSection(title: "FinanceIsland · app \(AppInfo.version) · terms \(Legal.termsVersion)") {
                Row(title: Legal.disclaimer) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 16, weight: .semibold)).foregroundStyle(Accent.orange.color)
                }
                Row(title: "No custody: FinanceIsland never holds funds, seed phrases or private keys. Wallets are watch-only; a Binance key is accepted only read-only and stays in the Keychain. Wallet in Telegram is read only from files you place in the Inbox.") {
                    Image(systemName: "lock.shield").font(.system(size: 16, weight: .semibold)).foregroundStyle(look.accent)
                }
                Row(title: "Live currency and crypto rates under your notch",
                    subtitle: "Data: Yahoo Finance · Binance · Coinbase · Kraken · CoinGecko · Nasdaq · Federal Reserve (FRED) · ECB · ExchangeRate-API · CBOE · US Treasury · Ethereum public nodes · optional AI provider", divider: false) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(look.accent)
                }
            }

            SettingsSection(title: "Author") {
                Row(title: "Made by marcalecs", subtitle: "© 2026 marcalecs. All rights reserved.", divider: false) {
                    Image(systemName: "signature")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(look.accent)
                }
            }


            SettingsSection(title: "Language") {
                Row(title: "Interface language", subtitle: "Switches instantly. Reports and AI answers stay in English.", divider: false) {
                    Picker("", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
            }

            SettingsSection(title: "User agreement") {
                Row(title: "Accepted version \(settings.acceptedTermsVersion ?? "—")",
                    subtitle: settings.acceptedAt.map { "On " + Fmt.date($0, "d MMMM yyyy, HH:mm") }) {
                    PillButton(title: showTerms ? tr("Hide") : tr("Read")) { showTerms.toggle() }
                }
                if showTerms {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr(Legal.agreementTitle)).font(.system(size: 13.5, weight: .bold))
                        ForEach(Legal.agreement) { termsSection($0) }
                        Text(tr(Legal.consentTitle)).font(.system(size: 13.5, weight: .bold)).padding(.top, 6)
                        ForEach(Legal.consent) { termsSection($0) }
                    }
                    .textSelection(.enabled)
                    .padding(.vertical, 12)
                    .transition(.opacity)
                    Rectangle().fill(look.theme.line).frame(height: 1)
                }
                Row(title: "Withdraw consent",
                    subtitle: confirmWithdraw
                        ? tr("Deletes everything: portfolio, journal, wallets, settings and all backups. This cannot be undone. Export first if you want a copy. Click Confirm to erase.")
                        : tr("Erase all stored data and return to the welcome screen"),
                    divider: false) {
                    HStack(spacing: 6) {
                        if confirmWithdraw { PillButton(title: tr("Export first")) { exportData() } }
                        PillButton(title: confirmWithdraw ? tr("Confirm") : tr("Withdraw"), destructive: true) {
                            if confirmWithdraw { state.onWithdrawConsent?() } else { askConfirm() }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showTerms)

            SettingsSection(title: "Your data") {
                Row(title: "Export portfolio and journal", subtitle: "One JSON file with your Long-Term positions, entry prices and journal") {
                    PillButton(title: tr("Export…")) { exportData() }
                }
                Row(title: "Import from a file", subtitle: "Replaces the current portfolio and journal. A backup of the current data is kept.") {
                    PillButton(title: tr("Import…")) { dataMessage = DataVault.runImport().map(tr) }
                }
                Row(title: "Automatic backups", subtitle: "Saved at launch, at most every 15 minutes while you edit, and before an import: the last 5 copies, one a day for 10 days, one a week for 5 weeks", divider: dataMessage == nil) {
                    PillButton(title: tr("Show")) { DataVault.revealBackups() }
                }
                if let dataMessage {
                    Text(dataMessage).font(.system(size: 11.5)).foregroundStyle(look.accent).padding(.vertical, 8)
                }
            }

            SettingsSection(title: "App") {
                Row(title: "Replay welcome tour", subtitle: "Language, product tour, wallet, mode and storage") {
                    PillButton(title: "Replay") { state.onReplayOnboarding?() }
                }
                Row(title: "Reset appearance", subtitle: "Default theme, layout, chart and motion. Keeps your currencies.") {
                    PillButton(title: "Reset") { settings.resetLook() }
                }
                Row(title: "Quit FinanceIsland", divider: false) {
                    PillButton(title: "Quit", destructive: true) { NSApp.terminate(nil) }
                }
            }
        }
    }

    private func askConfirm() {
        confirmWithdraw = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { confirmWithdraw = false }
    }

    private func termsSection(_ s: Legal.Section) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tr(s.title)).font(.system(size: 12, weight: .semibold))
            Text(Legal.rich(tr(s.body)))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
struct PillButton: View {
    @Environment(\.look) private var look
    let title: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tr(title))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(destructive ? look.trend.red : .white)
                .padding(.horizontal, 14).frame(height: 28)
                .background(Capsule().fill(look.theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

@MainActor
private struct AssistantSettingsTab: View {
    @Environment(\.look) private var look
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @State private var key = ""
    @State private var model = ""
    @State private var test: String?
    @State private var testing = false
    @AppStorage("journalOneR") private var oneR = 0.0
    @State private var pendingProvider: AIProvider?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Journal") {
                Row(title: "Value of 1R", subtitle: "Your usual risk per trade, in \(settings.baseCurrency). Empty: the journal shows results in R only.", divider: false) {
                    TextField(tr("not set"), text: Binding(
                        get: { oneR > 0 ? String(format: "%g", oneR) : "" },
                        set: { oneR = Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0 }))
                        .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 10).frame(width: 110, height: 28)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(look.theme.chip))
                }
            }
            TradingSettings(settings: settings)


            SettingsSection(title: "AI news summary") {
                Row(title: "Provider", subtitle: settings.aiProvider == .off ? "Off: the asset page shows the headlines only" : settings.aiProvider.note) {
                    Picker("", selection: Binding(get: { settings.aiConsent ? settings.aiProvider : AIProvider.off },
                                                  set: { p in
                                                      if p == .off { settings.aiProvider = .off; pendingProvider = nil }
                                                      else if settings.aiConsent { settings.aiProvider = p }
                                                      else { pendingProvider = p }
                                                  })) {
                        ForEach(AIProvider.allCases) { Text($0 == .off ? tr("Off") : $0.name).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 170)
                }
                if let p = pendingProvider {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("What leaves your Mac")).font(.system(size: 13, weight: .semibold))
                        Text(tr("When you ask for a news summary, FinanceIsland sends the asset's name and its latest headlines (title, publisher, date) to \(p.name). Nothing else: no portfolio, wallets, exchange keys, journal or settings. With Ollama the request stays on this Mac."))
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            PillButton(title: tr("Allow and turn on")) {
                                settings.aiConsent = true
                                settings.aiProvider = p
                                pendingProvider = nil
                            }
                            PillButton(title: tr("Cancel")) { pendingProvider = nil }
                        }
                    }
                    .padding(.vertical, 10)
                    Rectangle().fill(look.theme.line).frame(height: 1)
                }
                if settings.aiProvider != .off {
                    Row(title: "Model", subtitle: "Default: \(settings.aiProvider.defaultModel)") {
                        Field(placeholder: settings.aiProvider.defaultModel, text: $model) { saveModel() }
                            .frame(width: 230)
                    }
                }
                if settings.aiProvider.needsKey {
                    Row(title: "API key", subtitle: "Stored in the macOS Keychain, sent only to \(settings.aiProvider.name)") {
                        SecureField(tr("paste key"), text: $key)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13).monospacedDigit())
                            .padding(.horizontal, 12)
                            .frame(width: 230, height: 32)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.island))
                            .onSubmit { saveKey() }
                    }
                }
                Row(title: "Summarise automatically", subtitle: "When an asset page opens (summaries are cached for 1 hour)") {
                    Switch(isOn: $settings.aiAutoInsight)
                }
                Row(title: test ?? "Check the connection", divider: false) {
                    PillButton(title: testing ? tr("Testing…") : tr("Test")) { runTest() }
                        .disabled(testing || settings.aiProvider == .off)
                }
            }


            SettingsSection(title: "Data sources") {
                Row(title: "Crypto", subtitle: tr(settings.cryptoSource?.note ?? "Automatic") + tr(" · falls back to Binance, Coinbase, Kraken, Yahoo")) {
                    sourcePicker($settings.cryptoSource, DataSource.cryptoChain)
                }
                Row(title: "Stocks", subtitle: tr(settings.stockSource?.note ?? "Automatic") + tr(" · falls back to Yahoo, then Nasdaq for daily candles"), divider: false) {
                    sourcePicker($settings.stockSource, DataSource.stockChain)
                }
            }

        }
        .onAppear(perform: load)
        .onChange(of: settings.aiProvider) { _, _ in load(); test = nil }
        .onDisappear { saveKey(); saveModel() }
    }

    private func sourcePicker(_ b: Binding<DataSource?>, _ options: [DataSource]) -> some View {
        Picker("", selection: b) {
            Text(tr("Automatic")).tag(DataSource?.none)
            Divider()
            ForEach(options) { Text($0.name).tag(DataSource?.some($0)) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 160, alignment: .trailing)
    }

    private func load() {
        key = Keychain.get(settings.aiProvider.rawValue) ?? ""
        model = settings.aiModels[settings.aiProvider.rawValue] ?? ""
    }

    private func saveKey() {
        guard settings.aiProvider.needsKey else { return }
        Keychain.set(settings.aiProvider.rawValue, key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveModel() {
        let m = model.trimmingCharacters(in: .whitespaces)
        settings.aiModels[settings.aiProvider.rawValue] = m.isEmpty ? nil : m
    }

    private func runTest() {
        saveKey(); saveModel()
        testing = true
        test = nil
        let p = settings.aiProvider, m = settings.aiModel, k = p.needsKey ? Keychain.get(p.rawValue) : nil
        Task {
            do {
                let r = try await AIClient.complete(provider: p, model: m, key: k,
                                                    system: "Reply with the single word OK.", user: "ping")
                test = "Connected: \(p.name) answered “\(r.prefix(20).trimmingCharacters(in: .whitespacesAndNewlines))”"
            } catch {
                test = "Failed: " + error.localizedDescription
            }
            testing = false
        }
    }
}

@MainActor
private struct LogsTab: View {
    @Environment(\.look) private var look
    @AppStorage("logEnabled") private var logEnabled = true
    @State private var sizes: [String: Int64] = [:]
    @State private var lines: [String] = []
    @State private var confirmClear = false

    private struct Place: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let urls: [URL]
        var reveal: URL { urls[0] }
    }

    private var places: [Place] {
        let db = URL(fileURLWithPath: AssistantDatabase.defaultPath())
        let list: [Place] = [
            Place(id: "log", title: "App log", subtitle: "Errors and events · rotates at 2 MB",
                  urls: [AppLog.file, AppLog.previous]),
            Place(id: "db", title: "Assistant database", subtitle: "Candle history and cached news (SQLite)",
                  urls: [db, URL(fileURLWithPath: db.path + "-wal"), URL(fileURLWithPath: db.path + "-shm")]),
            Place(id: "journal", title: "Trader's journal", subtitle: "Your notes and trades",
                  urls: [JournalStore.fileURL]),
        ]
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "App log") {
                Row(title: "Keep an app log", subtitle: "Writes errors and events to a file on this Mac. Nothing is sent anywhere.") {
                    Switch(isOn: $logEnabled)
                }
                Row(title: "Log folder", subtitle: tildePath(AppLog.folder)) {
                    PillButton(title: "Show in Finder") { reveal(AppLog.file, folder: AppLog.folder) }
                }
                Row(title: tr("Captured: \(AppLog.format(sizes["log"] ?? 0))"),
                    subtitle: "Clearing moves the log files to the Trash", divider: !lines.isEmpty) {
                    HStack(spacing: 6) {
                        PillButton(title: "Refresh") { refresh() }
                        PillButton(title: confirmClear ? "Clear?" : "Clear log", destructive: true) {
                            if confirmClear { AppLog.clear { MainActor.assumeIsolated { refresh() } }; confirmClear = false } else { confirmClear = true }
                        }
                    }
                }
                if !lines.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                            Text(l).font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.vertical, 10)
                }
            }

            SettingsSection(title: tr("Captured data · \(AppLog.format(sizes.values.reduce(0, +)))")) {
                let ps = places
                ForEach(ps) { p in
                    Row(title: p.title, subtitle: tr(p.subtitle) + " · " + tildePath(p.reveal), divider: p.id != ps.last?.id) {
                        HStack(spacing: 10) {
                            Text(AppLog.format(sizes[p.id] ?? 0))
                                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                            Button { reveal(p.reveal, folder: p.reveal.deletingLastPathComponent()) } label: {
                                Image(systemName: "folder")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(look.theme.chip))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(PressStyle())
                            .help(tr("Show in Finder"))
                        }
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: logEnabled) { _, on in
            if on { AppLog.write("App log turned on") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { refresh() }
        }
    }

    private func refresh() {
        let ps = places.map { ($0.id, $0.urls) }
        DispatchQueue.global(qos: .utility).async {
            var s: [String: Int64] = [:]
            for (id, urls) in ps { s[id] = urls.reduce(0) { $0 + AppLog.size(of: $1) } }
            let t = AppLog.tail(8)
            DispatchQueue.main.async { sizes = s; lines = t }
        }
    }

    private func tildePath(_ u: URL) -> String {
        u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func reveal(_ url: URL, folder: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }
}

@MainActor
private struct LicenseSection: View {
    @ObservedObject private var store = LicenseStore.shared
    @Environment(\.look) private var look
    @State private var text = ""
    @State private var problem: String?
    @State private var copied = false

    var body: some View {
        SettingsSection(title: "FinanceIsland Pro") {
            Row(title: "Code of this Mac", subtitle: "Send it to the bot to get a licence for this Mac. One subscription covers up to 2 Macs; manage them with /devices in the bot.") {
                HStack(spacing: 6) {
                    Text(DeviceIdentity.displayCode).font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .textSelection(.enabled)
                    PillButton(title: copied ? tr("Copied") : tr("Copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(DeviceIdentity.displayCode, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                    PillButton(title: tr("Open the bot")) { NSWorkspace.shared.open(DeviceIdentity.activateURL) }
                }
            }
            if let l = store.license, store.isActive {
                Row(title: tr("Pro is active · plan \(l.plan)"),
                    subtitle: store.inGrace
                        ? tr("Ended \(Fmt.date(l.exp, "d MMM yyyy")): 3 days of grace, renew in the bot")
                        : tr("Valid until \(Fmt.date(l.exp, "d MMM yyyy")) · works offline")) {
                    HStack(spacing: 6) {
                        PillButton(title: tr("Renew in the bot")) { NSWorkspace.shared.open(DeviceIdentity.activateURL) }
                        PillButton(title: tr("Remove"), destructive: true) { store.remove() }
                    }
                }
            } else {
                if let p = store.problem, store.license != nil {
                    Row(title: tr(p.errorDescription ?? ""), subtitle: "Paste a new licence from the bot") {
                        PillButton(title: tr("Renew in the bot")) { NSWorkspace.shared.open(DeviceIdentity.activateURL) }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("Licence")).font(.system(size: 13.5))
                    HStack(spacing: 8) {
                        TextField("FI1.…", text: $text)
                            .textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
                            .onSubmit(install)
                        PillButton(title: tr("Activate")) { install() }
                    }
                    if let problem {
                        Text(tr(problem)).font(.system(size: 11.5)).foregroundStyle(look.trend.red)
                    }
                    Text(tr("Pro: ") + ProFeature.allCases.map { tr($0.title) }.joined(separator: " · "))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 10)
            }
        }
    }

    private func install() {
        do {
            try store.install(text)
            text = ""
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}
