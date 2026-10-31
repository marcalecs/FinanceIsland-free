import SwiftUI

@MainActor
struct HomeView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = LongTermStore.shared
    @ObservedObject private var journal = JournalStore.shared
    @ObservedObject private var desk = TradeDesk.shared
    @ObservedObject private var paper = PaperEngine.shared
    @ObservedObject private var perps = WalletPerps.shared
    @ObservedObject private var calendar = MarketCalendar.shared
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @State private var query = ""
    @State private var picked = 0
    @FocusState private var searching: Bool
    @Environment(\.pageActive) private var pageActive

    private var base: String { settings.baseCurrency }
    private var holdings: [Holding] { store.holdings(settings: settings, rates: rates) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PageTitle(tab: .home)
                Spacer(minLength: 6)
                commandBar
                CircleIconButton(symbol: "gearshape", label: "Settings") { state.openSettings(.widget) }
                    .hoverLift()
            }
            .frame(height: 34)
            .zIndex(2)

            HStack(alignment: .top, spacing: 10) {
                holdCard
                tradeCard
            }
            .frame(maxHeight: .infinity)

            attention
            watchlist
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .frame(width: Layout.pageW, height: Layout.bodyH, alignment: .top)
        .onAppear { store.refresh(holdings, base: base) }
    }

    private var cardBG: some View {
        CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card)
    }

    private func caption(_ text: String, trailing: String? = nil, color: Color = .white.opacity(0.5)) -> some View {
        HStack {
            Text(tr(text)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.system(size: 11).monospacedDigit()).foregroundStyle(color).lineLimit(1) }
        }
    }

    private func line(_ left: String, _ mid: String, _ right: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Text(left).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            Text(mid).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            Text(right).font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(color)
                .frame(minWidth: 58, alignment: .trailing)
        }
        .frame(height: 24)
    }

    private func link(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(tr(title))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(look.accent)
        }
        .buttonStyle(.plain)
    }

    private func go(_ tab: IslandTab) {
        settings.lastTab = tab
        withAnimation(motion.page) { state.mode = tab.mode }
    }

    private func openJournal(_ page: String) {
        UserDefaults.standard.set(page, forKey: "journalPage")
        go(.journal)
    }


    private var holdCard: some View {
        let hs = holdings
        let values = hs.map { ($0, store.valueUSD($0)) }
        let total = values.compactMap(\.1).reduce(0, +)
        let day = values.compactMap { h, v -> Double? in
            guard let v, let c = store.change24h[h.symbol], c > -100 else { return nil }
            return v - v / (1 + c / 100)
        }.reduce(0, +)
        let top = values.filter { $0.1 != nil }.sorted { ($0.1 ?? 0) > ($1.1 ?? 0) }
        return VStack(alignment: .leading, spacing: 4) {
            caption("Hold", trailing: total > 0 && day != 0 ? signed(day) + " " + tr("today") : nil, color: look.pnl(day))
            Text(total > 0 ? inBase(total) : inBase(0))
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
                .padding(.bottom, 2)
            if hs.isEmpty {
                Text(tr("Add what you hold: stocks, ETFs, coins or a wallet address."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    chipButton("Add position", "plus") { go(.longTerm) }
                    chipButton("Wallets", "wallet.bifold") { withAnimation(motion.page) { state.mode = .wallet } }
                }
            } else {
                ForEach(top.prefix(9), id: \.0.id) { h, v in
                    let pnl = store.pnl(h, base: base)
                    let pct = pnl.flatMap { $0.cost > 0 ? $0.local / $0.cost * 100 : nil }
                    line(h.symbol.replacingOccurrences(of: "USDT", with: ""), v.map(inBase) ?? "—",
                         pct.map { String(format: "%+.1f%%", $0) } ?? "", look.pnl(pct ?? 0))
                }
                Spacer(minLength: 0)
                HStack {
                    if hs.count > 9 { Text(tr("+ \(hs.count - 9) more")).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5)) }
                    Spacer()
                    link("Portfolio") { go(.longTerm) }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBG)
    }

    private func inBase(_ usd: Double) -> String {
        store.fromUSD(usd, to: base).map { LongTermStore.money($0, base) } ?? LongTermStore.money(usd, "USD")
    }

    private func signed(_ usd: Double) -> String { (usd >= 0 ? "+" : "−") + inBase(abs(usd)) }


    private struct OpenRow: Identifiable {
        let id: String
        let title: String
        let detail: String
        let r: Double?
        let warn: Bool
    }

    private var openRows: [OpenRow] {
        var out: [OpenRow] = []
        if let p = paper.position {
            out.append(OpenRow(id: "paper", title: p.asset + " " + (p.side == .sell ? "short" : "long"),
                               detail: tr("stop") + " " + Fmt.number(p.stop, min: 0, max: 4), r: paper.unrealizedR, warn: false))
        }
        if let e = desk.openManual {
            out.append(OpenRow(id: e.id.uuidString, title: e.asset + " " + (e.side == .sell ? "short" : "long"),
                               detail: e.stop.map { tr("stop") + " " + Fmt.number($0, min: 0, max: 4) } ?? "",
                               r: desk.price(of: e).flatMap { TradeDesk.liveR(e, price: $0) }, warn: false))
        }
        for e in perps.open {
            let px = perps.price(e)
            let liq = px.flatMap { WalletPerps.liquidationDistance(e, price: $0) }
            out.append(OpenRow(id: e.id.uuidString, title: e.asset + " " + tr("perp"),
                               detail: liq.map { tr("liq.") + " " + WalletPerps.pct($0) } ?? "",
                               r: px.flatMap { TradeDesk.liveR(e, price: $0) }, warn: (liq ?? 1) < 0.15))
        }
        return out
    }

    private var tradeCard: some View {
        let cal = Calendar.current
        let closed = journal.entries.filter { $0.kind == .trade && $0.status == .closed }
        let today = closed.filter { cal.isDateInToday($0.closedAt ?? $0.at) }.compactMap(\.rMultiple).reduce(0, +)
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let week = closed.filter { ($0.closedAt ?? $0.at) >= weekAgo }.compactMap(\.outcome)
        let wins = week.filter { $0 > 0 }.count
        let rows = openRows
        return VStack(alignment: .leading, spacing: 4) {
            caption("Trade", trailing: rows.isEmpty ? tr("no open trades") : tr("\(rows.count) open"))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TradeFormat.r(today)).font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(today == 0 ? .white : look.pnl(today))
                Text(tr("today")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 2)
            ForEach(rows.prefix(8)) { o in
                line(o.title, o.detail, o.r.map(TradeFormat.r) ?? "", o.warn ? TradeColors.loss : look.pnl(o.r ?? 0))
            }
            if rows.isEmpty && week.isEmpty {
                Text(tr("Plan a trade with a stop, or practise on paper first."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
            if rows.isEmpty, !week.isEmpty {
                line(tr("Last 7 days"), tr("\(wins)/\(week.count) wins"),
                     TradeFormat.r(closed.filter { ($0.closedAt ?? $0.at) >= weekAgo }.compactMap(\.rMultiple).reduce(0, +)),
                     look.pnl(Double(wins) - Double(week.count) / 2))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                chipButton(rows.isEmpty ? "New trade" : "Trade desk", "plus") { withAnimation(motion.page) { state.mode = .trade } }
                chipButton("Paper", "doc.plaintext") { openJournal("Paper") }
                chipButton("Analytics", "chart.bar") { openJournal("Analytics") }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBG)
    }

    private func chipButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(tr(title)).font(.system(size: 11.5, weight: .semibold)).fixedSize()
            }
            .padding(.horizontal, 9).frame(height: 24)
            .background(Capsule().fill(look.theme.chip))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hoverLift()
    }


    private struct Notice: Identifiable {
        let id: String
        let symbol: String
        let text: String
        let color: Color
        let action: () -> Void
    }

    private func notices(now: Date) -> [Notice] {
        var out: [Notice] = []
        for e in perps.open {
            guard let px = perps.price(e), let d = WalletPerps.liquidationDistance(e, price: px), d < 0.15 else { continue }
            out.append(Notice(id: "liq" + e.id.uuidString, symbol: "exclamationmark.triangle.fill",
                              text: tr("\(e.asset) \(WalletPerps.pct(d)) to liquidation"), color: TradeColors.loss) { go(.longTerm) })
        }
        if let e = journal.entry(desk.pendingTag) {
            out.append(Notice(id: "tag", symbol: "tag", text: tr("Tag your \(e.asset) trade"), color: .white.opacity(0.7)) {
                withAnimation(motion.page) { state.mode = .trade }
            })
        }
        if let next = calendar.upcoming.first {
            out.append(Notice(id: "cal", symbol: "clock", text: MarketCalendar.title(next) + " · " + MarketCalendar.countdown(next.at, now: now),
                              color: .orange) { go(.assistant) })
        }
        let movers = Set(holdings.map(\.symbol)).compactMap { s in store.change24h[s].map { (s, $0) } }
            .filter { abs($0.1) >= max(HolderPrefs.shared.v.movePercent, 3) && !BenchmarkStore.stable.contains($0.0) }
            .sorted { abs($0.1) > abs($1.1) }
        for (s, c) in movers.prefix(2) {
            out.append(Notice(id: "move" + s, symbol: c >= 0 ? "arrow.up.right" : "arrow.down.right",
                              text: s.replacingOccurrences(of: "USDT", with: "") + String(format: " %+.1f%%", c),
                              color: look.pnl(c)) { go(.longTerm) })
        }
        return out
    }

    private var attention: some View {
        TimelineView(.periodic(from: .now, by: 5)) { c in
            let list = notices(now: c.date)
            HStack(spacing: 6) {
                if list.isEmpty {
                    Label(tr("Nothing needs your attention"), systemImage: "checkmark.circle")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(list.prefix(4)) { n in
                    Button(action: n.action) {
                        HStack(spacing: 5) {
                            Image(systemName: n.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(n.color)
                            Text(n.text).font(.system(size: 11.5, weight: .medium).monospacedDigit()).lineLimit(1)
                        }
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(Capsule().fill(look.theme.chip))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 26)
            .animation(motion.small, value: list.map(\.id))
        }
    }


    private var watchlist: some View {
        HStack(spacing: 6) {
            ForEach(settings.assets.prefix(5)) { a in
                let q = rates.quote(a)
                Button { withAnimation(motion.page) { state.mode = .detail(a.id) } } label: {
                    HStack(spacing: 5) {
                        Text(tr(a.code)).font(.system(size: 11.5, weight: .bold))
                        Text(q.map { Fmt.price($0.price, a) } ?? "—").font(.system(size: 11.5).monospacedDigit())
                            .contentTransition(.numericText())
                        if let q {
                            Text(String(format: "%+.1f%%", q.pct)).font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(settings.color(a, up: q.isUp))
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(look.theme.chip))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .hoverLift()
            }
            Spacer(minLength: 0)
            link("Markets") { go(.assistant) }
        }
        .frame(height: 26)
    }


    private struct Hit: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let kind: String
        let run: () -> Void
    }

    private var hits: [Hit] {
        let raw = query.trimmingCharacters(in: .whitespaces)
        let q = raw.lowercased()
        guard !q.isEmpty else { return [] }
        var out: [Hit] = []
        if let smart = SmartEntry.parse(raw) {
            out.append(Hit(id: "smart", symbol: "✦", title: SmartEntryRunner.describe(smart), kind: tr("Add")) {
                SmartEntryRunner.run(smart, text: raw)
                if case .hold = smart { go(.longTerm) } else { openJournal("Journal") }
            })
        }
        let commands: [(String, String, String, () -> Void)] = [
            ("trade", "plus", "New trade", { withAnimation(motion.page) { state.mode = .trade } }),
            ("paper", "doc.plaintext", "Paper trading", { openJournal("Paper") }),
            ("journal", "book.pages", "Journal", { openJournal("Journal") }),
            ("analytics", "chart.bar", "Analytics", { openJournal("Analytics") }),
            ("portfolio", "briefcase", "Portfolio", { go(.longTerm) }),
            ("wallet", "wallet.bifold", "Wallets and exchange accounts", { withAnimation(motion.page) { state.mode = .wallet } }),
            ("markets", "chart.bar.xaxis", "Markets", { go(.assistant) }),
            ("settings", "gearshape", "Settings", { state.openSettings() }),
        ]
        for (key, _, title, run) in commands where key.hasPrefix(q) || tr(title).lowercased().hasPrefix(q) {
            out.append(Hit(id: "cmd-" + key, symbol: "›", title: tr(title), kind: tr("Go to"), run: run))
        }
        for a in settings.assets where a.code.lowercased().contains(q) || a.name.lowercased().contains(q) {
            let price = rates.quote(a).map { Fmt.price($0.price, a) } ?? ""
            out.append(Hit(id: "asset-" + a.id, symbol: tr(a.code), title: a.name + (price.isEmpty ? "" : " · " + price), kind: tr("Watchlist")) {
                withAnimation(motion.page) { state.mode = .detail(a.id) }
            })
        }
        for h in holdings where h.symbol.lowercased().contains(q) || h.label.lowercased().contains(q) {
            out.append(Hit(id: "hold-" + h.id, symbol: h.symbol.replacingOccurrences(of: "USDT", with: ""),
                           title: tr("\(Fmt.number(h.amount, min: 0, max: 6)) in your portfolio"), kind: tr("Position")) { go(.longTerm) })
        }
        let trades = journal.entries.filter { $0.kind == .trade && ($0.asset.lowercased().contains(q) || $0.allTags.contains { $0.lowercased().contains(q) }) }
            .sorted { $0.at > $1.at }
        for e in trades.prefix(3) {
            out.append(Hit(id: "trade-" + e.id.uuidString, symbol: e.asset,
                           title: (e.side == .sell ? "SHORT" : "LONG") + " · " + Fmt.date(e.opened, "d MMM") + (e.rMultiple.map { " · " + TradeFormat.r($0) } ?? ""),
                           kind: tr("Trade")) { openJournal(e.status == .open ? "Journal" : "Analytics") })
        }
        out.append(Hit(id: "markets", symbol: "⌕", title: tr("Find “\(raw)” in all markets"), kind: tr("Markets")) { go(.assistant) })
        return Array(out.prefix(8))
    }

    private func run(_ h: Hit) {
        query = ""
        searching = false
        h.run()
    }

    private var commandBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            TextField(tr("Search or command"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searching)
                .onSubmit { let h = hits; if h.indices.contains(picked) { run(h[picked]) } }
                .onChange(of: query) { _, _ in picked = 0 }
                .onKeyPress(.downArrow) { picked = min(picked + 1, max(hits.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
                .onExitCommand { query = ""; searching = false }
                .onKeyPress(.tab) {
                    guard let g = SmartEntryRunner.suggestion(query) else { return .ignored }
                    query = g
                    return .handled
                }
                .overlay(alignment: .leading) {
                    if let g = SmartEntryRunner.suggestion(query), g.count > query.count {
                        (Text(query).foregroundStyle(.clear) + Text(String(g.dropFirst(query.count))).foregroundStyle(.white.opacity(0.32)))
                            .font(.system(size: 12.5)).lineLimit(1).allowsHitTesting(false)
                    }
                }
            Text("⌘K").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 5).frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.2)))
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 140, maxWidth: 260, minHeight: 34, maxHeight: 34)
        .background(Capsule().fill(look.theme.chip))
        .background {
            if pageActive { Button("") { searching = true }.keyboardShortcut("k", modifiers: .command).opacity(0) }
        }
        .overlay(alignment: .topTrailing) {
            if searching && !query.isEmpty { results.offset(y: 40) }
        }
    }

    private var results: some View {
        let list = hits
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, h in
                Button { run(h) } label: {
                    HStack(spacing: 8) {
                        Text(h.symbol).font(.system(size: 12.5, weight: .bold)).frame(width: 64, alignment: .leading).lineLimit(1)
                        Text(h.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(h.kind).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        if i == picked { Text("↵").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(look.accent) }
                    }
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(i == picked ? look.theme.selected : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { picked = i } }
            }
        }
        .padding(6)
        .frame(width: 380, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }
}
