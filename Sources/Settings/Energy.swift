import Combine
import Foundation
import IOKit.ps

enum EnergyMode: String, CaseIterable, Identifiable {
    case normal, balanced, low
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .balanced: return "Balanced"
        case .low: return "Low power"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "bolt.fill"
        case .balanced: return "leaf"
        case .low: return "battery.25percent"
        }
    }

    var summary: String {
        switch self {
        case .normal: return "Live prices, every animation, daily AI engine"
        case .balanced: return "Slower refresh, AI engine only when plugged in"
        case .low: return "10 % or less of the activity: updates mostly when you look"
        }
    }

    var slowdown: Double {
        switch self {
        case .normal: return 1
        case .balanced: return 3
        case .low: return 10
        }
    }

    var animations: Bool { self != .low }

    var rank: Int { [.normal, .balanced, .low].firstIndex(of: self)! }
}

@MainActor
final class PowerState: ObservableObject {
    static let shared = PowerState()

    @Published private(set) var onBattery = false
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var systemLowPower = false
    private var timer: Timer?

    private init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer?.tolerance = 20
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func update() {
        systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { onBattery = false; return }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        onBattery = type == kIOPMBatteryPowerKey
        let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        batteryPercent = list.compactMap { src -> Int? in
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
            return cur * 100 / max
        }.first
    }
}

extension AppSettings {
    var effectiveEnergy: EnergyMode {
        let p = PowerState.shared
        var m = energyMode
        if energyOnBattery && p.onBattery && m.rank < EnergyMode.low.rank { m = .low }
        if energyFollowSystem && p.systemLowPower { m = .low }
        return m
    }

    var energyReason: String? {
        let p = PowerState.shared
        if energyFollowSystem && p.systemLowPower && energyMode != .low { return "macOS Low Power Mode is on" }
        if energyOnBattery && p.onBattery && energyMode != .low { return "running on battery" }
        return nil
    }

    func requestsPerHour(_ m: EnergyMode) -> Double {
        let rates = Double(max(assets.count, 1)) * 60 / (Double(max(refreshMinutes, 1)) * m.slowdown)
        let engine = m == .low ? 0 : Double(watchItems.count + 10) / 24
        return rates + engine
    }
}
