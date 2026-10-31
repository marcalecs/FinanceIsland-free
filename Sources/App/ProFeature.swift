import SwiftUI

enum ProFeature: String, CaseIterable, Identifiable {
    case tiltGuard, traderMirror, unlimitedPaper, extendedStats, unlimitedAlerts
    var id: String { rawValue }

    static let freePriceAlerts = 3
    static let freePaperTradesPerMonth = 20

    var title: String {
        switch self {
        case .tiltGuard: return "Tilt Guard"
        case .traderMirror: return "Trader mirror"
        case .unlimitedPaper: return "Unlimited paper trading"
        case .extendedStats: return "Extended statistics"
        case .unlimitedAlerts: return "Unlimited price alerts"
        }
    }

    var detail: String {
        switch self {
        case .tiltGuard: return "Your loss and trade limits, and a reminder if you open an exchange app during a pause"
        case .traderMirror: return "Your journal by hour, tag and mistake, and what trades with mistake tags came to"
        case .unlimitedPaper: return "Free: 20 paper trades a month"
        case .extendedStats: return "Profit factor, expectancy and drawdown in the journal"
        case .unlimitedAlerts: return "Free: 3 price alerts"
        }
    }

    @MainActor
    var isUnlocked: Bool { LicenseStore.shared.isActive }

    @MainActor
    static func limit(_ free: Int) -> Int? { LicenseStore.shared.isActive ? nil : free }
}

struct ProPreview: View {
    let feature: ProFeature
    @Environment(\.look) private var look

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(feature.title) + " · Pro").font(.system(size: 12.5, weight: .semibold))
                Text(tr(feature.detail)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button(tr("Open in the bot")) { NSWorkspace.shared.open(DeviceIdentity.activateURL) }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(look.theme.chip))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: look.corners.card, style: .continuous).fill(look.theme.card.opacity(0.6)))
    }
}
