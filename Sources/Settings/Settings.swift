import Combine
import SwiftUI

enum AppInfo {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let channel = Bundle.main.object(forInfoDictionaryKey: "FIReleaseChannel") as? String ?? "beta"
        return channel.isEmpty ? v : v + " " + channel
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var walletAddress: String? {
        didSet { defaults.set(walletAddress, forKey: "walletAddress") }
    }
    @Published var onboarded: Bool {
        didSet { defaults.set(onboarded, forKey: "onboarded") }
    }
    @Published var notchHintDone: Bool {
        didSet { defaults.set(notchHintDone, forKey: "notchHintDone") }
    }
    @Published var hintScreens: [String] {
        didSet { defaults.set(hintScreens, forKey: "hintScreens") }
    }

    @Published var assetIDs: [String] {
        didSet { defaults.set(assetIDs, forKey: "assetIDs") }
    }
    @Published var baseCurrency: String {
        didSet { defaults.set(baseCurrency, forKey: "baseCurrency") }
    }

    @Published var chartStyle: ChartStyle {
        didSet { defaults.set(chartStyle.rawValue, forKey: "chartStyle") }
    }
    @Published var showGrid: Bool {
        didSet { defaults.set(showGrid, forKey: "showGrid") }
    }
    @Published var showPoints: Bool {
        didSet { defaults.set(showPoints, forKey: "showPoints") }
    }
    @Published var sparkRange: SparkRange {
        didSet { defaults.set(sparkRange.rawValue, forKey: "sparkRange") }
    }
    @Published var defaultTimeframe: Timeframe {
        didSet { defaults.set(defaultTimeframe.rawValue, forKey: "defaultTimeframe") }
    }
    @Published var liquidGlass: Bool {
        didSet { defaults.set(liquidGlass, forKey: "liquidGlass") }
    }
    @Published var glassTransparency: Double {
        didSet { defaults.set(glassTransparency, forKey: "glassTransparency") }
    }
    @Published var riseIsRed: Bool {
        didSet { defaults.set(riseIsRed, forKey: "riseIsRed") }
    }

    @Published var pillAssetID: String? {
        didSet { defaults.set(pillAssetID, forKey: "pillAssetID") }
    }
    @Published var refreshMinutes: Int {
        didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") }
    }

    @Published var themeID: String {
        didSet { defaults.set(themeID, forKey: "themeID") }
    }
    @Published var trendID: String {
        didSet { defaults.set(trendID, forKey: "trendID") }
    }
    @Published var accent: Accent {
        didSet { defaults.set(accent.rawValue, forKey: "accent") }
    }
    @Published var corners: Corners {
        didSet { defaults.set(corners.rawValue, forKey: "corners") }
    }

    @Published var motionStyle: MotionStyle {
        didSet { defaults.set(motionStyle.rawValue, forKey: "motionStyle") }
    }
    @Published var motionSpeed: MotionSpeed {
        didSet { defaults.set(motionSpeed.rawValue, forKey: "motionSpeed") }
    }
    @Published var animateCharts: Bool {
        didSet { defaults.set(animateCharts, forKey: "animateCharts") }
    }
    @Published var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: "expandOnHover") }
    }
    @Published var openDelayMs: Double {
        didSet { defaults.set(openDelayMs, forKey: "openDelayMs") }
    }
    @Published var openByClick: Bool {
        didSet { defaults.set(openByClick, forKey: "openByClick") }
    }
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published private(set) var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    private var accessibilityObserver: NSObjectProtocol?
    @Published var islandScreen: String {
        didSet { defaults.set(islandScreen, forKey: "islandScreen") }
    }
    @Published var menuBarMode: Bool {
        didSet { defaults.set(menuBarMode, forKey: "menuBarMode") }
    }

    @Published var assistantItems: [String] {
        didSet { defaults.set(assistantItems, forKey: "assistantItems") }
    }
    @Published var aiProvider: AIProvider {
        didSet { defaults.set(aiProvider.rawValue, forKey: "aiProvider") }
    }
    @Published var aiModels: [String: String] {
        didSet { defaults.set(aiModels, forKey: "aiModels") }
    }
    @Published var aiAutoInsight: Bool {
        didSet { defaults.set(aiAutoInsight, forKey: "aiAutoInsight") }
    }
    @Published var aiConsent: Bool {
        didSet { defaults.set(aiConsent, forKey: "aiConsent") }
    }
    @Published var floatingItem: String? {
        didSet { defaults.set(floatingItem, forKey: "floatingItem") }
    }
    @Published var lastTab: IslandTab {
        didSet { defaults.set(lastTab.rawValue, forKey: "lastTab") }
    }
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            L10n.set(language)
        }
    }
    @Published var energyMode: EnergyMode {
        didSet { defaults.set(energyMode.rawValue, forKey: "energyMode") }
    }
    @Published var energyOnBattery: Bool {
        didSet { defaults.set(energyOnBattery, forKey: "energyOnBattery") }
    }
    @Published var energyFollowSystem: Bool {
        didSet { defaults.set(energyFollowSystem, forKey: "energyFollowSystem") }
    }
    @Published var engineAutoRun: Bool {
        didSet { defaults.set(engineAutoRun, forKey: "engineAutoRun") }
    }

    @Published var fiatSource: DataSource? {
        didSet { defaults.set(fiatSource?.rawValue, forKey: SourcePrefs.key(.fiat)) }
    }
    @Published var cryptoSource: DataSource? {
        didSet { defaults.set(cryptoSource?.rawValue, forKey: SourcePrefs.key(.crypto)) }
    }
    @Published var stockSource: DataSource? {
        didSet { defaults.set(stockSource?.rawValue, forKey: SourcePrefs.key(.stock)) }
    }

    private var powerSub: AnyCancellable?


    @Published var profileMode: ProfileMode {
        didSet { defaults.set(profileMode.rawValue, forKey: "profileMode") }
    }
    @Published var reportQuota: ReportQuota {
        didSet {
            defaults.set(reportQuota.rawValue, forKey: "reportQuotaMB")
        }
    }
    @Published var retention: RetentionPolicy {
        didSet {
            defaults.set(retention.rawValue, forKey: "retention")
        }
    }
    @Published var tourCompleted: Bool {
        didSet { defaults.set(tourCompleted, forKey: "tourCompleted") }
    }

    @Published var acceptedTermsVersion: String? {
        didSet { defaults.set(acceptedTermsVersion, forKey: "acceptedTermsVersion") }
    }
    @Published var acceptedAt: Date? {
        didSet { defaults.set(acceptedAt, forKey: "acceptedAt") }
    }

    init() {
        let d = UserDefaults.standard
        walletAddress = d.string(forKey: "walletAddress")
        onboarded = d.bool(forKey: "onboarded")
        notchHintDone = d.bool(forKey: "notchHintDone")
        hintScreens = d.stringArray(forKey: "hintScreens") ?? []
        openDelayMs = d.object(forKey: "openDelayMs") as? Double ?? 150
        openByClick = d.bool(forKey: "openByClick")
        let savedBase = d.string(forKey: "baseCurrency").flatMap { Catalog.bases.contains($0) ? $0 : nil } ?? "USD"
        let fiatCodes = Set(Catalog.fiat.map(\.code))
        let savedAssets = (d.stringArray(forKey: "assetIDs") ?? []).filter { id in
            guard id.hasPrefix("fx:") else { return true }
            let code = String(id.dropFirst(3))
            return fiatCodes.contains(code) && code != savedBase
        }
        assetIDs = savedAssets.isEmpty ? ["fx:EUR", "fx:GBP", "fx:JPY"] : savedAssets
        baseCurrency = savedBase
        chartStyle = ChartStyle(rawValue: d.string(forKey: "chartStyle") ?? "") ?? .line
        showGrid = d.object(forKey: "showGrid") as? Bool ?? true
        showPoints = d.object(forKey: "showPoints") as? Bool ?? true
        sparkRange = SparkRange(rawValue: d.string(forKey: "sparkRange") ?? "") ?? .m1
        defaultTimeframe = Timeframe(rawValue: d.string(forKey: "defaultTimeframe") ?? "") ?? .h24
        liquidGlass = d.bool(forKey: "liquidGlass")
        glassTransparency = d.object(forKey: "glassTransparency") as? Double ?? 0.25
        riseIsRed = d.object(forKey: "riseIsRed") as? Bool ?? false
        pillAssetID = d.string(forKey: "pillAssetID")
        refreshMinutes = d.object(forKey: "refreshMinutes") as? Int ?? 30
        themeID = d.string(forKey: "themeID") ?? Theme.midnight.id
        trendID = d.string(forKey: "trendID") ?? TrendPalette.classic.id
        accent = Accent(rawValue: d.string(forKey: "accent") ?? "") ?? .green
        corners = Corners(rawValue: d.string(forKey: "corners") ?? "") ?? .round
        motionStyle = MotionStyle(rawValue: d.string(forKey: "motionStyle") ?? "") ?? .smooth
        motionSpeed = MotionSpeed(rawValue: d.string(forKey: "motionSpeed") ?? "") ?? .normal
        animateCharts = d.object(forKey: "animateCharts") as? Bool ?? true
        expandOnHover = d.bool(forKey: "expandOnHover")
        islandScreen = d.string(forKey: "islandScreen") ?? "auto"
        menuBarMode = d.bool(forKey: "menuBarMode")
        let old = UserDefaults(suiteName: "local.tradingwidget")
        var pairs = d.stringArray(forKey: "tradingPairs") ?? ["BTCUSDT", "ETHUSDT"]
        if let oldSymbol = old?.string(forKey: "symbol"), !pairs.contains(oldSymbol) { pairs.insert(oldSymbol, at: 0) }
        assistantItems = d.stringArray(forKey: "assistantItems")
            ?? pairs.map { "binance:" + $0 } + ["yahoo:AAPL", "yahoo:SPY"]
        aiProvider = AIProvider(rawValue: d.string(forKey: "aiProvider") ?? "") ?? .off
        aiModels = d.dictionary(forKey: "aiModels") as? [String: String] ?? [:]
        aiAutoInsight = d.bool(forKey: "aiAutoInsight")
        aiConsent = d.bool(forKey: "aiConsent")
        floatingItem = d.string(forKey: "floatingItem") ?? d.string(forKey: "floatingPair").map { "binance:" + $0 }
        lastTab = IslandTab.visible.first { $0.rawValue == d.string(forKey: "lastTab") } ?? .home
        engineAutoRun = d.object(forKey: "engineAutoRun") as? Bool ?? true
        energyMode = EnergyMode(rawValue: d.string(forKey: "energyMode") ?? "") ?? .normal
        energyOnBattery = d.bool(forKey: "energyOnBattery")
        energyFollowSystem = d.object(forKey: "energyFollowSystem") as? Bool ?? true
        profileMode = ProfileMode(rawValue: d.string(forKey: "profileMode") ?? "") ?? .novice
        reportQuota = ReportQuota(rawValue: d.object(forKey: "reportQuotaMB") as? Int ?? -1) ?? .mb500
        retention = RetentionPolicy(rawValue: d.string(forKey: "retention") ?? "") ?? .fifo
        tourCompleted = d.bool(forKey: "tourCompleted")
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .system
        L10n.set(language)
        fiatSource = SourcePrefs.preferred(.fiat)
        cryptoSource = SourcePrefs.preferred(.crypto)
        stockSource = SourcePrefs.preferred(.stock)
        let accepted = d.string(forKey: "acceptedTermsVersion")
        acceptedTermsVersion = accepted == "1.2" ? Legal.termsVersion : accepted
        acceptedAt = d.object(forKey: "acceptedAt") as? Date
        powerSub = PowerState.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.objectWillChange.send() } }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self?.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            }
        }
    }

    var hasAcceptedTerms: Bool { acceptedTermsVersion == Legal.termsVersion }

    func acceptTerms() {
        acceptedTermsVersion = Legal.termsVersion
        acceptedAt = Date()
    }

    func eraseAll() {
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        defaults.removePersistentDomain(forName: AppIdentity.legacyBundleID)
        let fresh = AppSettings()
        walletAddress = nil
        onboarded = false
        acceptedTermsVersion = nil
        acceptedAt = nil
        assetIDs = fresh.assetIDs
        baseCurrency = fresh.baseCurrency
        fiatSource = nil
        cryptoSource = nil
        stockSource = nil
        resetLook()
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        defaults.removePersistentDomain(forName: AppIdentity.legacyBundleID)
    }

    func resetLook() {
        chartStyle = .line
        showGrid = true
        showPoints = true
        sparkRange = .m1
        defaultTimeframe = .h24
        riseIsRed = false
        liquidGlass = false
        glassTransparency = 0.25
        pillAssetID = nil
        refreshMinutes = 30
        themeID = Theme.midnight.id
        trendID = TrendPalette.classic.id
        accent = .green
        corners = .round
        motionStyle = .smooth
        motionSpeed = .normal
        animateCharts = true
        expandOnHover = false
        notchHintDone = false
        hintScreens = []
        openDelayMs = 150
        openByClick = false
    }


    var watchItems: [WatchItem] { assistantItems.compactMap(WatchItem.init(id:)) }


    var aiModel: String { aiModels[aiProvider.rawValue] ?? aiProvider.defaultModel }

    @discardableResult
    func addItem(_ raw: String, source: MarketSource) -> WatchItem? {
        var s = raw.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "^" || $0 == "-" || $0 == "=" }
        guard !s.isEmpty else { return nil }
        if source == .binance {
            s = s.filter { $0.isLetter || $0.isNumber }
            guard s.count >= 2 else { return nil }
            if s.count <= 5 { s += "USDT" }
        }
        let item = WatchItem(source: source, symbol: s)
        if !assistantItems.contains(item.id) { assistantItems.append(item.id) }
        return item
    }

    func removeItem(_ id: String) {
        assistantItems.removeAll { $0 == id }
    }

    func moveItem(_ id: String, by offset: Int) {
        guard let i = assistantItems.firstIndex(of: id), assistantItems.indices.contains(i + offset) else { return }
        assistantItems.swapAt(i, i + offset)
    }

    func moveItem(_ id: String, to index: Int) {
        guard let i = assistantItems.firstIndex(of: id) else { return }
        let target = min(max(index, 0), assistantItems.count - 1)
        guard target != i else { return }
        var list = assistantItems
        list.remove(at: i)
        list.insert(id, at: target)
        assistantItems = list
    }

    var look: Look {
        let base = Theme.byID(themeID)
        let glass = liquidGlass && !reduceTransparency
        return Look(theme: glass ? Theme.glass(over: base, transparency: glassTransparency) : base, glass: glass,
                    trend: TrendPalette.byID(trendID), accent: accent.color, corners: corners)
    }

    var motion: Motion {
        effectiveEnergy.animations && !reduceMotion ? Motion(style: motionStyle, speed: motionSpeed, animateCharts: animateCharts)
                                   : Motion(style: .off, speed: motionSpeed, animateCharts: false)
    }

    var assets: [Asset] {
        assetIDs.compactMap { Asset.make(id: $0, base: baseCurrency) }
            .filter { !($0.isFiat && $0.code == baseCurrency) }
    }

    var pillAsset: Asset? {
        if let id = pillAssetID, assetIDs.contains(id), let a = Asset.make(id: id, base: baseCurrency) { return a }
        return assets.first
    }

    var eth: Asset { Asset.make(kind: .crypto, code: "ETH", base: baseCurrency) }

    func asset(id: String) -> Asset {
        Asset.make(id: id, base: baseCurrency) ?? eth
    }

    func color(_ a: Asset, up: Bool) -> Color {
        let red = a.isFiat && riseIsRed ? up : !up
        let t = TrendPalette.byID(trendID)
        return red ? t.red : t.green
    }

    func contains(_ id: String) -> Bool { assetIDs.contains(id) }

    func toggle(_ id: String) {
        if let i = assetIDs.firstIndex(of: id) { assetIDs.remove(at: i) } else { assetIDs.append(id) }
    }

    func move(_ id: String, by offset: Int) {
        guard let i = assetIDs.firstIndex(of: id) else { return }
        let j = i + offset
        guard assetIDs.indices.contains(j) else { return }
        assetIDs.swapAt(i, j)
    }

    func move(_ id: String, to index: Int) {
        guard let i = assetIDs.firstIndex(of: id) else { return }
        let target = min(max(index, 0), assetIDs.count - 1)
        guard target != i else { return }
        var list = assetIDs
        list.remove(at: i)
        list.insert(id, at: target)
        assetIDs = list
    }

    func moveToTop(_ id: String) { move(id, to: 0) }
    func moveToBottom(_ id: String) { move(id, to: assetIDs.count - 1) }

    @discardableResult
    func addCustom(_ raw: String, kind: AssetKind) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (2...10).contains(code.count), code.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        if kind == .fiat && code.count != 3 { return nil }
        let id = kind.rawValue + ":" + code
        if !assetIDs.contains(id) { assetIDs.append(id) }
        return id
    }

    static func isValidAddress(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count == 42, t.hasPrefix("0x") else { return false }
        return t.dropFirst(2).allSatisfy { $0.isHexDigit }
    }
}
