import AppKit
import Collaboration
import SwiftUI

enum ProfileStatus: String, CaseIterable, Identifiable {
    case owner = "Owner", trader = "Trader", holder = "Holder", investor = "Investor", learner = "Learner"
    var id: String { rawValue }

    static var choices: [ProfileStatus] {
        allCases.filter { $0 != .owner }
    }

    var colors: [Color] {
        switch self {
        case .owner: return [Color(red: 1, green: 0.78, blue: 0.25), Color(red: 1, green: 0.36, blue: 0.47), Color(red: 0.55, green: 0.36, blue: 1)]
        case .trader: return [Color(red: 0.2, green: 0.85, blue: 0.6), Color(red: 0.2, green: 0.55, blue: 1)]
        case .holder: return [Color(red: 0.35, green: 0.65, blue: 1), Color(red: 0.6, green: 0.4, blue: 1)]
        case .investor: return [Color(red: 0.25, green: 0.8, blue: 0.85), Color(red: 0.2, green: 0.45, blue: 0.95)]
        case .learner: return [Color(red: 0.6, green: 0.85, blue: 0.35), Color(red: 0.25, green: 0.7, blue: 0.45)]
        }
    }

    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

enum ProBadge {
    static let gradient = LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.35), Color(red: 1, green: 0.55, blue: 0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published var nickname: String { didSet { UserDefaults.standard.set(nickname, forKey: "profileNickname") } }
    @Published var status: ProfileStatus { didSet { UserDefaults.standard.set(status.rawValue, forKey: "profileStatus") } }
    @Published var mood: String { didSet { UserDefaults.standard.set(mood, forKey: "profileMood") } }
    @Published var bio: String { didSet { UserDefaults.standard.set(bio, forKey: "profileBio") } }
    @Published private(set) var photo: NSImage?
    let since: Date

    private init() {
        let d = UserDefaults.standard
        let fallbackName = NSFullUserName().split(separator: " ").first.map(String.init) ?? "Trader", fallbackStatus = ProfileStatus.trader
        nickname = d.string(forKey: "profileNickname") ?? fallbackName
        let saved = ProfileStatus(rawValue: d.string(forKey: "profileStatus") ?? "") ?? fallbackStatus
        status = ProfileStatus.choices.contains(saved) ? saved : fallbackStatus
        mood = d.string(forKey: "profileMood") ?? "📈"
        bio = d.string(forKey: "profileBio") ?? ""
        if d.object(forKey: "profileSince") == nil { d.set(Date(), forKey: "profileSince") }
        since = d.object(forKey: "profileSince") as? Date ?? Date()
        photo = NSImage(contentsOf: Self.photoURL) ?? (ProcessInfo.processInfo.environment["FI_DEMO"] == nil || Self.ownerBuild ? Self.accountPicture() : nil)
    }

    var isPro: Bool { LicenseStore.shared.isActive }

    static let ownerBuild = false

    static var photoURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FinanceIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.png")
    }

    static func accountPicture() -> NSImage? {
        CBUserIdentity(posixUID: getuid(), authority: CBIdentityAuthority.default())?.image
    }

    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        let out = Self.square(image, side: 256)
        if let png = Self.png(out) { try? png.write(to: Self.photoURL, options: .atomic) }
        photo = out
    }

    func useAccountPicture() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        photo = Self.accountPicture()
    }

    static func square(_ image: NSImage, side: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        let s = image.size
        let k = max(side / max(s.width, 1), side / max(s.height, 1))
        let w = s.width * k, h = s.height * k
        image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        out.unlockFocus()
        return out
    }

    static func png(_ image: NSImage) -> Data? {
        image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    }
}

struct TraderStats {
    let trades: Int
    let winRate: Double?
    let totalR: Double
    let weekR: Double
    let holdings: Int
    let journalDays: Int
    let bestStreak: Int
    let withStop: Double?

    @MainActor
    static var current: TraderStats {
        let entries = JournalStore.shared.entries
        let closed = entries.filter { $0.kind == .trade && $0.status == .closed }.sorted { ($0.closedAt ?? $0.at) < ($1.closedAt ?? $1.at) }
        let outcomes = closed.compactMap(\.outcome)
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        var streak = 0, best = 0
        for o in outcomes { streak = o > 0 ? streak + 1 : 0; best = max(best, streak) }
        let trades = entries.filter { $0.kind == .trade }
        let days = Set(entries.map { Calendar.current.startOfDay(for: $0.at) }).count
        return TraderStats(trades: trades.count,
                           winRate: outcomes.isEmpty ? nil : Double(outcomes.filter { $0 > 0 }.count) / Double(outcomes.count),
                           totalR: closed.compactMap(\.rMultiple).reduce(0, +),
                           weekR: closed.filter { ($0.closedAt ?? $0.at) >= weekAgo }.compactMap(\.rMultiple).reduce(0, +),
                           holdings: LongTermStore.shared.manual.count,
                           journalDays: days, bestStreak: best,
                           withStop: trades.isEmpty ? nil : Double(trades.filter { $0.riskStop != nil }.count) / Double(trades.count))
    }
}

struct Achievement: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let earned: Bool

    static func all(_ s: TraderStats, pro: Bool) -> [Achievement] {
        [
            Achievement(id: "first", symbol: "flag.checkered", title: "First trade", detail: "Log your first trade", earned: s.trades >= 1),
            Achievement(id: "ten", symbol: "10.circle", title: "Ten trades", detail: "10 trades in the journal", earned: s.trades >= 10),
            Achievement(id: "fifty", symbol: "50.circle", title: "Fifty trades", detail: "50 trades in the journal", earned: s.trades >= 50),
            Achievement(id: "streak", symbol: "flame", title: "Hot streak", detail: "3 winning trades in a row", earned: s.bestStreak >= 3),
            Achievement(id: "stops", symbol: "shield.lefthalf.filled", title: "Risk first", detail: "Every trade has a stop (10+ trades)",
                        earned: s.trades >= 10 && (s.withStop ?? 0) >= 1),
            Achievement(id: "diary", symbol: "book.closed", title: "Journal habit", detail: "Entries on 7 different days", earned: s.journalDays >= 7),
            Achievement(id: "holder", symbol: "briefcase", title: "Holder", detail: "5 positions in the portfolio", earned: s.holdings >= 5),
            Achievement(id: "pro", symbol: "crown", title: "Pro member", detail: "FinanceIsland Pro is active", earned: pro),
        ]
    }
}

@MainActor
struct ProfileAvatar: View {
    @ObservedObject private var profile = ProfileStore.shared
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(profile.isPro ? AnyShapeStyle(ProBadge.gradient) : AnyShapeStyle(profile.status.gradient))
            Group {
                if let p = profile.photo {
                    Image(nsImage: p).resizable().scaledToFill()
                } else {
                    Text(String(profile.nickname.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0.15))
                }
            }
            .frame(width: size - max(3, size * 0.06), height: size - max(3, size * 0.06))
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if profile.isPro && size >= 40 {
                Image(systemName: "crown.fill").font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.black)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .background(Circle().fill(ProBadge.gradient))
                    .offset(x: size * 0.04, y: -size * 0.04)
            }
        }
    }
}

struct StatusBadge: View {
    let title: String
    let gradient: LinearGradient
    var symbol: String? = nil
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: size * 0.9, weight: .heavy)) }
            Text(tr(title).uppercased()).font(.system(size: size, weight: .heavy)).tracking(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, size * 0.7)
        .frame(height: size * 1.8)
        .background(Capsule().fill(gradient))
    }
}

@MainActor
struct ProfileButton: View {
    @ObservedObject var state: IslandState
    @ObservedObject private var profile = ProfileStore.shared

    var body: some View {
        Button { state.openSettings(.profile) } label: {
            ProfileAvatar(size: 30)
                .overlay(alignment: .bottomTrailing) {
                    Text(profile.mood).font(.system(size: 9)).frame(width: 13, height: 13)
                        .background(Circle().fill(Color.black))
                        .offset(x: 2, y: 2)
                }
        }
        .buttonStyle(PressStyle())
        .hoverLift()
        .help(profile.nickname + " · " + tr(profile.status.rawValue) + (profile.isPro ? " · PRO" : ""))
    }
}

@MainActor
struct ProfileCard: View {
    @ObservedObject private var profile = ProfileStore.shared
    let stats: TraderStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProfileAvatar(size: 64)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(profile.nickname.isEmpty ? "—" : profile.nickname).font(.system(size: 20, weight: .bold))
                        Text(profile.mood).font(.system(size: 16))
                    }
                    HStack(spacing: 6) {
                        StatusBadge(title: profile.status.rawValue, gradient: profile.status.gradient)
                        if profile.isPro { StatusBadge(title: "Pro", gradient: ProBadge.gradient, symbol: "crown.fill") }
                    }
                    if !profile.bio.isEmpty {
                        Text(profile.bio).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                tile(tr("Trades"), "\(stats.trades)")
                tile(tr("Winning"), stats.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                tile(tr("Total in R"), String(format: "%+.1fR", stats.totalR))
                tile(tr("This week"), String(format: "%+.1fR", stats.weekR))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(profile.isPro ? AnyShapeStyle(ProBadge.gradient) : AnyShapeStyle(profile.status.gradient), lineWidth: 1.2))
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 15, weight: .bold).monospacedDigit())
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
    }
}

@MainActor
struct ProfileTab: View {
    @ObservedObject private var profile = ProfileStore.shared
    @Environment(\.look) private var look
    @State private var shared: String?

    private static let moods = ["📈", "📉", "🚀", "🧘", "🔥", "🎯", "🐂", "🐻", "💎", "☕️"]

    var body: some View {
        let stats = TraderStats.current
        VStack(alignment: .leading, spacing: 0) {
            ProfileCard(stats: stats).environment(\.colorScheme, .dark)
            HStack(spacing: 8) {
                PillLink(title: "Choose photo", symbol: "photo") { profile.choosePhoto() }
                PillLink(title: "Use the Mac account picture", symbol: "person.crop.circle") { profile.useAccountPicture() }
                Spacer()
                PillLink(title: "Share card", symbol: "square.and.arrow.up") { share(stats) }
            }
            .padding(.vertical, 12)
            if let shared {
                Text(shared).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(look.accent).padding(.bottom, 8)
            }

            SettingsSection(title: "Profile") {
                Row(title: "Nickname") {
                    field(TextField(tr("Nickname"), text: $profile.nickname))
                }
                Row(title: "Status line", subtitle: "A short line under your name, like in a social profile") {
                    field(TextField(tr("Swing trading BTC this week"), text: $profile.bio))
                }
                Row(title: "Mood") {
                    HStack(spacing: 2) {
                        ForEach(Self.moods, id: \.self) { m in
                            Button { profile.mood = m } label: {
                                Text(m).font(.system(size: 14)).frame(width: 26, height: 26)
                                    .background(Circle().fill(profile.mood == m ? look.theme.selected : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Row(title: "Status", divider: false) {
                    PillPicker(options: ProfileStatus.choices, selection: $profile.status, label: \.rawValue, minWidth: 30)
                }
            }

            SettingsSection(title: "Achievements") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Achievement.all(stats, pro: profile.isPro)) { a in
                        HStack(spacing: 10) {
                            Image(systemName: a.symbol).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(a.earned ? AnyShapeStyle(profile.status.gradient) : AnyShapeStyle(Color.white.opacity(0.3)))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.white.opacity(a.earned ? 0.1 : 0.04)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tr(a.title)).font(.system(size: 12.5, weight: .semibold))
                                Text(tr(a.detail)).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if a.earned { Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(look.accent) }
                        }
                        .opacity(a.earned ? 1 : 0.6)
                    }
                }
                .padding(.vertical, 6)
            }
            if !profile.isPro {
                Text(tr("Pro members get a gold crown on their avatar and profile card."))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).padding(.top, 6)
            }
        }
    }

    private func field(_ f: some View) -> some View {
        f.textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 220)
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(look.theme.chip))
    }

    private func share(_ stats: TraderStats) {
        let r = ImageRenderer(content: ProfileCard(stats: stats).frame(width: 460).padding(20).background(Color.black)
            .environment(\.colorScheme, .dark).foregroundStyle(.white))
        r.scale = 2
        guard let image = r.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        shared = tr("Card copied: paste it into any chat")
    }
}
