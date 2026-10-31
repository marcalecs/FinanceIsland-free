import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct FriendCard: Codable, Identifiable, Equatable {
    var v = 1
    var id: String
    var nick: String
    var status: String
    var mood: String
    var bio: String
    var trades: Int
    var winRate: Double?
    var totalR: Double
    var weekR: Double
    var allocation: [String: Double]?
    var at: Date

    static let prefix = "FI-FRIEND."

    var code: String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        enc.outputFormatting = .sortedKeys
        let data = (try? enc.encode(self)) ?? Data()
        return Self.prefix + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func parse(_ text: String) -> FriendCard? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = raw.range(of: prefix) else { return nil }
        var b = String(raw[r.upperBound...].prefix { !$0.isWhitespace })
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        guard let card = try? dec.decode(FriendCard.self, from: data), card.v == 1, !card.id.isEmpty else { return nil }
        return card
    }
}

@MainActor
final class FriendsStore: ObservableObject {
    static let shared = FriendsStore()

    @Published private(set) var friends: [FriendCard] = []
    @Published var shareAllocation: Bool { didSet { UserDefaults.standard.set(shareAllocation, forKey: "friendsShareAllocation") } }
    let myID: String

    private init() {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "friendsMyID") { myID = id } else {
            myID = UUID().uuidString
            d.set(myID, forKey: "friendsMyID")
        }
        shareAllocation = d.bool(forKey: "friendsShareAllocation")
        if let data = d.data(forKey: "friendsList"), let list = try? JSONDecoder().decode([FriendCard].self, from: data) { friends = list }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(friends) { UserDefaults.standard.set(data, forKey: "friendsList") }
    }

    enum AddResult { case added(String), updated(String), invalid, yourself }

    func add(_ text: String) -> AddResult {
        guard let card = FriendCard.parse(text) else { return .invalid }
        guard card.id != myID else { return .yourself }
        if let i = friends.firstIndex(where: { $0.id == card.id }) {
            friends[i] = card
            save()
            return .updated(card.nick)
        }
        friends.append(card)
        save()
        return .added(card.nick)
    }

    func remove(_ id: String) {
        friends.removeAll { $0.id == id }
        save()
    }

    func myCard() -> FriendCard {
        let p = ProfileStore.shared, s = TraderStats.current
        var allocation: [String: Double]?
        if shareAllocation {
            let lt = LongTermStore.shared
            let parts = lt.manual.compactMap { m -> (String, Double)? in
                guard let px = lt.prices[m.symbol] else { return nil }
                return (m.symbol.replacingOccurrences(of: "USDT", with: ""), px * m.amount)
            }
            let total = parts.map(\.1).reduce(0, +)
            if total > 0 {
                allocation = Dictionary(parts.sorted { $0.1 > $1.1 }.prefix(6).map { ($0.0, ($0.1 / total * 1000).rounded() / 10) },
                                        uniquingKeysWith: +)
            }
        }
        return FriendCard(id: myID, nick: p.nickname.isEmpty ? "Trader" : p.nickname, status: p.status.rawValue, mood: p.mood,
                          bio: p.bio, trades: s.trades, winRate: s.winRate, totalR: s.totalR, weekR: s.weekR,
                          allocation: allocation, at: Date())
    }

    static func qr(_ text: String, size: CGFloat) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let k = size / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: k, y: k))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

@MainActor
struct FriendsView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = FriendsStore.shared
    @ObservedObject private var profile = ProfileStore.shared
    @Environment(\.look) private var look
    @Environment(\.motion) private var motion
    @State private var code = ""
    @State private var message: String?
    @State private var showQR = false

    private var ranked: [FriendCard] { store.friends.sorted { $0.weekR > $1.weekR } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PageTitle(tab: .friends)
                Spacer()
                PillLink(title: "Copy my code", symbol: "doc.on.doc") { copyMyCode() }
                CircleIconButton(symbol: "qrcode", label: "Show my QR code") { withAnimation(motion.small) { showQR.toggle() } }
                CircleIconButton(symbol: "gearshape", label: "Settings") { state.openSettings(.profile) }
            }
            .frame(height: 34)

            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(look.accent)
                TextField(tr("Paste a friend's code"), text: $code)
                    .textFieldStyle(.plain).font(.system(size: 12.5))
                    .onSubmit(add)
                    .onChange(of: code) { _, _ in message = nil }
                if !code.isEmpty {
                    PillLink(title: "Add", symbol: "plus") { add() }
                }
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(look.theme.chip))
            if let message {
                Text(message).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(look.accent)
            }

            PageScroll {
                VStack(alignment: .leading, spacing: 8) {
                    if showQR { qrCard.transition(.opacity) }
                    if ranked.isEmpty {
                        empty
                    } else {
                        Text(tr("This week")).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { i, f in row(f, rank: i + 1) }
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.never)
            .verticalOnly()

            FooterNote(text: tr("Friends see only what your code contains: name, status and journal stats, plus allocation in % if you allow it. No amounts, no server."))
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .frame(width: Layout.pageW, height: RenderFlags.noScroll ? nil : Layout.bodyH, alignment: .top)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2").font(.system(size: 28, weight: .light)).foregroundStyle(.white.opacity(0.4))
            Text(tr("Add your first friend")).font(.system(size: 15, weight: .bold))
            Text(tr("Send them your code, paste theirs above. You'll see each other's status and how the week is going."))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            PillLink(title: "Copy my code", symbol: "doc.on.doc") { copyMyCode() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var qrCard: some View {
        let card = store.myCard()
        return HStack(spacing: 16) {
            if let img = FriendsStore.qr(card.code, size: 150) {
                Image(nsImage: img).interpolation(.none).resizable().frame(width: 130, height: 130)
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(.white))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Your code")).font(.system(size: 14, weight: .bold))
                Text(tr("Friends scan it or paste the copied code. Share it again whenever you want them to see fresh stats."))
                    .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(tr("Share allocation in %")).font(.system(size: 12))
                    Switch(isOn: $store.shareAllocation)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
    }

    private func row(_ f: FriendCard, rank: Int) -> some View {
        let status = ProfileStatus(rawValue: f.status) ?? .trader
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(rank)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.4)).frame(width: 18)
                ZStack {
                    Circle().fill(status.gradient)
                    Text(String(f.nick.prefix(1)).uppercased()).font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28).background(Circle().fill(Color(white: 0.12)))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(f.nick).font(.system(size: 13.5, weight: .bold)).lineLimit(1)
                        Text(f.mood).font(.system(size: 12))
                        StatusBadge(title: status.rawValue, gradient: status.gradient, size: 8.5)
                    }
                    Text(f.bio.isEmpty ? tr("updated \(Fmt.date(f.at, "d MMM HH:mm"))") : f.bio + " · " + Fmt.date(f.at, "d MMM"))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 6)
                stat(tr("Week"), String(format: "%+.1fR", f.weekR), look.pnl(f.weekR))
                stat(tr("Winning"), f.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—", .white)
                stat(tr("Trades"), "\(f.trades)", .white)
            }
            if let a = f.allocation, !a.isEmpty {
                HStack(spacing: 6) {
                    ForEach(a.sorted { $0.value > $1.value }, id: \.key) { k, v in
                        Text("\(k) \(String(format: "%.0f%%", v))").font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 7).frame(height: 20)
                            .background(Capsule().fill(look.theme.chip))
                    }
                }
                .padding(.leading, 60)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(CardBackground(shape: RoundedRectangle(cornerRadius: look.corners.card, style: .continuous), fill: look.theme.card))
        .contextMenu {
            Button(tr("Remove friend"), role: .destructive) { withAnimation(motion.small) { store.remove(f.id) } }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            Text(value).font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(color)
        }
        .frame(minWidth: 56, alignment: .trailing)
    }

    private func add() {
        switch store.add(code) {
        case .added(let n): message = tr("\(n) added"); code = ""
        case .updated(let n): message = tr("\(n) updated"); code = ""
        case .yourself: message = tr("That's your own code")
        case .invalid: message = tr("Not a FinanceIsland friend code")
        }
    }

    private func copyMyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.myCard().code, forType: .string)
        message = tr("Your code is copied: send it to a friend")
    }
}
