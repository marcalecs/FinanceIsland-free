import AppKit
import SwiftUI

extension ProbabilityView {
    func plainHeader(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        HStack(spacing: 4) {
            Text(tr(title)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
        .frame(width: width)
    }
    func sortHeader(_ title: String, _ id: String, width: CGFloat, alignment: Alignment) -> some View {
        let on = sortKey == id
        return Button {
            withAnimation(motion.small) {
                if on { ascending.toggle() } else { sortKey = id; ascending = true }
            }
        } label: {
            HStack(spacing: 4) {
                Text(tr(title))
                    .font(.system(size: 11, weight: on ? .bold : .regular))
                    .foregroundStyle(.white.opacity(on ? 0.95 : 0.5))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: alignment)
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .opacity(on ? 1 : 0)
            }
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Sort by this column (click again to reverse)"))
    }
    func priceCell(_ text: String?, _ color: Color) -> some View {
        Text(text ?? "")
            .font(.system(size: 13, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: 88, alignment: .trailing)
            .contentTransition(.numericText())
            .animation(motion.small, value: text)
    }
    func trendColor(_ s: HubSubject, up: Bool) -> Color {
        if case .asset(let a) = s { return settings.color(a, up: up) }
        return look.pnl(up: up)
    }
    func remove(_ s: HubSubject) {
        switch s {
        case .asset(let a): settings.assetIDs.removeAll { $0 == a.id }
        case .item(let i): settings.removeItem(i.id)
        }
        if state.probDetail == s.id { state.probDetail = nil }
    }
    func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.8)
                .contentTransition(.numericText())
                .animation(motion.small, value: value)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
    }
    func legend<V: View>(_ swatch: V, _ text: String) -> some View {
        HStack(spacing: 5) { swatch.clipShape(RoundedRectangle(cornerRadius: 2)); Text(tr(text)) }
    }
    func kv(_ k: String, _ v: String, _ color: Color = .white) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(tr(k)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(v).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(motion.small, value: v)
        }
    }
    func eventRow(_ e: ProbabilityModel.Event) -> some View {
        let color = e.noSkill ? Color.white.opacity(0.22) : e.p >= e.base ? Accent.orange.color : Accent.blue.color
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(e.title)).font(.system(size: 12.5, weight: .semibold))
                    Text(tr(e.detail)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(pct(e.p)).font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white.opacity(e.noSkill ? 0.55 : 1))
                    Text(e.noSkill ? tr("as usual") : tr("usually \(pct(e.base))"))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(look.theme.chip)
                    Capsule().fill(color).frame(width: max(4, g.size.width * e.p))
                    Rectangle().fill(.white.opacity(0.85)).frame(width: 2, height: 11).offset(x: g.size.width * e.base - 1)
                }
            }
            .frame(height: 5)
        }
    }
    @ViewBuilder
    func newsCard(_ s: HubSubject) -> some View {
        let heads = news.headlines[s.id] ?? []
        let summary = news.summaries[s.id]
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("News")).font(.system(size: 14, weight: .bold))
                Spacer()
                if settings.aiProvider != .off && settings.aiConsent {
                    Button(news.summarizing.contains(s.id) ? tr("Summarising…") : summary == nil ? tr("Summarise with AI") : tr("Summarise again")) {
                        news.summarize(s, settings: settings, force: summary != nil)
                    }
                    .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(look.accent)
                    .disabled(news.summarizing.contains(s.id))
                }
            }
            if let summary {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.summary).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    ForEach(summary.points, id: \.self) { p in
                        Text("• " + p).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(tr("The AI model's reading of the news headlines · \(summary.provider), \(Fmt.date(summary.createdAt, "HH:mm")). Not a forecast or advice."))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.04)))
            } else if let e = news.errors[s.id] {
                Text(tr(e)).font(.system(size: 11.5)).foregroundStyle(look.trend.red)
            } else if settings.aiProvider == .off || !settings.aiConsent {
                Text(tr("AI news summaries are off. Turn them on in Settings ▸ Assistant."))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            if heads.isEmpty {
                Text(news.loading.contains(s.id) ? tr("Loading headlines…") : tr("No recent headlines found."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(Array(heads.prefix(5).enumerated()), id: \.offset) { i, h in
                if i > 0 { Rectangle().fill(look.theme.line).frame(height: 1) }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(i + 1). " + h.title).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    Text([h.publisher, Fmt.date(h.published, "d MMM HH:mm")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }
                .contentShape(Rectangle())
                .onTapGesture { if let u = URL(string: h.link), !h.link.isEmpty { NSWorkspace.shared.open(u) } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG)
        .onAppear { news.load(s, settings: settings) }
    }
    var estimateNote: some View {
        Text(tr("Chances are volatility-based estimates, not forecasts."))
            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
    }

    var marketHorizon: Int { 16 }

    func change24h(_ m: ProbabilityModel) -> Double? {
        guard let last = m.closes.last else { return nil }
        let cut = last.time.addingTimeInterval(-86_400)
        guard let ref = m.closes.last(where: { $0.time <= cut })?.value, ref > 0 else { return nil }
        return m.price / ref - 1
    }

    func dailyVol(_ m: ProbabilityModel) -> Double { m.sigmaNow * sqrt(max(m.barsPerDay, 1)) }

    var marketSorted: [HubSubject] {
        let base = subjects
        func key(_ s: HubSubject) -> Double? {
            guard let m = store.model(s) else { return nil }
            switch sortKey {
            case "change": return change24h(m)
            case "vol": return dailyVol(m)
            default: return nil
            }
        }
        if sortKey == "asset" {
            let a = base.sorted { $0.short.localizedCaseInsensitiveCompare($1.short) == .orderedAscending }
            return ascending ? a : a.reversed()
        }
        guard ["change", "vol"].contains(sortKey) else { return base }
        let withKey = base.compactMap { s in key(s).map { (s, $0) } }
        let without = base.filter { key($0) == nil }
        return withKey.sorted { ascending ? $0.1 < $1.1 : $0.1 > $1.1 }.map(\.0) + without
    }

    var marketPulse: some View {
        let moves = subjects.compactMap { s in store.model(s).flatMap(change24h).map { (s.short, $0) } }
        let up = moves.filter { $0.1 >= 0 }.count
        let best = moves.max { $0.1 < $1.1 }, worst = moves.min { $0.1 < $1.1 }
        return HStack(spacing: 8) {
            pulseTile(tr("Rising"), "\(up)/\(moves.count)", up * 2 >= moves.count ? look.trend.green : look.trend.red)
            pulseTile(tr("Best 24h"), best.map { $0.0 + String(format: " %+.1f%%", $0.1 * 100) } ?? "—", look.trend.green)
            pulseTile(tr("Worst 24h"), worst.map { $0.0 + String(format: " %+.1f%%", $0.1 * 100) } ?? "—", look.trend.red)
        }
    }

    func pulseTile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBG)
    }

    var marketList: some View {
        VStack(spacing: 8) {
            if !reorder.editing && subjects.count > 1 { marketPulse }
            HStack(spacing: 12) {
                sortHeader("Asset", "asset", width: 196, alignment: .leading)
                Spacer(minLength: 0)
                plainHeader("Price", width: 110, alignment: .trailing)
                sortHeader("24h", "change", width: 80, alignment: .trailing)
                sortHeader("Daily move (1σ)", "vol", width: 110, alignment: .trailing)
                Color.clear.frame(width: 8)
            }
            .padding(.horizontal, 14)
            .frame(height: 26)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            .contextMenu {
                Button(tr("Your own order")) { withAnimation(motion.small) { sortKey = "manual"; ascending = true } }
                    .disabled(sortKey == "manual")
            }
            let list = marketSorted, ids = list.map(\.id)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, s in
                marketRow(s)
                    .frame(height: Self.rowH)
                    .contextMenu {
                        Button(tr("Open chart")) { ChartWindows.open(s, settings: settings) }
                        Button(tr("Remove from the list"), role: .destructive) { remove(s) }
                    }
                    .reorderable(id: s.id, index: i, ids: ids, model: reorder,
                                 geo: ReorderGeometry(rowStride: Self.rowH + 8),
                                 onMove: { id, to in
                                     if sortKey != "manual" {
                                         orderRaw = list.map(\.id).joined(separator: "\n")
                                         sortKey = "manual"
                                     }
                                     move(id, to: to)
                                 },
                                 onHold: { withAnimation(motion.small) { reorder.editing = true } },
                                 onTap: { if !reorder.editing { select(s) } })
            }
            if reorder.editing {
                Text(tr("Drag rows to reorder · tap − to remove · Done to finish"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity).padding(.top, 2)
            }
        }
    }

    func marketRow(_ s: HubSubject) -> some View {
        let m = store.model(s)
        let ch = m.flatMap(change24h)
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                if reorder.editing && reorder.dragging == nil {
                    RemoveBadge(label: s.short) { withAnimation(motion.small) { remove(s) } }
                } else {
                    AssetIcon(symbol: s.short, size: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.short).font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(s.name == s.short ? tr(s.crypto ? "Crypto" : "Stock") : tr(s.name))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                .minimumScaleFactor(0.8)
            }
            .frame(width: 196, alignment: .leading)
            Spacer(minLength: 0)
            if m == nil {
                Group {
                    if store.isLoading(s) { ProgressView().controlSize(.small) }
                    else { Text(store.error(s).map { tr($0) } ?? "—").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).lineLimit(2) }
                }
                .frame(width: 300, alignment: .trailing)
            } else {
                Text(m.map { s.format($0.price) } ?? "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 110, alignment: .trailing)
                Text(ch.map { String(format: "%+.2f%%", $0 * 100) } ?? "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ch.map { trendColor(s, up: $0 >= 0) } ?? .white.opacity(0.5))
                    .frame(width: 80, alignment: .trailing)
                Text(m.map { String(format: "±%.2f%%", dailyVol($0) * 100) } ?? "—")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 110, alignment: .trailing)
            }
            Image(systemName: reorder.editing ? "line.3.horizontal" : "chevron.right")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(reorder.editing ? 0.6 : 0.35))
                .frame(width: 8)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(cardBG)
        .modifier(RowHover(radius: look.corners.card, fill: 0.05, stroke: 0.14, editing: reorder.editing))
    }

    func marketSubtitle(_ s: HubSubject) -> String {
        var parts: [String] = []
        if let m = store.model(s) { parts.append(s.format(m.price)) }
        if let t = store.updated(s) { parts.append(tr("updated \(Fmt.date(t, "HH:mm"))")) }
        parts.append(tr("computed on this Mac"))
        if let m = store.model(s) { parts.append(m.source.name) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    func marketDetail(_ s: HubSubject) -> some View {
        let m = store.model(s)
        HStack(alignment: .center, spacing: 10) {
            CircleIconButton(symbol: "chevron.left", label: "Back to the list") {
                withAnimation(motion.page) { state.probDetail = nil }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name == s.short ? s.short : tr(s.name) + " (\(s.short))").font(.system(size: 22, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(marketSubtitle(s)).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 8)
            ChartToggleButton(subject: s, settings: settings)
            CircleIconButton(symbol: "arrow.clockwise", label: "Refresh") { store.load(s, force: true) }
        }
        .padding(.top, 4)
        if let m {
            let h = marketHorizon
            HStack(spacing: 8) {
                stat(tr("Price"), s.format(m.price), .white)
                if let ch = change24h(m) { stat(tr("24h change"), String(format: "%+.2f%%", ch * 100), trendColor(s, up: ch >= 0)) }
                stat(tr("Daily move (1σ)"), String(format: "±%.2f%%", dailyVol(m) * 100), .white)
                stat(tr("Volatility, a year"), String(format: "%.0f%%", m.annualVolNow * 100), .white)
                stat(tr("Risk score"), "\(m.riskScore) / 100", .white)
                if let i = s.item, i.source == .yahoo, !i.symbol.contains("^"), !i.symbol.contains("="), !i.symbol.contains(".") {
                    ExtendedHoursTag(symbol: i.symbol, format: { s.format($0) })
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            let year = fiftyTwoWeekSource(s)
            FiftyTwoWeekBar(symbol: year.symbol, crypto: year.crypto, price: m.price, format: { s.format($0) })
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tr("Volatility estimate · next \(m.spanText(h))")).font(.system(size: 14, weight: .bold))
                    Spacer()
                }
                PlanChart(model: m, horizon: h, chart: ChartPlan(), format: { s.format($0, unit: false) }, onDrag: { _, _ in })
                    .frame(height: 220)
                HStack(spacing: 14) {
                    legend(Rectangle().fill(Accent.blue.color.opacity(0.4)).frame(width: 14, height: 8), "50 / 90% range")
                    legend(Rectangle().fill(Accent.orange.color.opacity(0.8)).frame(width: 14, height: 2), "SMA50")
                    Spacer()
                }
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                Text(tr("Volatility estimate, not a forecast: the band shows how far prices usually move, not where they will go."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
            .background(cardBG)
            marketEventsCard(m)
        } else {
            placeholder(store.error(s).map { tr($0) } ?? tr("Loading 15-minute prices for \(s.short)…"), failed: store.error(s) != nil)
                .frame(height: 160)
        }
        AlertsCard(subject: s, price: m?.price)
        newsCard(s)
    }

    func fiftyTwoWeekSource(_ s: HubSubject) -> (symbol: String, crypto: Bool) {
        switch s {
        case .asset(let a): return a.isFiat ? (a.yahoo, false) : (a.code, true)
        case .item(let i): return i.source == .yahoo ? (i.symbol, false) : (i.symbol.hasSuffix("USDT") ? String(i.symbol.dropLast(4)) : i.symbol, true)
        }
    }

    func marketEventsCard(_ m: ProbabilityModel) -> some View {
        let band = m.range(marketHorizon, z: 1, drift: 0)
        let events = m.events(h: marketHorizon, up: band.hi, down: band.lo)
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("Chances")).font(.system(size: 14, weight: .bold))
            Text(tr("Volatility estimate, not a forecast.")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
            ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Rectangle().fill(look.theme.line).frame(height: 1) }
                eventRow(e)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBG)
    }
}
