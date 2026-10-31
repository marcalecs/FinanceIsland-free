import AppKit
import SwiftUI

@MainActor
struct WalletView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var rates: RateStore
    @ObservedObject var settings: AppSettings
    @ObservedObject private var portfolio = PortfolioStore.shared
    @ObservedObject private var perps = WalletPerps.shared
    @Environment(\.look) private var look
    @State private var copied: String?

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let subtitle: String
        let address: String?
        let amount: Double?
        let usd: Double?
        let color: Color
        let failed: Bool
    }

    private var walletItems: [Item] {
        var out: [Item] = []
        if let a = settings.walletAddress {
            let b = rates.ethBalance
            out.append(Item(id: "main", symbol: "ETH", title: tr("Main wallet"), subtitle: "Ethereum", address: a,
                            amount: b, usd: b.flatMap { b in portfolio.prices[.eth].map { b * $0 } },
                            color: Self.color(.eth), failed: false))
        }
        for w in portfolio.wallets {
            out.append(Item(id: w.id.uuidString, symbol: w.chain.symbol, title: w.label, subtitle: w.chain.name, address: w.address,
                            amount: portfolio.balances[w.id], usd: portfolio.usd(w), color: Self.color(w.chain),
                            failed: portfolio.errors[w.id] != nil))
            for t in portfolio.tokens[w.id] ?? [] {
                out.append(Item(id: w.id.uuidString + "." + t.symbol, symbol: t.symbol, title: t.symbol,
                                subtitle: w.label + " · " + tr("token"), address: nil, amount: t.amount, usd: t.usd,
                                color: Self.color(t.symbol), failed: false))
            }
        }
        return out
    }

    private var binanceItems: [Item] {
        portfolio.binanceHoldings.map { h in
            Item(id: "bn." + h.asset, symbol: h.asset, title: h.asset, subtitle: "Binance", address: nil,
                 amount: h.amount, usd: h.usd, color: Self.color(h.asset), failed: false)
        }
    }

    private var total: Double { (walletItems + binanceItems).compactMap(\.usd).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if walletItems.isEmpty && !portfolio.binanceConnected && perps.open.isEmpty {
                emptyState
            } else {
                PageScroll {
                    VStack(alignment: .leading, spacing: 14) {
                        hero
                        if !walletItems.isEmpty { section(tr("Wallets"), walletItems) }
                        if portfolio.binanceConnected {
                            section(tr("Binance · read-only"), binanceItems.isEmpty ? [] : Array(binanceItems.prefix(12)))
                        }
                        WalletPerpsSection()
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.never)
                .verticalOnly()
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(width: Layout.pageW, height: RenderFlags.noScroll ? nil : Layout.pageH, alignment: .top)
        .onAppear { portfolio.refresh(); rates.walletChanged() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(symbol: "chevron.left", label: "Back to Portfolio") { state.mode = .longTerm }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.system(size: 17, weight: .bold))
                Text(portfolio.updated.map { tr("updated \(Fmt.date($0, "HH:mm"))") } ?? tr("Loading balances…"))
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            CircleIconButton(symbol: "arrow.clockwise", label: "Refresh") { portfolio.refresh(); rates.walletChanged() }
                .rotationEffect(.degrees(portfolio.loading ? 360 : 0))
                .animation(portfolio.loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: portfolio.loading)
            CircleIconButton(symbol: "plus", label: "Add wallet") { state.openSettings(.portfolio) }
                .help(tr("Add a wallet or sign in to an account"))
        }
        .frame(height: 34)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? tr(part) : tr(part) + ", " + name
    }

    private var hero: some View {
        let items = (walletItems + binanceItems).filter { ($0.usd ?? 0) > 0 }.sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
        let sum = max(items.compactMap(\.usd).reduce(0, +), 1e-9)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("Total balance")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(tr("\(walletItems.count) wallets") + (portfolio.binanceConnected ? " · Binance" : ""))
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
            }
            Text("$" + Fmt.number(total, min: 2, max: 2))
                .font(.system(size: 38, weight: .heavy).monospacedDigit())
                .contentTransition(.numericText(value: total))
                .animation(.smooth(duration: 0.4), value: total)
                .lineLimit(1).minimumScaleFactor(0.6)
            if !items.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(items) { it in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(it.color)
                                .frame(width: max(3, (g.size.width - CGFloat(items.count - 1) * 2) * CGFloat((it.usd ?? 0) / sum)))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(Capsule())
                HStack(spacing: 14) {
                    ForEach(items.prefix(5)) { it in
                        HStack(spacing: 5) {
                            Circle().fill(it.color).frame(width: 7, height: 7)
                            Text(it.symbol).font(.system(size: 11.5, weight: .semibold))
                            Text(String(format: "%.0f%%", (it.usd ?? 0) / sum * 100))
                                .font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: look.corners.card + 4, style: .continuous)
                .fill(LinearGradient(colors: [look.accent.opacity(0.55), Accent.blue.color.opacity(0.35), Accent.purple.color.opacity(0.35)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(RoundedRectangle(cornerRadius: look.corners.card + 4, style: .continuous).fill(look.theme.card))
        )
        .overlay(RoundedRectangle(cornerRadius: look.corners.card + 4, style: .continuous).stroke(.white.opacity(0.14)))
    }

    private func section(_ title: String, _ items: [Item]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 4)
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(portfolio.binanceError.map { tr($0) } ?? tr("No balances yet"))
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                    if i > 0 { Rectangle().fill(look.theme.line).frame(height: 1).padding(.leading, 56) }
                    row(it)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        }
    }

    private func row(_ it: Item) -> some View {
        let share = total > 0 ? (it.usd ?? 0) / total : 0
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(it.color.opacity(0.22))
                Circle().stroke(it.color.opacity(0.6), lineWidth: 1)
                Text(String(it.symbol.prefix(4))).font(.system(size: it.symbol.count > 3 ? 9 : 10.5, weight: .heavy)).foregroundStyle(it.color)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(it.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(it.subtitle).foregroundStyle(.white.opacity(0.5))
                    if let a = it.address {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(a, forType: .string)
                            withAnimation(.smooth(duration: 0.2)) { copied = it.id }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == it.id { withAnimation { copied = nil } } }
                        } label: {
                            HStack(spacing: 3) {
                                Text(copied == it.id ? tr("Copied") : Fmt.shortAddress(a)).font(.system(size: 11).monospacedDigit())
                                Image(systemName: copied == it.id ? "checkmark" : "doc.on.doc").font(.system(size: 9))
                            }
                            .foregroundStyle(copied == it.id ? look.accent : .white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .help(tr("Copy the address"))
                    }
                }
                .font(.system(size: 11.5))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let u = it.usd {
                    Text("$" + Fmt.number(u, min: 2, max: 2)).font(.system(size: 14, weight: .bold).monospacedDigit())
                } else if it.failed {
                    Text(tr("unavailable")).font(.system(size: 12)).foregroundStyle(look.trend.red)
                }
                if let a = it.amount {
                    Text(Fmt.number(a, min: 2, max: 6) + " " + it.symbol).font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                } else if !it.failed {
                    ProgressView().controlSize(.mini)
                }
            }
            if share > 0 {
                Text(String(format: "%.0f%%", share * 100))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(it.color)
                    .frame(width: 44, height: 22)
                    .background(Capsule().fill(it.color.opacity(0.14)))
            }
        }
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(LinearGradient(colors: [look.accent.opacity(0.45), Accent.blue.color.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "wallet.bifold.fill").font(.system(size: 30, weight: .semibold))
            }
            .frame(width: 76, height: 76)
            Text(tr("Your wallet, at a glance")).font(.system(size: 18, weight: .bold))
            Text(tr("Watch public addresses on Ethereum, Bitcoin, Solana or TON (including the TON wallet in Wallet), sign in to Binance with a read-only key, or bring in Wallet Perps from the Inbox. Nothing can ever be moved from here."))
                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            HStack(spacing: 10) {
                PillLink(title: "Add wallet", symbol: "plus") { state.openSettings(.portfolio) }
                PillLink(title: "Sign in to Binance", symbol: "person.badge.key") { state.openSettings(.portfolio) }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    static func color(_ c: Chain) -> Color {
        switch c {
        case .eth: return Color(red: 0.45, green: 0.52, blue: 0.95)
        case .btc: return Color(red: 0.97, green: 0.6, blue: 0.15)
        case .sol: return Color(red: 0.6, green: 0.35, blue: 0.98)
        case .ton: return Color(red: 0.0, green: 0.6, blue: 0.95)
        }
    }

    static func color(_ asset: String) -> Color {
        switch asset {
        case "BTC": return color(.btc)
        case "ETH": return color(.eth)
        case "SOL": return color(.sol)
        case "TON": return color(.ton)
        case "USDT", "USDC", "FDUSD", "DAI": return Color(red: 0.2, green: 0.75, blue: 0.55)
        case "BNB": return Color(red: 0.95, green: 0.73, blue: 0.18)
        default:
            let h = Double(asset.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
            return Color(hue: h, saturation: 0.55, brightness: 0.9)
        }
    }
}
