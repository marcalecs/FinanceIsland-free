import AppKit
import Combine
import Foundation

@MainActor
final class RateStore: ObservableObject {
    @Published var quotes: [String: Quote] = [:]
    @Published var sources: [String: DataSource] = [:]
    @Published var ethBalance: Double?
    @Published var failed = false
    @Published var updated: Date?
    @Published var fetchedAt: [String: Date] = [:]

    let settings: AppSettings
    private var timer: Timer?
    private var loading = false
    private var pending = false
    private var subs: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        self.settings = settings
    }

    nonisolated static func key(_ a: Asset) -> String { a.id + "/" + a.base }
    func quote(_ a: Asset) -> Quote? { quotes[Self.key(a)] }
    func source(_ a: Asset) -> DataSource? { sources[Self.key(a)] }

    func start() {
        refresh()
        schedule()

        Publishers.MergeMany(
            settings.$assetIDs.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$baseCurrency.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$sparkRange.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$fiatSource.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$cryptoSource.dropFirst().map { _ in () }.eraseToAnyPublisher())
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subs)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subs)

        Publishers.MergeMany(
            settings.$refreshMinutes.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$energyMode.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$energyOnBattery.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$energyFollowSystem.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            PowerState.shared.objectWillChange.map { _ in () }.eraseToAnyPublisher())
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] in self?.schedule() }
            .store(in: &subs)
    }

    var interval: TimeInterval {
        TimeInterval(max(settings.refreshMinutes, 1) * 60) * settings.effectiveEnergy.slowdown
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = interval * 0.1
    }

    func refreshIfStale() {
        guard let u = updated else { refresh(); return }
        if Date().timeIntervalSince(u) > TimeInterval(max(settings.refreshMinutes, 1) * 60) { refresh() }
    }

    private nonisolated static func fetch(_ a: Asset, range: SparkRange) async -> (Quote, DataSource)? {
        for attempt in 0..<2 {
            do { return try await RatesFeed.quote(a, range: range) }
            catch {
                AppLog.write("fetch \(a.id) failed (try \(attempt + 1)):", error.localizedDescription)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
        return nil
    }

    func reset() {
        quotes = [:]
        sources = [:]
        ethBalance = nil
        updated = nil
        failed = false
        refresh()
    }

    func walletChanged() {
        ethBalance = nil
        refresh()
    }

    func refresh() {
        if loading { pending = true; return }
        loading = true
        Task { [self] in
            let address = settings.walletAddress
            let range = settings.sparkRange
            var assets = settings.assets
            if address != nil && !assets.contains(where: { Self.key($0) == Self.key(settings.eth) }) {
                assets.append(settings.eth)
            }

            var results: [(String, (Quote, DataSource)?)] = []
            for start in stride(from: 0, to: assets.count, by: 3) {
                let batch = assets[start..<min(start + 3, assets.count)]
                let part = await withTaskGroup(of: (String, (Quote, DataSource)?).self) { group in
                    for a in batch {
                        group.addTask { (Self.key(a), await Self.fetch(a, range: range)) }
                    }
                    var out: [(String, (Quote, DataSource)?)] = []
                    for await r in group { out.append(r) }
                    return out
                }
                results += part
            }
            var anyOK = false
            for (key, r) in results {
                if let (q, src) = r { quotes[key] = q; sources[key] = src; fetchedAt[key] = Date(); anyOK = true }
            }

            if let address {
                do { ethBalance = try await DataService.ethBalance(address) }
                catch { AppLog.write("balance failed:", error) }
            }

            failed = !anyOK && quotes.isEmpty
            if anyOK { updated = Date() }
            loading = false
            if pending { pending = false; refresh() }
        }
    }
}
