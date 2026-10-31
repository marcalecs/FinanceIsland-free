import SwiftUI

@MainActor
enum SmartEntryRunner {
    static func describe(_ s: SmartEntry) -> String {
        switch s {
        case let .hold(symbol, amount, price):
            return tr("Add \(Fmt.number(amount, min: 0, max: 6)) \(symbol) to the portfolio") + (price.map { " @ " + Fmt.number($0, min: 0, max: 6) } ?? "")
        case let .trade(side, symbol, entry, stop, target, exit, _):
            var parts = [(side == .sell ? "SHORT " : "LONG ") + symbol]
            if let entry { parts.append("@ " + Fmt.number(entry, min: 0, max: 6)) }
            if let stop { parts.append(tr("stop") + " " + Fmt.number(stop, min: 0, max: 6)) }
            if let target { parts.append(tr("target") + " " + Fmt.number(target, min: 0, max: 6)) }
            if let exit { parts.append(tr("closed") + " " + Fmt.number(exit, min: 0, max: 6)) }
            return parts.joined(separator: " · ")
        }
    }

    static let popular = ["AAPL", "NVDA", "MSFT", "TSLA", "AMZN", "GOOGL", "META", "SPY", "QQQ", "VOO"]

    static var symbols: [String] {
        var seen = Set<String>(), out: [String] = []
        let own = LongTermStore.shared.manual.map { $0.symbol.replacingOccurrences(of: "USDT", with: "") }
            + JournalStore.shared.entries.map(\.asset)
        for s in own + Catalog.crypto.map(\.code) + popular where seen.insert(s.uppercased()).inserted { out.append(s.uppercased()) }
        return out
    }

    static func price(_ symbol: String) -> Double? {
        TradeDesk.shared.quote(symbol) ?? LongTermStore.shared.prices[symbol] ?? LongTermStore.shared.prices[symbol + "USDT"]
    }

    static func suggestion(_ text: String) -> String? {
        SmartComplete.suggest(text, symbols: symbols, price: price)
    }

    @discardableResult
    static func run(_ s: SmartEntry, text: String) -> String {
        switch s {
        case let .hold(symbol, amount, price):
            LongTermStore.shared.add(symbol: symbol, crypto: Catalog.crypto.contains { $0.code == symbol }, amount: amount, entry: price)
            return tr("Added to the portfolio")
        case let .trade(side, symbol, entry, stop, target, exit, qty):
            let desk = TradeDesk.shared
            if exit == nil, let stop, let price = entry ?? desk.quote(symbol) {
                return desk.openManual(asset: symbol, itemID: nil, side: side, stop: stop, target: target, price: price)
                    ? tr("Trade opened") : tr("The trade couldn't be opened.")
            }
            var e = JournalEntry(asset: symbol, kind: .trade, side: side, entry: entry, stop: stop, text: text)
            e.target = target
            e.qty = qty
            e.mode = .manual
            e.openedAt = Date()
            if let exit {
                e.status = .closed
                e.exit = exit
                e.closedAt = Date()
            } else {
                e.status = .open
            }
            JournalStore.shared.add(e)
            return tr("Saved to the journal")
        }
    }
}

@MainActor
struct SmartEntryField: View {
    var placeholder = "long BTC 67000 stop 66000 target 70000 · bought 10 NVDA at 131"
    @State private var text = ""
    @State private var result: String?
    @Environment(\.look) private var look

    var body: some View {
        let parsed = SmartEntry.parse(text)
        let ghost = SmartEntryRunner.suggestion(text)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").font(.system(size: 12, weight: .semibold)).foregroundStyle(look.accent)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .onSubmit(submit)
                    .onChange(of: text) { _, _ in result = nil }
                    .onKeyPress(.tab) {
                        guard let ghost else { return .ignored }
                        text = ghost
                        return .handled
                    }
                    .overlay(alignment: .leading) {
                        if let ghost, ghost.count > text.count {
                            (Text(text).foregroundStyle(.clear) + Text(String(ghost.dropFirst(text.count))).foregroundStyle(.white.opacity(0.32)))
                                .font(.system(size: 12.5)).lineLimit(1).allowsHitTesting(false)
                        }
                    }
                if ghost != nil {
                    Text("⇥ Tab").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                        .padding(.horizontal, 6).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.2)))
                }
                if parsed != nil {
                    Button(action: submit) {
                        Image(systemName: "return").font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 22).background(Capsule().fill(look.accent.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.chip))
            if let parsed {
                Text(SmartEntryRunner.describe(parsed)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            } else if let result {
                Text(result).font(.system(size: 11, weight: .semibold)).foregroundStyle(look.accent)
            } else if !text.isEmpty && ghost == nil {
                Text(tr("Start with buy, long or short, then the ticker and prices")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func submit() {
        guard let p = SmartEntry.parse(text) else { return }
        let r = SmartEntryRunner.run(p, text: text)
        text = ""
        result = r
    }
}
