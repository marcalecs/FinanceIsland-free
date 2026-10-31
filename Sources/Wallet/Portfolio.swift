import CryptoKit
import Foundation

enum Chain: String, CaseIterable, Codable, Identifiable, Sendable {
    case eth, btc, sol, ton
    var id: String { rawValue }
    var name: String {
        switch self {
        case .eth: return "Ethereum"
        case .btc: return "Bitcoin"
        case .sol: return "Solana"
        case .ton: return "TON"
        }
    }
    var symbol: String { rawValue.uppercased() }
    var placeholder: String {
        switch self {
        case .eth: return "0x…"
        case .btc: return "bc1… / 1… / 3…"
        case .sol: return "Base58 address"
        case .ton: return "EQ… / UQ…"
        }
    }

    func isValid(_ a: String) -> Bool {
        let b58 = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        switch self {
        case .eth: return a.count == 42 && a.hasPrefix("0x") && a.dropFirst(2).allSatisfy(\.isHexDigit)
        case .btc:
            if a.lowercased().hasPrefix("bc1") { return (14...74).contains(a.count) && a.dropFirst(3).allSatisfy { $0.isLetter || $0.isNumber } }
            return (a.hasPrefix("1") || a.hasPrefix("3")) && (26...35).contains(a.count) && a.unicodeScalars.allSatisfy { b58.contains($0) }
        case .sol: return (32...44).contains(a.count) && a.unicodeScalars.allSatisfy { b58.contains($0) }
        case .ton:
            return a.count == 48 && a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                || (a.hasPrefix("0:") || a.hasPrefix("-1:")) && a.count >= 66
        }
    }

    func balance(_ a: String) async throws -> Double {
        switch self {
        case .eth:
            return try await DataService.ethBalance(a)
        case .btc:
            let j = try await Self.json("https://mempool.space/api/address/\(a)")
            func sats(_ k: String) -> Double {
                let s = j[k] as? [String: Any]
                return ((s?["funded_txo_sum"] as? Double) ?? 0) - ((s?["spent_txo_sum"] as? Double) ?? 0)
            }
            return (sats("chain_stats") + sats("mempool_stats")) / 1e8
        case .sol:
            var r = URLRequest(url: URL(string: "https://api.mainnet-beta.solana.com")!)
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "getBalance", "params": [a]])
            r.timeoutInterval = 15
            let (d, _) = try await URLSession.shared.data(for: r)
            let j = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            guard let v = (j?["result"] as? [String: Any])?["value"] as? Double else { throw MarketError.badData }
            return v / 1e9
        case .ton:
            let j = try await Self.json("https://toncenter.com/api/v2/getAddressBalance?address=\(a)")
            if let s = j["result"] as? String, let v = Double(s) { return v / 1e9 }
            if let v = j["result"] as? Double { return v / 1e9 }
            throw MarketError.badData
        }
    }

    static func json(_ url: String, headers: [String: String] = [:]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw MarketError.badData }
        var r = URLRequest(url: u)
        r.timeoutInterval = 15
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let (d, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["msg"] as? String
            throw NSError(domain: "HTTP", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "HTTP \(h.statusCode)"])
        }
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw MarketError.badData }
        return j
    }
}

struct WatchedWallet: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var chain: Chain
    var address: String
    var label: String
}

enum AccountKeychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "FinanceIsland.accounts",
         kSecAttrAccount as String: account]
    }
    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ account: String, _ value: String?) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

enum BinanceAccount {
    struct Holding: Identifiable, Sendable { let asset: String; let amount: Double; let usd: Double?; var id: String { asset } }

    static func signed(_ path: String, key: String, secret: String, extra: String = "", host: String = "https://api.binance.com") async throws -> Any {
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let qs = (extra.isEmpty ? "" : extra + "&") + "recvWindow=10000&timestamp=\(ts)"
        let sig = HMAC<SHA256>.authenticationCode(for: Data(qs.utf8), using: SymmetricKey(data: Data(secret.utf8)))
            .map { String(format: "%02x", $0) }.joined()
        guard let u = URL(string: "\(host)\(path)?\(qs)&signature=\(sig)") else { throw MarketError.badData }
        var r = URLRequest(url: u)
        r.timeoutInterval = 15
        r.setValue(key, forHTTPHeaderField: "X-MBX-APIKEY")
        let (d, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: d) as? [String: Any])?["msg"] as? String
            throw NSError(domain: "Binance", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: msg ?? "Binance error \(h.statusCode)"])
        }
        return try JSONSerialization.jsonObject(with: d)
    }

    static func checkReadOnly(key: String, secret: String) async throws {
        guard let r = try await signed("/sapi/v1/account/apiRestrictions", key: key, secret: secret) as? [String: Any] else {
            throw MarketError.badData
        }
        let risky = ["enableWithdrawals", "enableSpotAndMarginTrading", "enableFutures", "enableMargin",
                     "enableInternalTransfer", "permitsUniversalTransfer", "enableVanillaOptions"]
        if risky.contains(where: { (r[$0] as? Bool) == true }) {
            throw NSError(domain: "Binance", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "This key can trade or move funds. Create a key with only “Enable Reading” and try again."])
        }
    }

    static func holdings(key: String, secret: String) async throws -> [Holding] {
        guard let acc = try await signed("/api/v3/account", key: key, secret: secret, extra: "omitZeroBalances=true") as? [String: Any],
              let bal = acc["balances"] as? [[String: Any]] else { throw MarketError.badData }
        var px: [String: Double] = [:]
        if let u = URL(string: "https://api.binance.com/api/v3/ticker/price"),
           let (d, _) = try? await URLSession.shared.data(from: u),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            for t in arr { if let s = t["symbol"] as? String, let p = Double(t["price"] as? String ?? "") { px[s] = p } }
        }
        let stable: Set<String> = ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "DAI", "USD"]
        return bal.compactMap { b in
            guard let a = b["asset"] as? String else { return nil }
            let amt = (Double(b["free"] as? String ?? "") ?? 0) + (Double(b["locked"] as? String ?? "") ?? 0)
            guard amt > 0 else { return nil }
            let usd: Double? = stable.contains(a) ? amt : px[a + "USDT"].map { $0 * amt } ?? px[a + "USDC"].map { $0 * amt }
            return Holding(asset: a, amount: amt, usd: usd)
        }
        .sorted { ($0.usd ?? 0) > ($1.usd ?? 0) }
    }
}

@MainActor
final class PortfolioStore: ObservableObject {
    static let shared = PortfolioStore()

    @Published var wallets: [WatchedWallet] = [] { didSet { save() } }
    @Published private(set) var balances: [UUID: Double] = [:]
    @Published private(set) var tokens: [UUID: [TokenHolding]] = [:]
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var prices: [Chain: Double] = [:]
    @Published private(set) var binanceConnected = AccountKeychain.get("binance.key") != nil
    @Published private(set) var binanceHoldings: [BinanceAccount.Holding] = []
    @Published private(set) var binanceError: String?
    @Published private(set) var loading = false
    @Published private(set) var updated: Date?

    private init() {
        if let d = UserDefaults.standard.data(forKey: "watchedWallets"),
           let w = try? JSONDecoder().decode([WatchedWallet].self, from: d) { wallets = w }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(wallets) { UserDefaults.standard.set(d, forKey: "watchedWallets") }
    }

    func usd(_ w: WatchedWallet) -> Double? { balances[w.id].flatMap { b in prices[w.chain].map { b * $0 } } }
    var binanceUSD: Double { binanceHoldings.compactMap(\.usd).reduce(0, +) }
    func tokensUSD(_ w: WatchedWallet) -> Double { (tokens[w.id] ?? []).map(\.usd).reduce(0, +) }
    var totalUSD: Double { wallets.compactMap(usd).reduce(0, +) + wallets.map(tokensUSD).reduce(0, +) + binanceUSD }

    func add(_ chain: Chain, _ address: String, label: String) {
        wallets.append(WatchedWallet(chain: chain, address: address, label: label.isEmpty ? chain.name : label))
        refresh()
    }

    func remove(_ w: WatchedWallet) {
        wallets.removeAll { $0.id == w.id }
        balances[w.id] = nil
        tokens[w.id] = nil
        errors[w.id] = nil
    }

    func refresh() {
        WalletPerps.shared.scan()
        loading = true
        let ws = wallets, connected = binanceConnected
        Task {
            async let pricesTask = Self.fetchPrices()
            await withTaskGroup(of: (UUID, Double?, String?).self) { g in
                for w in ws {
                    g.addTask {
                        do { return (w.id, try await w.chain.balance(w.address), nil) }
                        catch { return (w.id, nil, "Couldn't read the balance") }
                    }
                }
                for await (id, b, e) in g { balances[id] = b ?? balances[id]; errors[id] = e }
            }
            let rpc = AccountKeychain.get("solana.rpc")
            await withTaskGroup(of: (UUID, [TokenHolding]).self) { g in
                for w in ws where w.chain == .eth || w.chain == .sol || w.chain == .ton {
                    g.addTask { (w.id, await TokenScanner.tokens(w.chain, w.address, customSolanaRPC: rpc)) }
                }
                for await (id, list) in g where !list.isEmpty || tokens[id] == nil { tokens[id] = list }
            }
            prices = await pricesTask
            if connected, let k = AccountKeychain.get("binance.key"), let s = AccountKeychain.get("binance.secret") {
                do { binanceHoldings = try await BinanceAccount.holdings(key: k, secret: s); binanceError = nil }
                catch { binanceError = error.localizedDescription }
            }
            updated = Date()
            loading = false
        }
    }

    private static func fetchPrices() async -> [Chain: Double] {
        var out: [Chain: Double] = [:]
        for c in Chain.allCases {
            if let j = try? await Chain.json("https://api.binance.com/api/v3/ticker/price?symbol=\(c.symbol)USDT"),
               let p = Double(j["price"] as? String ?? "") { out[c] = p }
        }
        return out
    }

    func connectBinance(key: String, secret: String) async -> String? {
        do {
            try await BinanceAccount.checkReadOnly(key: key, secret: secret)
            binanceHoldings = try await BinanceAccount.holdings(key: key, secret: secret)
            AccountKeychain.set("binance.key", key)
            AccountKeychain.set("binance.secret", secret)
            binanceConnected = true
            binanceError = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func disconnectBinance() {
        AccountKeychain.set("binance.key", nil)
        AccountKeychain.set("binance.secret", nil)
        binanceConnected = false
        binanceHoldings = []
        binanceError = nil
    }

    func eraseAll() {
        disconnectBinance()
        wallets = []
        balances = [:]
        tokens = [:]
        errors = [:]
        AccountKeychain.set("solana.rpc", nil)
    }
}
