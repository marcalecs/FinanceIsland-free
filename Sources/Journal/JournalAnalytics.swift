import AppKit
import SwiftUI

@MainActor
struct JournalAnalytics: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var journal = JournalStore.shared
    @ObservedObject private var license = LicenseStore.shared
    @ObservedObject private var prefs = TradePrefs.shared
    @Environment(\.look) private var look

    enum Period: String, CaseIterable { case today = "Today", week = "7 days", month = "30 days", all = "All time" }
    enum Modes: String, CaseIterable { case real = "Manual + paper", manual = "Manual", binance = "Binance", wallet = "Wallet", paper = "Paper", simulated = "Simulated" }
    @AppStorage("analyticsPeriod") private var period: Period = .all
    @AppStorage("analyticsModes") private var modes: Modes = .real
    @State private var tag: String?

    var filter: JournalFilter {
        let now = Date(), cal = Calendar.current
        let from: Date? = switch period {
        case .today: cal.startOfDay(for: now)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        case .all: nil
        }
        let m: Set<JournalEntry.Mode> = switch modes {
        case .real: [.manual, .paper]
        case .manual, .binance, .wallet: [.manual]
        case .paper: [.paper]
        case .simulated: [.simulated]
        }
        let src: Set<JournalFilter.Source>? = switch modes {
        case .manual: [.manual]
        case .binance: [.binance]
        case .wallet: [.wallet]
        default: nil
        }
        return JournalFilter(from: from, modes: m, tag: tag, sources: src)
    }

    private var unit: String? {
        switch modes {
        case .manual, .binance: return settings.baseCurrency
        case .wallet: return "USDT"
        case .paper, .simulated: return "USDT"
        case .real: return settings.baseCurrency == "USD" ? "USD" : nil
        }
    }

    var body: some View {
        let s = JournalStats(journal.entries, filter: filter)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PillPicker(options: Period.allCases, selection: $period, label: { $0.rawValue }, minWidth: 40)
                Menu {
                    ForEach(Modes.allCases, id: \.self) { m in Button(tr(m.rawValue)) { modes = m } }
                } label: { Text(tr(modes.rawValue)).font(.system(size: 12, weight: .semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
                Menu {
                    Button(tr("All tags")) { tag = nil }
                    ForEach(allTags, id: \.self) { t in Button(t) { tag = t } }
                } label: { Text(tag ?? tr("All tags")).font(.system(size: 12, weight: .semibold)) }
                    .menuStyle(.borderlessButton).fixedSize()
                Spacer()
                if modes == .simulated { ModeLabel(mode: .simulated) }
                PillLink(title: "Export CSV", symbol: "square.and.arrow.up") { exportCSV() }
                    .help(tr("Closed trades with every field. This is not a tax report."))
            }
            HStack(spacing: 8) {
                kpi("Net PnL", s.totalTrades == 0 ? "—" : TradeFormat.money(s.netPnL, unit: unit),
                    sub: s.totalTrades == 0 ? nil : TradeFormat.r(s.totalR), color: s.totalTrades == 0 ? nil : TradeColors.pnl(s.totalR))
                kpi("Win rate", s.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—", sub: tr("\(s.totalTrades) trades"))
                kpi("Avg R", s.avgR.map(TradeFormat.r) ?? "—", color: s.avgR.map(TradeColors.pnl))
                kpi("Streak", s.currentStreak == 0 ? "—" : s.currentStreak > 0 ? tr("\(s.currentStreak) won") : tr("\(-s.currentStreak) lost"),
                    color: s.currentStreak == 0 ? nil : TradeColors.pnl(Double(s.currentStreak)))
            }
            .fixedSize(horizontal: false, vertical: true)
            if license.isActive {
                HStack(spacing: 8) {
                    kpi("Profit factor", s.profitFactor.map { $0.isInfinite ? "∞" : String(format: "%.2f", $0) } ?? "—")
                    kpi("Expectancy", s.expectancy.map(TradeFormat.r) ?? "—",
                        sub: s.expectancyMoney.map { TradeFormat.money($0, unit: unit) })
                    kpi("Max drawdown", s.totalTrades == 0 ? "—" : String(format: "%.2fR", s.maxDrawdownR),
                        sub: s.totalTrades == 0 ? nil : TradeFormat.money(s.maxDrawdownMoney, unit: unit))
                    kpi("Daily limit left", dailyLeft)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                ProPreview(feature: .extendedStats)
            }
            MistakeCostCard(stats: s, unit: unit, title: "Trades with mistake tags in this filter", pro: license.isActive)
            list(s.trades.reversed())
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "FinanceIsland-trades-\(Fmt.date(Date(), "yyyy-MM-dd")).csv"
        panel.message = tr("Closed trades with every field. This is not a tax report.")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(JournalCSV.make(journal.entries, baseCurrency: settings.baseCurrency).utf8).write(to: url, options: .atomic)
        } catch {
            AppLog.write("csv export failed:", error.localizedDescription)
        }
    }

    private var dailyLeft: String {
        let t = prefs.v.tilt
        guard let left = TiltGuard.remaining(journal.entries, t, now: Date()) else { return tr("off") }
        return t.dailyLossInR ? String(format: "%.2fR", left) : LongTermStore.money(left, settings.baseCurrency)
    }

    private var allTags: [String] {
        Array(Set(journal.entries.filter { $0.kind == .trade }.flatMap(\.allTags))).sorted()
    }

    private func list(_ trades: [JournalEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Trades")).font(.system(size: 14, weight: .bold))
            if trades.isEmpty {
                Text(tr("No closed trades in this filter."))
                    .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            ForEach(trades) { e in
                HStack(spacing: 8) {
                    Text(Fmt.date(e.closedAt ?? e.at, "d MMM HH:mm")).font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                    ModeLabel(entry: e, size: 8.5)
                    Text(e.asset).font(.system(size: 12.5, weight: .bold))
                    SignalBadgeView(signal: e.side, size: 9)
                    if let c = e.closedAt { Text(TradeFormat.duration(c.timeIntervalSince(e.opened))).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
                    ForEach([e.setupTag, e.mistakeTag].compactMap { $0 }, id: \.self) { t in
                        Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(look.theme.chip))
                    }
                    Spacer(minLength: 4)
                    if let n = e.netPnL {
                        Text(TradeFormat.money(n, unit: TradeFormat.unit(e, base: settings.baseCurrency)))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(TradeColors.pnl(n))
                    }
                    if let r = e.rMultiple {
                        Text(TradeFormat.r(r)).font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(TradeColors.pnl(r))
                    }
                }
                .lineLimit(1)
                if let note = e.note { Text(note).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).padding(.leading, 4) }
                if e.id != trades.last?.id { Divider().overlay(look.theme.line) }
            }
        }
        .padding(14)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
    }

    private func kpi(_ title: String, _ value: String, sub: String? = nil, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tr(title)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(size: 16, weight: .bold).monospacedDigit()).foregroundStyle(color ?? .white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let sub { Text(sub).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.45)).lineLimit(1) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: .infinity, alignment: .leading)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), fill: look.theme.card))
    }
}

@MainActor
struct TraderMirror: View {
    @ObservedObject private var journal = JournalStore.shared
    @ObservedObject private var license = LicenseStore.shared
    @Environment(\.look) private var look

    var body: some View {
        if !license.isActive {
            ProPreview(feature: .traderMirror)
        } else {
            let s = JournalStats(journal.entries)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    fact("Trades with a moved stop", s.movedStopShare.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                    let a = s.afterLoss
                    fact("Opened within 30 min after a loss", a.count == 0 ? "—" : tr("\(a.count) · \(TradeFormat.r(a.totalR))"))
                }
                .fixedSize(horizontal: false, vertical: true)
                let cal = Calendar.current
                let month = JournalStats(journal.entries, filter: JournalFilter(from: cal.dateInterval(of: .month, for: Date())?.start))
                MistakeCostCard(stats: month, unit: nil, title: "Trades with mistake tags this month", pro: true)
                checklistCard(s)
                section("By hour", s.byHour().map { ($0.key + ":00", $0) })
                section("By weekday", s.byWeekday().map { (Calendar.current.shortWeekdaySymbols[(Int($0.key) ?? 1) - 1], $0) })
                section("By asset", s.byAsset.map { ($0.key, $0) })
                section("By side", s.bySide.map { ($0.key, $0) })
                section("By setup tag", s.bySetup.map { ($0.key, $0) })
                section("By mistake tag", s.byMistake.map { ($0.key, $0) })
                Text(tr("Built from your own closed manual and paper trades. Not a recommendation."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.42))
            }
        }
    }

    @ViewBuilder
    private func checklistCard(_ s: JournalStats) -> some View {
        let e = s.checklistEffect
        if e.full.count + e.partial.count > 0 {
            HStack(spacing: 8) {
                fact("Avg R with the full checklist", e.full.avgR.map(TradeFormat.r).map { $0 + " · " + tr("\(e.full.count) trades") } ?? "—")
                fact("Avg R without it", e.partial.avgR.map(TradeFormat.r).map { $0 + " · " + tr("\(e.partial.count) trades") } ?? "—")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tr(title)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            Text(value).font(.system(size: 16, weight: .bold).monospacedDigit())
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), fill: look.theme.card))
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [(String, JournalStats.Bucket)]) -> some View {
        if !rows.isEmpty {
            let mx = max(rows.map { abs($0.1.totalR) }.max() ?? 1, 0.01)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr(title)).font(.system(size: 13, weight: .bold))
                ForEach(rows, id: \.1.id) { label, b in
                    HStack(spacing: 8) {
                        Text(label).font(.system(size: 11.5, weight: .semibold)).frame(width: 90, alignment: .leading).lineLimit(1)
                        GeometryReader { g in
                            Capsule().fill(TradeColors.pnl(b.totalR).opacity(0.8))
                                .frame(width: max(3, g.size.width * CGFloat(abs(b.totalR) / mx)), height: 8)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: 14)
                        Text(TradeFormat.r(b.totalR)).font(.system(size: 11.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(TradeColors.pnl(b.totalR)).frame(width: 66, alignment: .trailing)
                        Text(tr("\(b.count) tr.")).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(14)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
    }
}

@MainActor
struct MistakeCostCard: View {
    let stats: JournalStats
    let unit: String?
    let title: String
    let pro: Bool
    @ObservedObject private var prefs = TradePrefs.shared
    @Environment(\.look) private var look

    var body: some View {
        let c = stats.mistakeCost(Set(prefs.v.mistakeTags))
        let u = unit ?? UserDefaults.standard.string(forKey: "baseCurrency") ?? "USD"
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(title)).font(.system(size: 13, weight: .bold))
            if c.count == 0 {
                Text(stats.totalTrades == 0 ? tr("No closed trades yet.") : tr("No trades with mistake tags. Nothing to add up."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            } else {
                Text(tr("\(c.count) trades with mistake tags came to \(TradeFormat.money(c.money, unit: u))"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(TradeColors.pnl(c.money))
                if pro {
                    if let clean = c.cleanShare {
                        Text(tr("Trades without mistake tags: \(Int((clean * 100).rounded()))%"))
                            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65))
                    }
                    ForEach(c.tags) { t in
                        HStack(spacing: 8) {
                            Text(t.tag).font(.system(size: 11.5, weight: .semibold)).frame(width: 110, alignment: .leading)
                            Text(tr("\(t.count) tr.")).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.white.opacity(0.45))
                            Spacer()
                            Text(TradeFormat.money(t.money, unit: u)).font(.system(size: 11.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(TradeColors.pnl(t.money))
                        }
                    }
                } else {
                    ProPreview(feature: .traderMirror)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
    }
}
