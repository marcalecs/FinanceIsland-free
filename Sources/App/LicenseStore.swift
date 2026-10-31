import Foundation

enum LicensePublicKey {
    static let placeholder = "REPLACE_WITH_PRODUCTION_PUBLIC_KEY"
    static let production = placeholder
}

@MainActor
final class LicenseStore: ObservableObject {
    static let shared = LicenseStore()

    @Published private(set) var license: License?
    @Published private(set) var problem: LicenseError?
    private var timer: Timer?

    var isActive: Bool { license != nil && problem == nil }
    var inGrace: Bool { license.map { Date() > $0.exp } ?? false }

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { LicenseStore.shared.refresh() }
        }
    }

    private var latestSeen: Date {
        let d = UserDefaults.standard
        let now = Date(), seen = Date(timeIntervalSince1970: d.double(forKey: "licenseClock"))
        if now > seen { d.set(now.timeIntervalSince1970, forKey: "licenseClock"); return now }
        return seen
    }

    func refresh() {
        guard let text = AccountKeychain.get("license") else { license = nil; problem = nil; return }
        do {
            license = try LicenseVerifier.check(text, publicKey: LicensePublicKey.production, device: DeviceIdentity.code,
                                                now: Date(), latestSeen: latestSeen)
            problem = nil
        } catch let e as LicenseError {
            license = try? LicenseVerifier.parse(text, publicKey: LicensePublicKey.production)
            problem = e
        } catch {
            problem = .malformed
        }
    }

    func install(_ text: String) throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try LicenseVerifier.check(clean, publicKey: LicensePublicKey.production, device: DeviceIdentity.code,
                                      now: Date(), latestSeen: latestSeen)
        AccountKeychain.set("license", clean)
        refresh()
    }

    func remove() {
        AccountKeychain.set("license", nil)
        refresh()
    }
}
