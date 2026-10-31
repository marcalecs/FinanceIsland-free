import SwiftUI

@MainActor
struct ProbabilityView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var store: ProbabilityStore
    @ObservedObject var journal: JournalStore
    @ObservedObject var settings: AppSettings
    @Environment(\.look) var look
    @Environment(\.motion) var motion
    @State var showDeep = false
    var reorder: ReorderModel { state.assistantReorder }
    @ObservedObject var news = NewsStore.shared
    @AppStorage("scalpSort") var sortKey = "manual"
    @AppStorage("scalpAscending") var ascending = true
    @ObservedObject var reorderModel: ReorderModel

    init(state: IslandState, store: ProbabilityStore, journal: JournalStore, settings: AppSettings) {
        self.state = state
        self.store = store
        self.journal = journal
        self.settings = settings
        _reorderModel = ObservedObject(wrappedValue: state.assistantReorder)
    }
    @AppStorage("assistantOrder") var orderRaw = ""
    static let rowH: CGFloat = 56
    let noviceHorizon = 16
    @AppStorage("proHorizon") var proHorizon = 16
    var pro: Bool { false }
    var horizon: Int { pro ? proHorizon : noviceHorizon }
    @State var stop: Double?
    @State var target: Double?
    @State var answer: String?
    @State var query = ""
    @State var picked = 0
    @State var remote: [CatalogItem] = []
    @FocusState var searching: Bool
    @Environment(\.pageActive) var pageActive

    var subjects: [HubSubject] {
        let all = HubSubject.all(settings)
        let order = orderRaw.split(separator: "\n").map(String.init)
        guard !order.isEmpty else { return all }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return all.enumerated().sorted { a, b in
            (rank[a.element.id] ?? 10_000 + a.offset) < (rank[b.element.id] ?? 10_000 + b.offset)
        }.map(\.element)
    }


    func move(_ id: String, to index: Int) {
        var ids = subjects.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        ids.insert(id, at: min(max(index, 0), ids.count))
        orderRaw = ids.joined(separator: "\n")
    }
    var selected: HubSubject? { subjects.first { $0.id == state.probDetail } }

    var signalsOn: Bool {
        false
    }

    func refreshSignals(_ list: [HubSubject]) {
    }

    @ViewBuilder
    var page: some View {
        if selected == nil { MacroCard() }
        if let s = selected { marketDetail(s) } else { marketList; MarketHoursCard() }
    }

    var footer: String {
        if let stale = store.staleSince {
            return tr("Some prices are stale: the last daily candle is from \(Fmt.date(stale, "d MMM")). Refresh, or check the data source in Settings.")
        }
        return tr("Prices from public market data · volatility estimates, not forecasts") + " · " + tr(Legal.disclaimer)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            topBar.zIndex(2)
            if subjects.isEmpty {
                placeholder(tr("Add a currency, a coin or a stock with the search above."), failed: false)
            } else {
                PageScroll {
                    VStack(alignment: .leading, spacing: 12) { page }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.never)
                .verticalOnly()
                .id(selected?.id ?? "list")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: selected == nil ? -18 : 18)),
                    removal: .opacity))
            }
            FooterNote(text: footer)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .frame(width: Layout.pageW, height: RenderFlags.noScroll ? nil : Layout.bodyH, alignment: .top)
        .onAppear {
            for s in subjects { store.load(s) }
            refreshSignals(subjects)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                if selected == nil { refreshSignals(subjects) }
            }
        }
        .onChange(of: subjects.map(\.id)) { _, _ in for s in subjects { store.load(s) } }
        .onChange(of: selected?.id) { _, id in
            stop = nil; target = nil; answer = nil; reorder.editing = false
            if id == nil { refreshSignals(subjects) }
        }
        .onExitCommand { if state.probDetail != nil { withAnimation(motion.page) { state.probDetail = nil } } }
    }

    var topBar: some View {
        HStack(spacing: 8) {
            PageTitle(tab: .assistant)
            Spacer(minLength: 8)
            if selected == nil && !subjects.isEmpty {
                if signalsOn {
                    CircleIconButton(symbol: "bolt.fill", label: "Refresh signals") {
                        refreshSignals(subjects)
                    }
                        .help(tr("Generate fresh signals from the latest 5-minute candles"))
                }
                EditDoneButton(editing: $reorderModel.editing)
            }
            search
            CircleIconButton(symbol: "gearshape", label: "Settings") { state.openSettings(.currencies) }
        }
        .frame(height: 34)
    }

    struct Hit: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let kind: String
        let added: Bool
        let pick: () -> Void
    }

    var hits: [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "/", with: "")
        let have = subjects
        var out: [Hit] = []
        func match(_ parts: [String]) -> Bool {
            q.isEmpty || parts.joined(separator: " ").lowercased().replacingOccurrences(of: "/", with: "").contains(q)
        }
        if !q.isEmpty {
            let lt = LongTermStore.shared
            for m in lt.manual where match([m.symbol, ItemNames.name(m.symbol) ?? ""]) {
                out.append(Hit(id: "pos:" + m.id.uuidString, symbol: m.symbol, name: tr("\(Fmt.number(m.amount, min: 0, max: 6)) in your portfolio"),
                               kind: tr("Position"), added: true, pick: {
                    query = ""; searching = false
                    settings.lastTab = .longTerm
                    state.mode = .longTerm
                }))
            }
            let trades = JournalStore.shared.entries.filter { $0.kind == .trade && match([$0.asset] + $0.allTags) }.sorted { $0.at > $1.at }
            for e in trades.prefix(3) {
                let r = e.rMultiple.map { " · " + TradeFormat.r($0) } ?? ""
                out.append(Hit(id: "trade:" + e.id.uuidString, symbol: e.asset,
                               name: (e.side == .sell ? "SHORT" : "LONG") + " · " + Fmt.date(e.opened, "d MMM HH:mm") + r,
                               kind: tr("Trade"), added: true, pick: {
                    query = ""; searching = false
                    UserDefaults.standard.set(e.status == .open ? "Journal" : "Analytics", forKey: "journalPage")
                    settings.lastTab = .journal
                    state.mode = .journal
                }))
            }
        }
        for s in have where !q.isEmpty && match([s.short, s.name, s.code]) {
            out.append(Hit(id: s.id, symbol: s.short, name: tr(s.name), kind: tr(s.crypto ? "Crypto" : s.item != nil ? "Stock" : "Currency"),
                           added: true, pick: { select(s) }))
        }
        let base = settings.baseCurrency
        for e in Catalog.fiat + Catalog.crypto where !(e.kind == .fiat && e.code == base) && match([e.code, e.name]) {
            let a = Asset.make(kind: e.kind, code: e.code, base: base)
            guard !have.contains(.asset(a)) else { continue }
            out.append(Hit(id: e.id, symbol: e.kind == .fiat ? e.code + "/" + base : e.code, name: tr(e.name),
                           kind: tr(e.kind == .fiat ? "Currency" : "Crypto"), added: false, pick: {
                if !settings.assetIDs.contains(e.id) { settings.assetIDs.append(e.id) }
                select(.asset(a))
            }))
        }
        let fiatCrypto = Set(Catalog.crypto.map(\.code))
        let haveSymbols = Set(have.compactMap { $0.item?.symbol.uppercased() })
        for c in SearchCatalog.search(query) + remote where !(c.kind == .crypto && fiatCrypto.contains(c.symbol)) {
            let sym = c.kind == .crypto ? c.symbol + "USDT" : c.symbol
            guard !haveSymbols.contains(sym.uppercased()), !out.contains(where: { $0.id == c.id }) else { continue }
            out.append(Hit(id: c.id, symbol: ItemNames.short(c.symbol, name: c.name), name: c.name, kind: tr(c.kind.rawValue),
                           added: false, pick: {
                ItemNames.remember(sym, name: c.name)
                if let item = settings.addItem(c.symbol, source: c.source) { select(.item(item)) }
            }))
        }
        let ticker = query.trimmingCharacters(in: .whitespaces).uppercased()
        if !ticker.isEmpty, ticker.count <= 12, ticker.allSatisfy({ $0.isLetter || $0.isNumber || ".^-=".contains($0) }),
           !out.contains(where: { $0.symbol.uppercased() == ticker }) {
            out.append(Hit(id: "stock:" + ticker, symbol: ticker, name: tr("Stock or ETF on Yahoo Finance"), kind: tr("Stock"),
                           added: false, pick: {
                if let item = settings.addItem(ticker, source: .yahoo) { select(.item(item)) }
            }))
        }
        return Array(out.prefix(q.isEmpty ? 6 : 10))
    }

    var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            TextField(tr("Search or add"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searching)
                .onSubmit { let h = hits; if h.indices.contains(picked) { h[picked].pick() } }
                .onChange(of: query) { _, _ in picked = 0 }
                .task(id: query) {
                    remote = []
                    let q = query.trimmingCharacters(in: .whitespaces)
                    guard q.count >= 2 else { return }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    let found = await SearchCatalog.yahoo(q)
                    if !Task.isCancelled { remote = found }
                }
                .onKeyPress(.downArrow) { picked = min(picked + 1, max(hits.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { picked = max(picked - 1, 0); return .handled }
                .onExitCommand { query = ""; searching = false }
            Text("⌘K").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 5).frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.2)))
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 120, maxWidth: 250, minHeight: 34, maxHeight: 34)
        .background(Capsule().fill(look.theme.chip))
        .background {
            if pageActive { Button("") { searching = true }.keyboardShortcut("k", modifiers: .command).opacity(0) }
        }
        .overlay(alignment: .topTrailing) {
            if searching { results.offset(y: 40) }
        }
    }

    var results: some View {
        let list = hits
        return VStack(alignment: .leading, spacing: 2) {
            if query.isEmpty {
                Text(tr("You can add these")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 10).padding(.top, 4)
            }
            if list.isEmpty {
                Text(tr("Nothing found for “\(query)”")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .padding(10)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, h in
                Button { h.pick() } label: {
                    HStack(spacing: 8) {
                        Text(h.symbol).font(.system(size: 12.5, weight: .bold)).frame(width: 78, alignment: .leading)
                        Text(h.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(h.kind).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        if !h.added {
                            Text(tr("+ add")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(look.accent)
                        }
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
        .frame(width: 330, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    func select(_ s: HubSubject) {
        withAnimation(motion.page) { state.probDetail = s.id }
        query = ""
        searching = false
        store.load(s)
    }

    var cardBG: some View {
        CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card)
    }

    func placeholder(_ text: String, failed: Bool) -> some View {
        VStack(spacing: 8) {
            if failed { Image(systemName: "wifi.exclamationmark").font(.system(size: 22)) }
            else { ProgressView().controlSize(.small) }
            Text(text).font(.system(size: 13)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func pct(_ x: Double) -> String { String(format: "%.0f%%", x * 100) }
    func pctFine(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    func signed(_ x: Double) -> String { (x >= 0 ? "+" : "−") + String(format: "%.2f", abs(x)) }

}
