import CryptoKit
import Foundation
import IOKit

enum DeviceIdentity {
    static let hash: String = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        let raw = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String ?? "unknown"
        let digest = SHA256.hash(data: Data(("FinanceIsland.device." + raw).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }()

    static var code: String { String(hash.prefix(16)) }

    static var displayCode: String {
        let c = Array(code.uppercased())
        return stride(from: 0, to: c.count, by: 4).map { String(c[$0..<min($0 + 4, c.count)]) }.joined(separator: "-")
    }

    static let botName = "FinanceIsland_agent"
    static var activateURL: URL { URL(string: "https://t.me/\(botName)?start=dev_\(code)")! }
}
