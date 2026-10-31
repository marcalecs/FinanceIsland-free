import Foundation

enum AppIdentity {
    static let bundleID = "com.marcalecs.financeisland"
    static let legacyBundleID = "local.finance.island"

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? bundleID, isDirectory: true)
    }
}

enum Migration {
    static func run() {
        let d = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, id != AppIdentity.legacyBundleID else { return }
        let current = d.persistentDomain(forName: id) ?? [:]
        guard current.isEmpty, let old = d.persistentDomain(forName: AppIdentity.legacyBundleID), !old.isEmpty else { return }
        d.setPersistentDomain(old, forName: id)
        d.synchronize()
        AppLog.write("settings moved from \(AppIdentity.legacyBundleID) to \(id): \(old.count) keys")
    }
}
