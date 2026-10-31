import CryptoKit
import Foundation

struct License: Equatable, Sendable {
    let sub: Int
    let dev: String
    let plan: String
    let iat: Date
    let exp: Date
}

enum LicenseError: LocalizedError, Equatable {
    case malformed, badSignature, otherMac, expired(Date), clockBehind, noPublicKey

    var errorDescription: String? {
        switch self {
        case .malformed: return "This is not a FinanceIsland licence"
        case .badSignature: return "The licence signature is not valid"
        case .otherMac: return "This licence was issued for another Mac"
        case .expired: return "This licence has expired: renew in the bot"
        case .clockBehind: return "The Mac's clock is behind: set the correct date and time"
        case .noPublicKey: return "This build has no licence key"
        }
    }
}

enum LicenseVerifier {
    static let prefix = "FI1"
    static let grace: TimeInterval = 3 * 86_400
    static let clockTolerance: TimeInterval = 86_400

    static func base64url(_ s: Substring) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        t += String(repeating: "=", count: (4 - t.count % 4) % 4)
        return Data(base64Encoded: t)
    }

    static func parse(_ text: String, publicKey: String) throws -> License {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix, let payload = base64url(parts[1]), let signature = base64url(parts[2]) else {
            throw LicenseError.malformed
        }
        guard let raw = base64url(Substring(publicKey)), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
            throw LicenseError.noPublicKey
        }
        guard key.isValidSignature(signature, for: payload) else { throw LicenseError.badSignature }
        guard let j = try? JSONSerialization.jsonObject(with: payload) as? [String: Any], (j["v"] as? Int) == 1,
              let sub = j["sub"] as? Int, let dev = j["dev"] as? String, let plan = j["plan"] as? String,
              let iat = j["iat"] as? Double, let exp = j["exp"] as? Double else { throw LicenseError.malformed }
        return License(sub: sub, dev: dev, plan: plan, iat: Date(timeIntervalSince1970: iat), exp: Date(timeIntervalSince1970: exp))
    }

    static func validate(_ l: License, device: String, now: Date, latestSeen: Date) throws {
        guard l.dev == device else { throw LicenseError.otherMac }
        if latestSeen.timeIntervalSince(now) > clockTolerance { throw LicenseError.clockBehind }
        if now > l.exp.addingTimeInterval(grace) { throw LicenseError.expired(l.exp) }
    }

    static func check(_ text: String, publicKey: String, device: String, now: Date, latestSeen: Date) throws -> License {
        let l = try parse(text, publicKey: publicKey)
        try validate(l, device: device, now: now, latestSeen: latestSeen)
        return l
    }
}
