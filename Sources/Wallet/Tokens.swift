import Foundation

struct TokenHolding: Identifiable, Sendable, Equatable {
    let symbol: String
    let amount: Double
    let usd: Double
    var id: String { symbol }
}

enum TokenScanner {
    static let minUSD = 1.0
    static let maxUSD = 1e11
    static let stable: Set<String> = ["USDT", "USDC", "DAI", "FDUSD", "PYUSD", "USDE"]
    static let priceSymbol = ["WBTC": "BTC", "WETH": "ETH", "WSOL": "SOL", "STETH": "ETH", "MSOL": "SOL", "JITOSOL": "SOL"]

    static let ethTokens: [(address: String, symbol: String, decimals: Int)] = [
        ("0xdAC17F958D2ee523a2206206994597C13D831ec7", "USDT", 6),
        ("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "USDC", 6),
        ("0x6B175474E89094C44Da98b954EedeAC495271d0F", "DAI", 18),
        ("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", "WBTC", 8),
        ("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", "WETH", 18),
        ("0x514910771AF9Ca656af840dff83E8264EcF986CA", "LINK", 18),
        ("0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984", "UNI", 18),
        ("0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE", "SHIB", 18),
        ("0x6982508145454Ce325dDbE47a25d4ec3d2311933", "PEPE", 18),
        ("0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6", "POL", 18),
        ("0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1", "ARB", 18),
        ("0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32", "LDO", 18),
        ("0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", "AAVE", 18),
    ]

    static let solMints = [
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": "USDC",
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": "USDT",
        "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN": "JUP",
        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": "BONK",
        "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm": "WIF",
        "jtojtomepa8beP8AuQc6eXt5FriJwfFMwQx2v2f9mCL": "JTO",
        "HZ1JovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3": "PYTH",
        "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R": "RAY",
        "So11111111111111111111111111111111111111112": "WSOL",
        "6p6xgHyF7AeE6TZkSmFsko444wqoP15icUSqi2jfGiPN": "TRUMP",
        "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So": "MSOL",
        "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn": "JITOSOL",
    ]

    static let knownContracts = Set(ethTokens.map { $0.address.lowercased() })
    static let ethRPCs = ["https://ethereum-rpc.publicnode.com", "https://eth.llamarpc.com", "https://rpc.ankr.com/eth"]
    static let solRPCs = ["https://api.mainnet-beta.solana.com"]

    static func tokens(_ chain: Chain, _ address: String, customSolanaRPC: String?) async -> [TokenHolding] {
        let raw: [(symbol: String, amount: Double, usd: Double?)]
        switch chain {
        case .eth: raw = await ethTokens(address)
        case .sol: raw = await solTokens(address, custom: customSolanaRPC)
        case .ton: raw = await tonTokens(address)
        default: return []
        }
        var out: [TokenHolding] = []
        for t in raw where t.amount > 0 {
            var usd = t.usd
            if usd == nil, let p = await price(t.symbol) { usd = p * t.amount }
            if let usd, usd.isFinite, usd >= minUSD, usd < maxUSD { out.append(TokenHolding(symbol: t.symbol, amount: t.amount, usd: usd)) }
        }
        return out.sorted { $0.usd > $1.usd }
    }

    static func price(_ symbol: String) async -> Double? {
        let s = priceSymbol[symbol] ?? symbol
        if stable.contains(s) { return 1 }
        guard let j = try? await Chain.json("https://api.binance.com/api/v3/ticker/price?symbol=\(s)USDT") else { return nil }
        return Double(j["price"] as? String ?? "")
    }

    private static func ethTokens(_ address: String) async -> [(String, Double, Double?)] {
        if let j = try? await Chain.json("https://api.ethplorer.io/getAddressInfo/\(address)?apiKey=freekey"),
           let list = j["tokens"] as? [[String: Any]] {
            return list.compactMap { t in
                guard let info = t["tokenInfo"] as? [String: Any], let symbol = info["symbol"] as? String,
                      let decimals = Int("\(info["decimals"] ?? "")"), let raw = t["balance"] as? Double else { return nil }
                let amount = raw / pow(10, Double(decimals))
                let rate = (info["price"] as? [String: Any])?["rate"] as? Double
                let contract = (info["address"] as? String ?? "").lowercased()
                guard rate != nil || knownContracts.contains(contract) else { return nil }
                return (symbol.uppercased(), amount, rate.map { $0 * amount })
            }
        }
        var out: [(String, Double, Double?)] = []
        let owner = address.lowercased().replacingOccurrences(of: "0x", with: "")
        for t in ethTokens {
            let data = "0x70a08231" + String(repeating: "0", count: 24) + owner
            let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [["to": t.address, "data": data], "latest"]]
            for rpc in ethRPCs {
                guard let j = try? await post(rpc, body), let hex = j["result"] as? String else { continue }
                let value = hexValue(hex) / pow(10, Double(t.decimals))
                if value > 0 { out.append((t.symbol, value, nil)) }
                break
            }
        }
        return out
    }

    private static func solTokens(_ address: String, custom: String?) async -> [(String, Double, Double?)] {
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "getTokenAccountsByOwner",
                                   "params": [address, ["programId": "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"], ["encoding": "jsonParsed"]]]
        for rpc in ([custom].compactMap { $0 }.filter { !$0.isEmpty } + solRPCs) {
            guard let j = try? await post(rpc, body), let value = (j["result"] as? [String: Any])?["value"] as? [[String: Any]] else { continue }
            var totals: [String: Double] = [:]
            for acc in value {
                guard let info = (((acc["account"] as? [String: Any])?["data"] as? [String: Any])?["parsed"] as? [String: Any])?["info"] as? [String: Any],
                      let mint = info["mint"] as? String, let symbol = solMints[mint],
                      let amount = (info["tokenAmount"] as? [String: Any])?["uiAmount"] as? Double else { continue }
                totals[symbol, default: 0] += amount
            }
            return totals.map { ($0.key, $0.value, nil) }
        }
        return []
    }

    static let tonJettons = [
        "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs": ("USDT", 6),
        "EQAvlWFDxGF2lXm67y4yzC17wYKD9A0guwPkMs1gOsM__NOT": ("NOT", 9),
        "EQCvxJy4eG8hyHBFsZ7eePxrRsUQSFE_jpptRAYBmcG_DOGS": ("DOGS", 9),
    ]

    private static func tonTokens(_ address: String) async -> [(String, Double, Double?)] {
        if let enc = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
           let j = try? await Chain.json("https://tonapi.io/v2/accounts/\(enc)/jettons?currencies=usd"),
           let list = j["balances"] as? [[String: Any]] {
            return list.compactMap { b in
                guard let jt = b["jetton"] as? [String: Any], jt["verification"] as? String == "whitelist",
                      let symbol = jt["symbol"] as? String, let decimals = (jt["decimals"] as? NSNumber)?.intValue,
                      let raw = Double(b["balance"] as? String ?? ""),
                      let usd = (((b["price"] as? [String: Any])?["prices"] as? [String: Any])?["USD"] as? NSNumber)?.doubleValue,
                      usd > 0 else { return nil }
                let amount = raw / pow(10, Double(decimals))
                return (symbol.uppercased().replacingOccurrences(of: "₮", with: "T"), amount, usd * amount)
            }
        }
        guard let enc = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let j = try? await Chain.json("https://toncenter.com/api/v3/jetton/wallets?owner_address=\(enc)&limit=100"),
              let list = j["jetton_wallets"] as? [[String: Any]] else { return [] }
        let known = Dictionary(uniqueKeysWithValues: tonJettons.compactMap { k, v in rawTON(k).map { ($0, v) } })
        return list.compactMap { w in
            guard let master = (w["jetton"] as? String)?.uppercased(), let (symbol, decimals) = known[master],
                  let raw = Double(w["balance"] as? String ?? "") else { return nil }
            return (symbol, raw / pow(10, Double(decimals)), nil)
        }
    }

    static func rawTON(_ friendly: String) -> String? {
        var b64 = friendly.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let d = Data(base64Encoded: b64), d.count == 36 else { return nil }
        let wc = Int8(bitPattern: d[1])
        return "\(wc):" + d[2..<34].map { String(format: "%02X", $0) }.joined()
    }

    private static func post(_ url: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw MarketError.badData }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.timeoutInterval = 15
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let j = try JSONSerialization.jsonObject(with: d) as? [String: Any],
              j["error"] == nil else { throw MarketError.badData }
        return j
    }

    static func hexValue(_ hex: String) -> Double {
        var v = 0.0
        for ch in hex.dropFirst(2) { guard let d = ch.hexDigitValue else { return 0 }; v = v * 16 + Double(d) }
        return v
    }
}
