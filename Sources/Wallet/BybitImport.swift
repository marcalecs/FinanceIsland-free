import CryptoKit
import SwiftUI

enum BybitAccount {
    static let host = "https://api.bybit.com"

    static func signed(_ path: String, query: String, key: String, secret: String) async throws -> [String: Any] {
        let ts = String(Int(Date().timeIntervalSince1970 * 1000)), window = "10000"
        let sig = HMAC<SHA256>.authenticationCode(for: Data((ts + key + window + query).utf8), using: SymmetricKey(data: Data(secret.utf8)))
            .map { String(format: "%02x", $0) }.joined()
        guard let u = URL(string: host + path + (query.isEmpty ? "" : "?" + query)) else { throw MarketError.badData }
        var r = URLRequest(url: u)
        r.timeoutInterval = 15
        r.setValue(key, forHTTPHeaderField: "X-BAPI-API-KEY")
        r.setValue(ts, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
        r.setValue(window, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
        r.setValue(sig, forHTTPHeaderField: "X-BAPI-SIGN")
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw MarketError.badData }
        if let code = (j["retCode"] as? NSNumber)?.intValue, code != 0 {
            throw NSError(domain: "Bybit", code: code, userInfo: [NSLocalizedDescriptionKey: j["retMsg"] as? String ?? "Bybit error \(code)"])
        }
        return j["result"] as? [String: Any] ?? [:]
    }

    static func checkReadOnly(key: String, secret: String) async throws {
        let r = try await signed("/v5/user/query-api", query: "", key: key, secret: secret)
        guard (r["readOnly"] as? NSNumber)?.intValue == 1 else {
            throw NSError(domain: "Bybit", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "This key can trade or move funds. Create a read-only key and try again."])
        }
    }

    static func closedTrades(from: Date, to: Date, key: String, secret: String) async throws -> [JournalEntry] {
        var out: [JournalEntry] = []
        var start = from
        while start < to {
            let end = min(start.addingTimeInterval(7 * 86_400 - 1), to)
            var cursor = ""
            repeat {
                var q = "category=linear&endTime=\(ms(end))&limit=100&startTime=\(ms(start))"
                if !cursor.isEmpty { q = "category=linear&cursor=\(cursor)&endTime=\(ms(end))&limit=100&startTime=\(ms(start))" }
                let r = try await signed("/v5/position/closed-pnl", query: q, key: key, secret: secret)
                out += (r["list"] as? [[String: Any]] ?? []).compactMap(entry)
                cursor = r["nextPageCursor"] as? String ?? ""
                try await Task.sleep(nanoseconds: 200_000_000)
            } while !cursor.isEmpty
            start = end.addingTimeInterval(0.001)
        }
        return out
    }

    private static func ms(_ d: Date) -> Int { Int(d.timeIntervalSince1970 * 1000) }

    static func entry(_ j: [String: Any]) -> JournalEntry? {
        func num(_ k: String) -> Double? { Double(j[k] as? String ?? "") ?? (j[k] as? NSNumber)?.doubleValue }
        guard let symbol = j["symbol"] as? String, let order = j["orderId"] as? String, let entry = num("avgEntryPrice"),
              let exit = num("avgExitPrice"), let qty = num("closedSize") ?? num("qty"), let pnl = num("closedPnl"),
              let created = num("createdTime"), let updated = num("updatedTime") else { return nil }
        let side: Signal = (j["side"] as? String) == "Buy" ? .sell : .buy
        let gross = (side == .sell ? entry - exit : exit - entry) * qty
        var e = JournalEntry(asset: symbol.hasSuffix("USDT") ? String(symbol.dropLast(4)) : symbol, kind: .trade, side: side, entry: entry, text: "")
        e.at = Date(timeIntervalSince1970: created / 1000)
        e.status = .closed
        e.exit = exit
        e.mode = .manual
        e.qty = qty
        e.grossPnL = gross
        e.netPnL = pnl
        e.commission = gross - pnl
        e.currency = "USD"
        e.openedAt = e.at
        e.closedAt = Date(timeIntervalSince1970: updated / 1000)
        e.exitReason = .manual
        e.importedFrom = "bybit"
        e.externalIDs = ["bybit:" + order]
        e.tags = ["futures"]
        return e
    }
}

@MainActor
final class BybitImporter: ObservableObject {
    static let shared = BybitImporter()

    @Published private(set) var connected = AccountKeychain.get("bybit.key") != nil
    @Published private(set) var running = false
    @Published private(set) var message: String?

    func connect(key: String, secret: String) {
        let key = key.trimmingCharacters(in: .whitespaces), secret = secret.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !secret.isEmpty, !running else { return }
        running = true
        Task {
            do {
                try await BybitAccount.checkReadOnly(key: key, secret: secret)
                AccountKeychain.set("bybit.key", key)
                AccountKeychain.set("bybit.secret", secret)
                connected = true
                message = tr("Connected with a read-only key")
            } catch {
                message = error.localizedDescription
            }
            running = false
        }
    }

    func disconnect() {
        AccountKeychain.set("bybit.key", nil)
        AccountKeychain.set("bybit.secret", nil)
        connected = false
        message = nil
    }

    func run(days: Int) {
        guard !running, let key = AccountKeychain.get("bybit.key"), let secret = AccountKeychain.get("bybit.secret") else { return }
        running = true
        message = tr("Reading closed trades…")
        Task {
            do {
                let to = Date()
                let list = try await BybitAccount.closedTrades(from: to.addingTimeInterval(-Double(days) * 86_400), to: to, key: key, secret: secret)
                let known = Set(JournalStore.shared.entries.compactMap { $0.externalIDs?.first })
                let fresh = list.filter { !known.contains($0.externalIDs?.first ?? "") }
                if !fresh.isEmpty {
                    JournalStore.shared.importTrades(fresh)
                    TradeDesk.shared.queueTags(fresh.map(\.id))
                }
                message = tr("Added \(fresh.count) trades · \(list.count - fresh.count) already in the journal")
            } catch {
                message = error.localizedDescription
            }
            running = false
        }
    }
}

@MainActor
struct BybitImportCard: View {
    @ObservedObject private var importer = BybitImporter.shared
    @AppStorage("bybitImportDays") private var days = 30
    @State private var key = ""
    @State private var secret = ""
    @Environment(\.look) private var look

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("B").font(.system(size: 12, weight: .heavy)).foregroundStyle(.black)
                    .frame(width: 22, height: 22).background(Circle().fill(Color(red: 0.97, green: 0.65, blue: 0.1)))
                Text(tr("Import trades from Bybit")).font(.system(size: 13, weight: .bold))
                Spacer()
                if importer.connected {
                    Button(tr("Disconnect")) { importer.disconnect() }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
            }
            if importer.connected {
                HStack(spacing: 8) {
                    PillPicker(options: [7, 30, 90], selection: $days, label: { tr("\($0) days") }, minWidth: 54)
                    Spacer()
                    Button(tr(importer.running ? "Importing…" : "Import")) { importer.run(days: days) }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(look.accent.opacity(0.85)))
                        .disabled(importer.running)
                }
            } else {
                HStack(spacing: 8) {
                    field(TextField(tr("API key"), text: $key))
                    field(SecureField(tr("Secret"), text: $secret))
                    Button(tr("Connect")) { importer.connect(key: key, secret: secret); secret = "" }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(Capsule().fill(look.accent.opacity(0.85)))
                        .disabled(importer.running || key.isEmpty || secret.isEmpty)
                }
            }
            if let m = importer.message {
                Text(tr(m)).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Closed USDT perpetual trades with fees and funding. Use a read-only key: keys that can trade or withdraw are refused, and the key stays in the macOS Keychain."))
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
    }

    private func field(_ f: some View) -> some View {
        f.textFieldStyle(.plain).font(.system(size: 12).monospacedDigit())
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.theme.chip))
    }
}
