import SwiftUI

@MainActor
struct PaperPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var paper = PaperEngine.shared
    @ObservedObject private var desk = TradeDesk.shared
    @ObservedObject private var prefs = TradePrefs.shared
    @ObservedObject private var journal = JournalStore.shared
    @Environment(\.look) private var look
    @State private var problem: String?

    var body: some View {
        let block = paper.entryBlocked
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(tr("Paper trading")).font(.system(size: 14, weight: .bold))
                    ModeLabel(mode: paper.mode)
                    Circle().fill(paper.source.isLive ? TradeColors.profit : paper.source == .simulated ? TradeColors.loss : .white.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(tr(TradeFormat.source(paper.source))).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    Spacer()
                    Menu {
                        ForEach(PaperEngine.symbols, id: \.self) { s in Button(PaperEngine.asset(s)) { paper.setSymbol(s) } }
                    } label: {
                        Text(paper.asset).font(.system(size: 12.5, weight: .bold))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(paper.position != nil)
                }
                HStack(spacing: 14) {
                    quote("bid", paper.tick?.bid)
                    quote("ask", paper.tick?.ask)
                    if let t = paper.tick {
                        Text(tr("spread \(Fmt.number((t.ask - t.bid) / t.mid * 10_000, min: 1, max: 1)) bp"))
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    labelled("Risk, $") { number($prefs.v.risk, width: 70) }
                    labelled("SL %") { number($prefs.v.slPercent, width: 60) }
                    labelled("Reward : risk") {
                        PillPicker(options: [1.0, 1.5, 2, 3], selection: $prefs.v.rr, label: { "1 : " + String(format: "%g", $0) }, minWidth: 40)
                    }
                    Spacer(minLength: 0)
                }
                sizing
                ChecklistView(paper: true)
                if let block {
                    if block == .proLimit { ProPreview(feature: .unlimitedPaper) } else { TiltBanner(block: block) }
                }
                HStack(spacing: 8) {
                    SideButton(side: .buy, key: prefs.v.keys["long"]) { open(.buy) }
                        .disabled(block != nil || paper.tick == nil || paper.position?.side == .buy)
                    SideButton(side: .sell, key: prefs.v.keys["short"]) { open(.sell) }
                        .disabled(block != nil || paper.tick == nil || paper.position?.side == .sell)
                    if let problem { Text(tr(problem)).font(.system(size: 11.5)).foregroundStyle(TradeColors.loss).lineLimit(2) }
                    Spacer()
                    Text(tr("Hotkeys work while the island has focus"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(14)
            .background(card)

            PaperPositionCard(paper: paper)

            Text(tr("Training simulation on public Binance quotes. No orders are sent and no exchange keys are used. Fees: \(Fmt.number(prefs.v.feePercent, min: 2, max: 3))% per side."))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { paper.retain(); desk.hotkeysActive = true }
        .onDisappear { paper.release(); desk.hotkeysActive = false }
    }

    @ViewBuilder
    private var sizing: some View {
        if let p = paper.plan(side: .buy, risk: prefs.v.risk, slPercent: prefs.v.slPercent, rr: prefs.v.rr) {
            HStack(spacing: 12) {
                pair("volume", Fmt.number(p.qty, min: 0, max: 6) + " " + paper.asset)
                pair("actual risk", "$" + Fmt.number(p.actualRisk, min: 2, max: 2))
                pair("long stop", AssetFormat.price(p.stop))
                pair("target", AssetFormat.price(p.target))
                Spacer(minLength: 0)
            }
            .font(.system(size: 11).monospacedDigit())
            if p.qty == 0 {
                Text(tr("The risk is too small for the exchange's lot step."))
                    .font(.system(size: 11)).foregroundStyle(TradeColors.loss)
            }
        }
    }

    private func open(_ side: Signal) {
        switch paper.open(side: side, risk: prefs.v.risk, slPercent: prefs.v.slPercent, rr: prefs.v.rr,
                          checklist: desk.checklistCounts(paper: true)) {
        case .opened: problem = nil; desk.checked = []
        case .alreadyOpen, .blocked: problem = nil
        case .noPrice: problem = "No quote yet."
        case .tooSmall: problem = "The risk is too small for the exchange's lot step."
        }
    }

    private func quote(_ title: String, _ v: Double?) -> some View {
        HStack(spacing: 5) {
            Text(tr(title)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            Text(v.map(AssetFormat.price) ?? "—").font(.system(size: 15, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
    }

    private func pair(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(tr(title)).foregroundStyle(.white.opacity(0.45))
            Text(value).fontWeight(.semibold)
        }
        .lineLimit(1).fixedSize()
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr(title)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            content()
        }
    }

    private func number(_ value: Binding<Double>, width: CGFloat) -> some View {
        TextField("", text: Binding(
            get: { String(format: "%g", value.wrappedValue) },
            set: { if let v = Double($0.replacingOccurrences(of: ",", with: ".")), v > 0 { value.wrappedValue = v } }))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5).monospacedDigit())
            .padding(.horizontal, 9)
            .frame(width: width, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
    }

    private var card: some View {
        CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card)
    }
}
