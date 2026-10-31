import Foundation
import UserNotifications

@MainActor
final class AlertStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AlertStore()
    static let checkEvery: TimeInterval = 60

    @Published private(set) var alerts: [PriceAlert] = []
    @Published private(set) var lastCheck: Date?
    private var lastSaved: Data?
    private var task: Task<Void, Never>?

    var activeCount: Int { alerts.filter(\.active).count }
    var canAdd: Bool { ProFeature.limit(ProFeature.freePriceAlerts).map { activeCount < $0 } ?? true }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinanceIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("alerts.json")
    }

    private override init() {
        super.init()
        if let data = try? Data(contentsOf: Self.fileURL), let list = try? DataVault.decoder.decode([PriceAlert].self, from: data) {
            alerts = list
            lastSaved = data
            DataVault.backup("alerts", data)
        }
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(nanoseconds: UInt64(Self.checkEvery * 1_000_000_000))
            }
        }
    }

    @discardableResult
    func add(_ a: PriceAlert) -> Bool {
        guard canAdd else { return false }
        alerts.append(a)
        save()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Task { await check() }
        return true
    }

    func remove(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        save()
    }

    func rearm(_ id: UUID) {
        guard let i = alerts.firstIndex(where: { $0.id == id }), !alerts[i].active, canAdd else { return }
        alerts[i].active = true
        alerts[i].firedAt = nil
        alerts[i].firedPrice = nil
        alerts[i].createdAt = Date()
        save()
    }

    func alerts(for subject: String) -> [PriceAlert] { alerts.filter { $0.subject == subject } }

    func restore(_ list: [PriceAlert]) {
        alerts = list
        save()
    }

    func eraseAll() {
        alerts = []
        lastSaved = nil
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func save() {
        guard let data = try? DataVault.encoder.encode(alerts), data != lastSaved else { return }
        if let previous = lastSaved { DataVault.backup("alerts", previous) }
        lastSaved = data
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    func check() async {
        let due = alerts.filter(\.active)
        guard !due.isEmpty else { return }
        for subjectID in Set(due.map(\.subject)) {
            guard let s = HubSubject(id: subjectID) else { continue }
            let longest = due.filter { $0.subject == subjectID && $0.isChange }.map(\.hours).max() ?? 0
            guard let r = try? await ChartFeed.candles(s, tf: longest > 40 ? .h1 : .m5), let last = r.candles.last else { continue }
            for a in alerts where a.active && a.subject == subjectID {
                let since = Date().addingTimeInterval(-a.hours * 3600)
                let reference = r.candles.first(where: { $0.openTime >= since })?.open
                if a.isMet(price: last.close, reference: reference) { fire(a.id, price: last.close) }
            }
        }
        lastCheck = Date()
    }

    private func fire(_ id: UUID, price: Double) {
        guard let i = alerts.firstIndex(where: { $0.id == id }), alerts[i].active else { return }
        alerts[i].active = false
        alerts[i].firedAt = Date()
        alerts[i].firedPrice = price
        save()
        let a = alerts[i]
        let s = HubSubject(id: a.subject)
        let fmt = { (v: Double) in s?.format(v) ?? Fmt.number(v, min: 2, max: 6) }
        let title = Self.title(a, format: fmt)
        notify(id: a.id.uuidString, title: title, body: tr("Now \(fmt(price)) · the alert is off until you turn it on again"), thread: a.subject)
    }

    func notify(id: String, title: String, body: String, thread: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = thread
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
        TradeDesk.shared.post(title)
    }

    static func title(_ a: PriceAlert, format: (Double) -> String) -> String {
        let hours = Fmt.number(a.hours, min: 0, max: 1)
        switch a.kind {
        case .above: return tr("\(a.name) is above \(format(a.value))")
        case .below: return tr("\(a.name) is below \(format(a.value))")
        case .risesBy: return tr("\(a.name) rose \(Fmt.number(a.value, min: 0, max: 2))% in \(hours) h")
        case .fallsBy: return tr("\(a.name) fell \(Fmt.number(a.value, min: 0, max: 2))% in \(hours) h")
        }
    }

    static func describe(_ a: PriceAlert, format: (Double) -> String) -> String {
        let hours = Fmt.number(a.hours, min: 0, max: 1)
        switch a.kind {
        case .above: return tr("Above \(format(a.value))")
        case .below: return tr("Below \(format(a.value))")
        case .risesBy: return tr("Rises \(Fmt.number(a.value, min: 0, max: 2))% within \(hours) h")
        case .fallsBy: return tr("Falls \(Fmt.number(a.value, min: 0, max: 2))% within \(hours) h")
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
