import SwiftUI

@MainActor
struct JournalView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var journal: JournalStore
    @ObservedObject var probability: ProbabilityStore
    @ObservedObject var settings: AppSettings
    @Environment(\.look) private var look

    enum Filter: String, CaseIterable { case all = "All", open = "Active", closed = "Closed", notes = "Notes" }
    enum Page: String, CaseIterable { case journal = "Journal", paper = "Paper", analytics = "Analytics", mirror = "Mirror" }
    @AppStorage("journalPage") private var page: Page = .journal
    @ObservedObject private var desk = TradeDesk.shared
    @State private var filter: Filter = .all

    @State private var kind: JournalEntry.Kind = .note
    @State private var side: Signal = .buy
    @State private var asset = ""
    @State private var entry = ""
    @State private var stop = ""
    @State private var target = ""
    @State private var size = ""
    @AppStorage("journalShowMoney") private var showMoney = false
    @ObservedObject private var license = LicenseStore.shared
    @AppStorage("journalOneR") private var rValue = 0.0
    @State private var rHint = false
    private var moneyOn: Bool { showMoney && rValue > 0 }
    @State private var text = ""
    @State private var tags = ""
    @State private var problem: String?

    @State private var closing: UUID?
    @State private var exitPrice = ""
    @State private var confirmDelete: UUID?
    @AppStorage("journalImportOpen") private var importOpen = false
    private var editing: Bool { state.journalEditing }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PageTitle(tab: .journal)
                PillPicker(options: Page.allCases, selection: $page, label: { $0.rawValue }, minWidth: 64)
                    .padding(.leading, 6)
                Spacer(minLength: 4)
                PillLink(title: desk.hasTrade ? "Trade desk" : "New trade", symbol: "plus") { state.mode = .trade }
                if !journal.entries.isEmpty { EditDoneButton(editing: $state.journalEditing) }
                CircleIconButton(symbol: "gearshape", label: "Settings") { state.openSettings(.assistant) }
            }
            .frame(height: 34)

            if page == .journal {
                stats
                if !journal.closed.isEmpty { extendedStats }
            }

            PageScroll {
                VStack(spacing: 12) {
                    switch page {
                    case .journal:
                        SmartEntryField()
                        compose
                        list
                        importSection
                    case .paper: PaperPanel(settings: settings)
                    case .analytics: JournalAnalytics(settings: settings)
                    case .mirror: TraderMirror()
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
            .verticalOnly()
            .overlay(alignment: .bottom) {
                if let id = desk.pendingTag, journal.entry(id) != nil {
                    TagPopover(entryID: id, settings: settings)
                        .shadow(color: .black.opacity(0.35), radius: 14, y: 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: desk.pendingTag)

            if let d = journal.lastDeleted {
                UndoBar(text: "Entry deleted", since: d.at) { withAnimation(.smooth(duration: 0.22)) { journal.undoDelete() } }
            }
            FooterNote(text: tr("The journal is stored only on this Mac · R = result in units of the planned risk"), symbol: "lock")
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .frame(width: Layout.pageW, height: RenderFlags.noScroll ? nil : Layout.bodyH, alignment: .top)
        .onAppear(perform: takeDraft)
        .onChange(of: journal.draft) { _, _ in takeDraft() }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { importOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 11, weight: .semibold))
                    Text(tr("Import trades")).font(.system(size: 12.5, weight: .semibold))
                    Text("Binance · Bybit · Wallet").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(importOpen ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if importOpen {
                BinanceImportCard()
                BybitImportCard()
                HStack {
                    Text(tr("Wallet (Telegram)")).font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    PillLink(title: "Import file…", symbol: "square.and.arrow.down") { WalletPerps.shared.importFiles() }
                }
                WalletTradeForm()
            }
        }
    }

    private var stats: some View {
        let total = journal.totalR
        let closed = journal.closed.count
        return HStack(spacing: 8) {
            stat("Entries", "\(journal.entries.count)")
            stat("Open trades", "\(journal.openCount)")
            stat("Winning", journal.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                 sub: closed > 0 ? tr("\(closed) closed") : nil)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rHint ? tr("Set 1R in Settings ▸ Trading") : moneyOn ? tr("Total in \(settings.baseCurrency)") : tr("Total in R"))
                        .font(.system(size: 11)).foregroundStyle(rHint ? look.accent : .white.opacity(0.5))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(closed > 0 ? totalText(total) : "—")
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.numericText())
                        .foregroundStyle(closed == 0 ? .white : look.pnl(total))
                }
                Spacer(minLength: 4)
                if closed > 0 {
                    EquityCurve(values: journal.equityCurve, color: look.pnl(total),
                                line: look.theme.line)
                        .frame(width: 54, height: 26)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(tile)
            .contentShape(Rectangle())
            .onTapGesture {
                guard rValue > 0 else {
                    withAnimation(.easeOut(duration: 0.18)) { rHint = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { rHint = false } }
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) { showMoney.toggle() }
            }
            .help(tr("Tap to switch between R and money"))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var extendedStats: some View {
        if license.isActive {
            HStack(spacing: 8) {
                stat("Profit factor", journal.profitFactor.map { $0.isInfinite ? "∞" : String(format: "%.2f", $0) } ?? "—")
                stat("Expectancy", journal.expectancy.map { String(format: "%+.2fR", $0) } ?? "—")
                stat("Max drawdown", journal.closed.isEmpty ? "—" : String(format: "%.2fR", journal.maxDrawdownR))
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            ProPreview(feature: .extendedStats)
        }
    }

    private func totalText(_ r: Double) -> String {
        guard moneyOn else { return String(format: "%+.2fR", r) }
        return (r >= 0 ? "+" : "−") + LongTermStore.money(abs(r * rValue), settings.baseCurrency)
    }

    private func stat(_ title: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tr(title)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 17, weight: .bold).monospacedDigit())
                if let sub { Text(sub).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42)) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(tile)
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("New entry")).font(.system(size: 14, weight: .bold))
                Spacer()
                PillPicker(options: [JournalEntry.Kind.note, .trade], selection: $kind,
                           label: { $0 == .note ? "Note" : "Trade" }, minWidth: 54)
            }
            HStack(spacing: 8) {
                labelled("Asset") {
                    HStack(spacing: 2) {
                        field("BTC, AAPL…", $asset, width: 120)
                        Menu {
                            ForEach(HubSubject.all(settings)) { s in Button(s.short + " · " + tr(s.name)) { asset = s.code } }
                        } label: { Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)) }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help(tr("Pick from the assistant's list"))
                    }
                }
                if kind == .trade {
                    labelled("Side") {
                        PillPicker(options: [Signal.buy, .sell], selection: $side, label: { $0.rawValue }, minWidth: 34)
                    }
                    labelled("Entry") { field("0.00", $entry, width: 66) }
                    labelled("Stop") { field("0.00", $stop, width: 66) }
                    labelled("Target") { field("0.00", $target, width: 66) }
                    labelled("Size, %") { field("—", $size, width: 46) }
                }
                Spacer(minLength: 0)
            }
            if kind == .trade {
                HStack(spacing: 8) {
                    if let rr = rewardRisk {
                        Text(tr("Reward : risk") + String(format: "  1 : %.1f", rr))
                            .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            TextField(tr("What I see, why I'm entering, what I'll do if it goes against me…"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(3...6)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.chip))
            HStack(spacing: 8) {
                TextField(tr("tags, comma separated"), text: $tags)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Capsule().fill(look.theme.chip))
                if let problem {
                    Text(tr(problem)).font(.system(size: 11.5)).foregroundStyle(look.trend.red).lineLimit(1)
                }
                Button(action: save) {
                    Label(tr("Save"), systemImage: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(Capsule().fill(look.accent.opacity(0.85)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(14)
        .background(card)
        .animation(.easeOut(duration: 0.18), value: kind)
    }

    private func labelled<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr(title)).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            content()
        }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, width: CGFloat) -> some View {
        TextField(tr(placeholder), text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5).monospacedDigit())
            .padding(.horizontal, 9)
            .frame(width: width, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
    }

    private var list: some View {
        let shown = journal.entries
            .filter {
                switch filter {
                case .all: return true
                case .notes: return $0.kind == .note
                case .open: return $0.kind == .trade && $0.status == .open
                case .closed: return $0.kind == .trade && $0.status == .closed
                }
            }
            .sorted { $0.at > $1.at }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Entries")).font(.system(size: 14, weight: .bold))
                Spacer()
                PillPicker(options: Filter.allCases, selection: $filter, label: { $0.rawValue }, minWidth: 44)
            }
            if shown.isEmpty {
                Text(journal.entries.isEmpty
                     ? tr("Nothing here yet. Write down why you enter a trade, and close it here when you exit.")
                     : tr("Nothing in this filter."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            ForEach(shown) { e in
                row(e)
                if e.id != shown.last?.id { Divider().overlay(look.theme.line) }
            }
        }
        .padding(14)
        .background(card)
        .animation(.easeOut(duration: 0.2), value: journal.entries)
        .animation(.easeOut(duration: 0.2), value: filter)
    }

    private func row(_ e: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if editing {
                    RemoveBadge(label: e.asset) { withAnimation(.smooth(duration: 0.22)) { journal.delete(e.id) } }
                }
                Text(e.asset).font(.system(size: 12.5, weight: .bold))
                if e.kind == .trade {
                    SignalBadgeView(signal: e.side, size: 9.5)
                    chip(e.status == .closed ? "closed" : "open", e.status == .closed ? .white.opacity(0.55) : look.accent)
                } else {
                    chip("note", .white.opacity(0.55))
                }
                Text(Fmt.date(e.at, "d MMM HH:mm")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                ForEach(e.tags, id: \.self) { t in chip("#" + t, .white.opacity(0.5), translate: false) }
                Spacer(minLength: 4)
                if e.kind == .trade && e.status == .open {
                    smallButton("Close trade", "flag.checkered") {
                        closing = e.id
                        exitPrice = currentPrice(e).map(AssetFormat.price) ?? e.entry.map(AssetFormat.price) ?? ""
                    }
                }
                if let a = matchedAsset(e.asset) {
                    smallButton("Open in the assistant", "brain.head.profile") {
                        state.probDetail = a.id
                        settings.lastTab = .assistant
                        state.mode = .assistant
                    }
                } else if let id = e.itemID, HubSubject.match(itemID: id, settings) != nil {
                    smallButton("Open in the assistant", "brain.head.profile") {
                        settings.lastTab = .assistant
                        state.openSubject(itemID: id, settings: settings)
                    }
                }
                if confirmDelete == e.id {
                    smallButton("Delete?", "trash.fill", tint: look.trend.red) { journal.delete(e.id); confirmDelete = nil }
                } else {
                    smallButton("Delete", "trash") { confirmDelete = e.id }
                }
            }
            if !e.text.isEmpty {
                Text(e.text).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if e.kind == .trade { levels(e) }
            if closing == e.id {
                HStack(spacing: 8) {
                    field("exit price", $exitPrice, width: 100)
                    smallButton("Close", "checkmark", tint: look.accent) {
                        if let x = number(exitPrice) { journal.close(e.id, exit: x, reason: .manual); TradeDesk.shared.pendingTag = e.id }
                        closing = nil
                    }
                    smallButton("Cancel", "xmark") { closing = nil }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func levels(_ e: JournalEntry) -> some View {
        HStack(spacing: 12) {
            level("entry", e.entry, .white)
            level("stop", e.stop, look.trend.red)
            level("target", e.target, look.trend.green)
            if let s = e.size { pair("size", String(format: "%g%%", s), .white) }
            if let rr = e.rewardRisk { pair("reward : risk", String(format: "1 : %.1f", rr), .white) }
            if e.status == .closed {
                level("exit", e.exit, .white)
                if let r = e.rMultiple {
                    Text(String(format: "%+.2fR", r))
                        .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(look.pnl(r))
                }
            }
        }
        .font(.system(size: 11.5).monospacedDigit())
    }

    private func level(_ title: String, _ v: Double?, _ color: Color) -> some View {
        pair(title, v.map(AssetFormat.price) ?? "—", color)
    }

    private func pair(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(tr(title)).foregroundStyle(.white.opacity(0.45))
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func chip(_ s: String, _ color: Color, translate: Bool = true) -> some View {
        Text(translate ? tr(s) : s)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).frame(height: 18)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    private func smallButton(_ title: String, _ symbol: String, tint: Color? = nil,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(tr(title), systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(0.75))
                .padding(.horizontal, 9).frame(height: 24)
                .background(Capsule().fill((tint ?? .white).opacity(tint == nil ? 0.08 : 0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }

    private var card: some View {
        CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card)
    }

    private var tile: some View {
        CardBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), fill: look.theme.card)
    }

    private var matchedItem: WatchItem? {
        let a = asset.trimmingCharacters(in: .whitespaces).uppercased()
        guard !a.isEmpty else { return nil }
        return settings.watchItems.first { [$0.short, $0.symbol, $0.display].map { $0.uppercased() }.contains(a) }
    }

    private func matchedAsset(_ name: String) -> HubSubject? { HubSubject.find(name, settings) }

    private var canPlan: Bool {
        matchedAsset(asset).map { probability.model($0) != nil } ?? (matchedItem != nil)
    }

    private var rewardRisk: Double? {
        JournalEntry(asset: "", kind: .trade, entry: number(entry), stop: number(stop), target: number(target),
                     text: "").rewardRisk
    }

    private func currentPrice(_ e: JournalEntry) -> Double? {
        let subject = matchedAsset(e.asset) ?? e.itemID.flatMap { HubSubject.match(itemID: $0, settings) }
        guard let s = subject else { return nil }
        return probability.model(s)?.price
    }

    private func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private func show(_ v: Double?) -> String { v.map { String(format: "%g", $0) } ?? "" }

    private func takeDraft() {
        guard let d = journal.draft else { return }
        journal.draft = nil
        load(d, keepText: false)
    }

    private func load(_ d: JournalEntry, keepText: Bool) {
        kind = d.kind
        side = d.side
        asset = d.asset
        entry = show(d.entry); stop = show(d.stop); target = show(d.target); size = show(d.size)
        if !keepText || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = d.text }
        if !d.tags.isEmpty { tags = d.tags.joined(separator: ", ") }
        problem = nil
    }


    private func save() {
        let name = asset.trimmingCharacters(in: .whitespaces)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var e = JournalEntry(asset: name.isEmpty ? "—" : name.uppercased(), itemID: matchedItem?.id, kind: kind,
                             text: body,
                             tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty })
        if kind == .trade {
            guard let en = number(entry), let st = number(stop), let tg = number(target) else {
                problem = "A trade needs an entry, a stop and a target."
                return
            }
            guard en != st else { problem = "The stop must differ from the entry."; return }
            e.side = side; e.entry = en; e.stop = st; e.target = tg; e.size = number(size)
        } else if body.isEmpty {
            problem = "Write something first."
            return
        }
        journal.add(e)
        problem = nil
        entry = ""; stop = ""; target = ""; size = ""; text = ""; tags = ""
    }
}

private struct EquityCurve: View {
    let values: [Double]
    let color: Color
    let line: Color

    var body: some View {
        GeometryReader { g in
            let mx = max(1, values.map(abs).max() ?? 1)
            let mid = g.size.height / 2
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: mid - CGFloat(v / mx) * (mid - 2))
            }
            ZStack {
                Path { p in p.move(to: CGPoint(x: 0, y: mid)); p.addLine(to: CGPoint(x: g.size.width, y: mid)) }
                    .stroke(line, lineWidth: 1)
                Path { p in p.addLines(pts) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
