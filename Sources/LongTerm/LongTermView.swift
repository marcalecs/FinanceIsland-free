import SwiftUI

@MainActor
struct LongTermView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = LongTermStore.shared
    @ObservedObject private var portfolio = PortfolioStore.shared
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @State private var editing: String?
    @State private var entryText = ""
    @State private var expanded: Set<String> = []
    @State private var adding = false
    @State private var problem: String?
    @State private var query = ""
    @State private var remote: [CatalogItem] = []
    @State private var picked: CatalogItem?
    @State private var newAmount = ""
    @State private var newEntry = ""
    @State private var entryEdited = false
    @State private var newDate = Date()
    @State private var datePreset = "now"
    @State private var marketAtDate: Double?
    @State private var resolving = false
    @State private var amountInUSD = false
    @AppStorage("ltPnlWithFX") private var withFX = false
    @AppStorage("ltFilter") private var filter = "All"

    private var holdings: [Holding] { store.holdings(settings: settings, rates: rates) }
    private var totalValue: Double { holdings.compactMap { store.valueUSD($0) }.reduce(0, +) }
    private var base: String { settings.baseCurrency }
    private func inBase(_ usd: Double) -> String {
        store.fromUSD(usd, to: base).map { LongTermStore.money($0, base) } ?? LongTermStore.money(usd, "USD")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PageTitle(tab: .longTerm)
                Spacer()
                PillLink(title: adding ? "Close" : "Add position", symbol: adding ? "xmark" : "plus") {
                    withAnimation(motion.small) { adding.toggle(); problem = nil }
                }
                CircleIconButton(symbol: "wallet.bifold", label: "Wallets and exchange accounts") { state.mode = .wallet }
                CircleIconButton(symbol: "arrow.clockwise", label: "Refresh") { refreshAll() }
                    .hoverLift()
                CircleIconButton(symbol: "gearshape", label: "Settings") { state.openSettings(.portfolio) }
                    .hoverLift()
                    .rotationEffect(.degrees(store.loading ? 360 : 0))
                    .animation(store.loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.loading)
            }
            .frame(height: 34)

            PageScroll {
                VStack(alignment: .leading, spacing: 12) {
                    WeeklySummaryCard(holdings: holdings, base: base)
                    summary
                    SmartEntryField(placeholder: "bought 10 NVDA at 131 · add 0.5 BTC")
                    if adding { addForm.transition(.opacity.combined(with: .move(edge: .top))) }
                    if holdings.isEmpty {
                        empty
                    } else {
                        allocation
                        VStack(spacing: 6) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { i, h in row(h) }
                        }
                        .animation(motion.small, value: filter)
                        BenchmarkCard(holdings: holdings)
                        PortfolioNewsCard(holdings: holdings)
                        DividendsCard(symbols: Array(Set(holdings.filter { !$0.crypto }.map(\.symbol))).sorted())
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
            .verticalOnly()

            if let r = store.lastRemoved {
                UndoBar(text: "Position removed", since: r.at) { withAnimation(motion.small) { store.undoRemove() } }
            }
            FooterNote(text: tr("Rule checks compare your entry price with the daily momentum trend.") + " " + tr(Legal.disclaimer))
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .frame(width: Layout.pageW, height: RenderFlags.noScroll ? nil : Layout.bodyH, alignment: .top)
        .onAppear(perform: refreshAll)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                store.refresh(holdings, base: base)
            }
        }
        .onChange(of: holdings.map(\.symbol)) { _, _ in store.refresh(holdings, base: base) }
        .onChange(of: store.updated) { _, _ in MoveAlerts.check(holdings, store: store) }
    }

    private var filtered: [Holding] {
        let list = holdings.sorted { (store.valueUSD($0) ?? 0) > (store.valueUSD($1) ?? 0) }
        switch filter {
        case "Stocks": return list.filter { !$0.crypto }
        case "Crypto": return list.filter(\.crypto)
        default: return list
        }
    }

    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow]

    private var allocation: some View {
        let parts = holdings.compactMap { h in store.valueUSD(h).map { (ItemNames.short(h.symbol, name: ItemNames.name(h.symbol)), $0) } }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let total = max(parts.map(\.1).reduce(0, +), 1)
        let shown = Array(parts.prefix(6)) + (parts.count > 6 ? [(tr("Other"), parts.dropFirst(6).map(\.1).reduce(0, +))] : [])
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Allocation")).font(.system(size: 12, weight: .bold))
                Spacer()
                PillPicker(options: ["All", "Stocks", "Crypto"], selection: $filter, label: { $0 }, minWidth: 34)
                    .scaleEffect(0.9, anchor: .trailing)
            }
            GeometryReader { g in
                HStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                        Self.palette[i % Self.palette.count].opacity(0.85)
                            .frame(width: max(2, (g.size.width - CGFloat(shown.count - 1) * 2) * p.1 / total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack(spacing: 12) {
                ForEach(Array(shown.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 4) {
                        Circle().fill(Self.palette[i % Self.palette.count]).frame(width: 6, height: 6)
                        Text(p.0).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(String(format: "%.0f%%", p.1 / total * 100)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(card)
    }

    private func refreshAll() {
        portfolio.refresh()
        rates.walletChanged()
        store.refresh(holdings, base: base)
    }

    private var summary: some View {
        let hs = holdings
        let value = totalValue
        let parts = hs.compactMap { store.pnl($0, base: base) }
        let cost = parts.map(\.cost).reduce(0, +)
        let local = parts.map(\.local).reduce(0, +), total = parts.map(\.total).reduce(0, +)
        let fxPart = total - local
        let pnl = withFX ? total : local
        let approx = parts.contains { $0.approx } ? "≈ " : ""
        let money = { (v: Double) in LongTermStore.money(v, base) }
        let signed = { (v: Double) in (v >= 0 ? "+" : "−") + money(abs(v)) }
        let hasFX = abs(fxPart) > 0.005 || parts.contains { $0.approx }
        return HStack(spacing: 10) {
            tile(tr("Portfolio value"), inBase(value), .white)
            tile(tr("Invested (with entry)"), cost > 0 ? approx + money(cost) : "—", .white)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(withFX ? tr("Profit / loss with currency") : tr("Profit / loss of the assets"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if hasFX {
                        Button(withFX ? tr("Assets only") : tr("With FX")) { withAnimation(motion.small) { withFX.toggle() } }
                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(look.accent)
                    }
                }
                Text(cost > 0 ? String(format: "%@%@ · %+.2f%%", approx, signed(pnl), pnl / cost * 100) : "—")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(cost == 0 ? .white : look.pnl(pnl))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                if cost > 0 && hasFX {
                    Text(withFX ? tr("of which currency: \(signed(fxPart))") : tr("currency adds \(signed(fxPart))"))
                        .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
        }
    }

    private func tile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(size: 17, weight: .bold).monospacedDigit()).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var card: some View {
        CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card)
    }

    private func row(_ h: Holding) -> some View {
        let price = store.prices[h.symbol]
        let entry = store.entry(for: h)
        let cur = store.currency(h.symbol)
        let pnl: Double? = { guard let p = price, let e = entry, e > 0 else { return nil }; return (p - e) * h.amount }()
        let pct: Double? = { guard let p = price, let e = entry, e > 0 else { return nil }; return p / e - 1 }()
        let day = store.change24h[h.symbol]
        let value = store.valueUSD(h)
        let smart = store.smart(for: h, total: totalValue, count: holdings.count)
        let open = expanded.contains(h.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(motion.small) { if open { expanded.remove(h.id) } else { expanded.insert(h.id) } } } label: {
                HStack(spacing: 12) {
                    AssetIcon(symbol: h.symbol, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(ItemNames.short(h.symbol, name: ItemNames.name(h.symbol))).font(.system(size: 13.5, weight: .bold))
                            if h.origin != .manual {
                                Text(tr(h.origin.rawValue)).font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5).frame(height: 15)
                                    .background(Capsule().fill(look.theme.selected))
                            }
                            if smart?.overweight == true {
                                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundStyle(look.trend.red)
                                    .help(tr("Over-concentrated: more than 40% of the portfolio in one asset"))
                            }
                        }
                        Text(Fmt.number(h.amount, min: 0, max: 6) + " · " + h.label)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price.map { LongTermStore.money($0, cur) } ?? "—")
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                            .contentTransition(.numericText())
                        Text(day.map { String(format: "%+.2f%%", $0) } ?? " ")
                            .font(.system(size: 10.5, weight: .semibold).monospacedDigit()).foregroundStyle(look.pnl(day ?? 0))
                    }
                    .frame(width: 92, alignment: .trailing)
                    Group {
                        if let v = store.history[h.id], v.count > 1 {
                            Sparkline(values: v, color: look.pnl(up: (v.last ?? 0) >= (v.first ?? 0)), style: .line)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                    Text(value.map(inBase) ?? "—")
                        .font(.system(size: 13, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(width: 96, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let pnl, let pct {
                            Text((pnl >= 0 ? "+" : "−") + LongTermStore.money(abs(pnl), cur))
                                .font(.system(size: 12.5, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                            Text(String(format: "%+.2f%%", pct * 100)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        } else {
                            Text(tr("set entry")).font(.system(size: 11, weight: .semibold)).foregroundStyle(look.accent)
                        }
                    }
                    .foregroundStyle(look.pnl(pnl ?? 0))
                    .frame(width: 92, alignment: .trailing)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(tr("Entry")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        if editing == h.id {
                            TextField("0.00", text: $entryText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .frame(width: 90)
                                .padding(.horizontal, 6).frame(height: 24)
                                .background(RoundedRectangle(cornerRadius: 6).fill(look.theme.chip))
                                .onSubmit { commitEntry(h) }
                        } else {
                            Button {
                                editing = h.id
                                entryText = entry.map { String(format: "%g", $0) } ?? ""
                            } label: {
                                HStack(spacing: 4) {
                                    Text(entry.map { LongTermStore.money($0, cur) } ?? tr("set"))
                                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(entry == nil ? look.accent : .white)
                                    Image(systemName: "pencil").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .buttonStyle(.plain)
                            .help(tr("Your buy-in price per unit"))
                        }
                        if let d = store.entryDate(for: h) {
                            Text(tr("Held for \(heldFor(d))")).font(.system(size: 11, weight: .medium)).foregroundStyle(look.accent.opacity(0.9))
                        }
                        if cur != base, let b = store.pnl(h, base: base) {
                            Text((b.approx ? "≈ " : "") + (b.total >= 0 ? "+" : "−") + LongTermStore.money(abs(b.total), base) + " " + tr("with FX"))
                                .font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if h.origin == .manual {
                            Button { withAnimation(motion.small) { store.remove(h) } } label: {
                                Image(systemName: "trash").font(.system(size: 10, weight: .semibold))
                                    .frame(width: 24, height: 24).background(Circle().fill(look.theme.chip)).contentShape(Circle())
                            }
                            .buttonStyle(PressStyle())
                            .help(tr("Remove this position"))
                        }
                    }
                    if let smart {
                        HStack(spacing: 8) {
                            chip(tr(smart.health.rawValue), healthColor(smart.health))
                            chip(String(format: "%.0f%% ", smart.weight * 100) + tr("of portfolio"), smart.overweight ? look.trend.red : .white.opacity(0.7))
                                .help(smart.overweight ? tr("Over-concentrated: more than 40% of the portfolio in one asset") : tr("Share of the portfolio's value"))
                            if let adv = store.advice(for: h) { chip(tr(adv.rule), adviceColor(adv.action)) }
                        }
                        Text(smart.directive).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        controlPanel(h, smart)
                    }
                }
                .padding(.leading, 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(card)
        .overlay(RoundedRectangle(cornerRadius: look.corners.card, style: .continuous)
            .stroke(smart?.overweight == true ? look.trend.red.opacity(0.35) : .clear))
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10.5, weight: .bold)).foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.14)))
    }

    private func healthColor(_ h: SmartControl.Health) -> Color {
        switch h {
        case .accumulation: return Accent.blue.color
        case .healthy: return look.trend.green
        case .overheated: return Accent.orange.color
        case .drawdown: return look.trend.red
        case .developing: return .white.opacity(0.7)
        }
    }

    private func adviceColor(_ a: LongTermAdvice.Action) -> Color {
        switch a {
        case .buy: return look.trend.green
        case .hold: return Accent.orange.color
        case .sell: return look.trend.red
        }
    }

    private func controlPanel(_ h: Holding, _ s: SmartControl) -> some View {
        let cur = store.currency(h.symbol)
        let f = { (v: Double) in LongTermStore.money(v, cur) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("Entry time")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                DatePicker("", selection: Binding(get: { store.entryDate(for: h) ?? Date() },
                                                  set: { store.setEntryDate($0, for: h) }),
                           in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field).frame(width: 170)
                PillLink(title: "Use market price then", symbol: "clock.arrow.circlepath") {
                    guard let d = store.entryDate(for: h) else { return }
                    Task { if let p = await LongTermStore.historicalPrice(symbol: h.symbol, crypto: h.crypto, at: d) { store.setEntry(p, for: h) } }
                }
                .help(tr("Fill the entry price with the market price at that moment"))
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Staged take-profit")).font(.system(size: 11.5, weight: .bold))
                    if s.tiers.isEmpty {
                        Text(tr("Set an entry price to see the levels")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(s.tiers) { t in
                        HStack(spacing: 6) {
                            Image(systemName: t.reached ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10)).foregroundStyle(t.reached ? look.trend.green : .white.opacity(0.4))
                            Text("TP\(t.id) " + String(format: "(+%.0f%%)", t.gain * 100)).font(.system(size: 11, weight: .semibold))
                            Text(f(t.price)).font(.system(size: 11).monospacedDigit()).foregroundStyle(look.trend.green)
                            Text(tr(t.action)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Buy-more (DCA) zone")).font(.system(size: 11.5, weight: .bold))
                    Text(f(s.dca.low) + " – " + f(s.dca.high)).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Accent.blue.color)
                    ForEach(s.dca.previews, id: \.share) { pv in
                        HStack(spacing: 4) {
                            Text(String(format: "+%.0f%%", pv.share * 100)).font(.system(size: 10.5, weight: .semibold))
                                .frame(width: 40, alignment: .leading)
                            Text(tr("new average")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                            Text(f(pv.average)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Trailing stop")).font(.system(size: 11.5, weight: .bold))
                    Text(f(s.trailingStop)).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(look.trend.red)
                    if let p = store.prices[h.symbol] {
                        Text(String(format: "%.1f%% ", (s.trailingStop / p - 1) * 100) + tr("from the price"))
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                    }
                    Text(tr("Two typical weekly moves below the price; at +50% it never drops under your entry."))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.05)))
            }
        }
    }

    private func commitEntry(_ h: Holding) {
        let v = Double(entryText.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
        store.setEntry(v.flatMap { $0 > 0 ? $0 : nil }, for: h)
        editing = nil
    }

    private var suggestions: [CatalogItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, picked?.symbol != q.uppercased() else { return [] }
        var out = SearchCatalog.search(q)
        for r in remote where !out.contains(where: { $0.symbol == r.symbol }) { out.append(r) }
        return Array(out.prefix(6))
    }

    private var quickChips: [CatalogItem] {
        let trending = ["BTC", "ETH", "SOL", "TON", "BNB", "XRP"]
        var syms = holdings.map(\.symbol)
        for t in trending where !syms.contains(t) { syms.append(t) }
        var seen = Set<String>()
        return syms.compactMap { s in
            guard seen.insert(s).inserted else { return nil }
            return SearchCatalog.items.first { $0.symbol == s } ?? CatalogItem(symbol: s, name: s, kind: .crypto)
        }
        .prefix(9).map { $0 }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("New position")).font(.system(size: 14, weight: .bold))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                TextField(tr("Ticker, name or category: BTC, Bitcoin, gold…"), text: $query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .onChange(of: query) { _, q in if picked != nil && q.uppercased() != picked?.symbol { picked = nil } }
                    .task(id: query) {
                        remote = []
                        let q = query.trimmingCharacters(in: .whitespaces)
                        guard q.count >= 2 else { return }
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        let found = await SearchCatalog.yahoo(q)
                        if !Task.isCancelled { remote = found }
                    }
                if let p = picked { AssetIcon(symbol: p.symbol, size: 22) }
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(look.theme.chip))
            if !suggestions.isEmpty {
                VStack(spacing: 2) {
                    ForEach(suggestions) { c in
                        Button { pick(c) } label: { suggestionRow(c) }.buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.35)))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickChips) { c in
                        Button { pick(c) } label: {
                            HStack(spacing: 5) {
                                AssetIcon(symbol: c.symbol, size: 16)
                                Text(c.symbol).font(.system(size: 11.5, weight: .semibold))
                            }
                            .padding(.horizontal, 8).frame(height: 26)
                            .background(Capsule().fill(picked?.id == c.id ? look.theme.selected : look.theme.chip))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    PillPicker(options: [false, true], selection: $amountInUSD, label: { $0 ? "$" : "Units" }, minWidth: 34)
                    field(amountInUSD ? tr("$ invested") : tr("Amount"), $newAmount, width: 100)
                }
                VStack(alignment: .leading, spacing: 4) {
                    PillPicker(options: ["now", "1W", "1M", "1Y"], selection: $datePreset,
                               label: { $0 == "now" ? "Now" : $0 }, minWidth: 34)
                    DatePicker("", selection: $newDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden().datePickerStyle(.field)
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField(tr("Entry price"), text: $newEntry)
                        .textFieldStyle(.plain).font(.system(size: 13).monospacedDigit())
                        .padding(.horizontal, 10).frame(width: 120, height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
                        .onChange(of: newEntry) { _, v in if v != autoText { entryEdited = true } }
                    if resolving {
                        ProgressView().controlSize(.mini)
                    } else if let m = marketAtDate {
                        let mine = num(newEntry)
                        Text(tr("market then") + " $" + Fmt.number(m, min: 2, max: 4)
                             + (mine.map { $0 != m ? String(format: " · %+.2f%%", ($0 / m - 1) * 100) : "" } ?? ""))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
                Spacer()
                PillLink(title: "Add", symbol: "checkmark") { addPosition() }
            }
            .onChange(of: datePreset) { _, p in
                let day = 86_400.0
                switch p {
                case "1W": newDate = Date().addingTimeInterval(-7 * day)
                case "1M": newDate = Date().addingTimeInterval(-30 * day)
                case "3M": newDate = Date().addingTimeInterval(-91 * day)
                case "1Y": newDate = Date().addingTimeInterval(-365 * day)
                default: newDate = Date()
                }
            }
            .onChange(of: newDate) { _, _ in resolvePrice() }
            .onChange(of: picked?.id) { _, _ in resolvePrice() }
            if let problem { Text(tr(problem)).font(.system(size: 11.5)).foregroundStyle(look.trend.red) }
        }
        .padding(14)
        .background(card)
    }

    @State private var autoText = ""

    private func suggestionRow(_ c: CatalogItem) -> some View {
        let q = store.quotes[c.id]
        return HStack(spacing: 10) {
            AssetIcon(symbol: c.symbol, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(ItemNames.short(c.symbol, name: c.name)).font(.system(size: 12.5, weight: .bold))
                Text(c.name + " · " + tr(c.kind.rawValue)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer()
            if let q, q.price > 0 {
                Text(LongTermStore.money(q.price, q.currency)).font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                if let ch = q.change {
                    Text(String(format: "%+.2f%%", ch)).font(.system(size: 10.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(look.pnl(ch))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 4).fill((look.pnl(ch)).opacity(0.14)))
                }
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.horizontal, 8).frame(height: 38)
        .contentShape(Rectangle())
        .onAppear { store.loadQuote(c) }
    }

    private func pick(_ c: CatalogItem) {
        picked = c
        query = c.symbol
        remote = []
        store.loadQuote(c)
    }

    private func num(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private func resolvePrice() {
        guard let c = picked else { return }
        let crypto = c.kind == .crypto, t = newDate
        resolving = true
        Task {
            let p: Double?
            if Date().timeIntervalSince(t) < 120 {
                if store.quotes[c.id] == nil || store.quotes[c.id]?.price == 0 { store.loadQuote(c) }
                try? await Task.sleep(nanoseconds: 600_000_000)
                p = store.quotes[c.id].flatMap { $0.price > 0 ? $0.price : nil }
            } else {
                p = await LongTermStore.historicalPrice(symbol: c.symbol, crypto: crypto, at: t)
            }
            resolving = false
            marketAtDate = p
            if let p, !entryEdited {
                autoText = String(format: p >= 100 ? "%.2f" : "%.6g", p)
                newEntry = autoText
            }
        }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, width: CGFloat) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13).monospacedDigit())
            .padding(.horizontal, 10)
            .frame(width: width, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
    }

    private func addPosition() {
        let sym = (picked?.symbol ?? query).trimmingCharacters(in: .whitespaces).uppercased()
        guard !sym.isEmpty else { problem = "Enter a ticker."; return }
        guard let typed = num(newAmount), typed > 0 else { problem = "Enter how much you hold."; return }
        let entryPrice = num(newEntry).flatMap { $0 > 0 ? $0 : nil }
        if amountInUSD && entryPrice == nil { problem = "Set the entry price to turn the dollar amount into units."; return }
        let cur = picked.flatMap { store.quotes[$0.id]?.currency } ?? "USD"
        if amountInUSD && store.fx[cur] == nil { problem = "Still loading the exchange rate for \(cur), try again in a second."; return }
        let amount = amountInUSD ? typed / (entryPrice! * store.fx[cur]!) : typed
        let crypto = picked.map { $0.kind == .crypto } ?? true
        if let c = picked { ItemNames.remember(c.kind == .crypto ? c.symbol + "USDT" : c.symbol, name: c.name) }
        let date = datePreset == "now" && Date().timeIntervalSince(newDate) < 120 ? Date() : newDate
        withAnimation(motion.small) {
            store.add(symbol: sym, crypto: crypto, amount: amount, entry: num(newEntry).flatMap { $0 > 0 ? $0 : nil }, date: date)
            adding = false
        }
        query = ""; picked = nil; newAmount = ""; newEntry = ""; entryEdited = false; marketAtDate = nil
        datePreset = "now"; newDate = Date(); problem = nil
        store.refresh(holdings, base: base)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "briefcase").font(.system(size: 26)).foregroundStyle(.white.opacity(0.5))
            Text(tr("Nothing tracked yet")).font(.system(size: 15, weight: .bold))
            Text(tr("Holdings from your wallets and Binance appear here automatically. You can also add any position by hand with its entry price."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 8) {
                PillLink(title: "Add position", symbol: "plus") { withAnimation(motion.small) { adding = true } }
                PillLink(title: "Connect a wallet", symbol: "wallet.bifold") { state.openSettings(.portfolio) }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct AssetIcon: View {
    let symbol: String
    var size: CGFloat = 32
    var body: some View {
        let c = WalletView.color(symbol)
        let t = symbol.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: ".ME", with: "")
            .replacingOccurrences(of: "=F", with: "")
        ZStack {
            Circle().fill(c.opacity(0.22))
            Circle().stroke(c.opacity(0.6), lineWidth: 1)
            Text(String(t.prefix(t.count > 4 ? 3 : 4))).font(.system(size: size * (t.count > 3 ? 0.27 : 0.32), weight: .heavy)).foregroundStyle(c)
        }
        .frame(width: size, height: size)
    }
}
