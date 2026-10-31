import AppKit
import SwiftUI

private let accentGreen = Accent.green.color
private let errorRed = TrendPalette.classic.red
private let windowW: CGFloat = 560
private let windowH: CGFloat = 700

enum OnboardingStep: Int, CaseIterable {
    case language, terms, tour, wallet, profile

    static var shown: [OnboardingStep] {
        allCases.filter { $0 != .profile }
    }

    var title: String {
        switch self {
        case .language: return "Language"
        case .terms: return "Agreement"
        case .tour: return "Tour"
        case .wallet: return "Wallet"
        case .profile: return "Profile"
        }
    }
}

@MainActor
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    var onDone: @MainActor () -> Void

    @State private var step: OnboardingStep = .language
    @State private var forward = true
    @State private var tourSlide = 0
    @State private var acceptTerms = false
    @State private var acceptData = false
    @State private var address = ""
    @State private var error: String?
    private var preview: (step: OnboardingStep, slide: Int)?

    init(settings: AppSettings, onDone: @escaping @MainActor () -> Void) {
        self.settings = settings
        self.onDone = onDone
    }

    init(settings: AppSettings, previewStep: OnboardingStep, tourSlide slide: Int = 0) {
        self.settings = settings
        self.onDone = {}
        preview = (previewStep, slide)
        _step = State(initialValue: previewStep)
        _tourSlide = State(initialValue: slide)
    }

    private var agreementOnly: Bool { settings.onboarded && !settings.hasAcceptedTerms }

    var body: some View {
        ZStack {
            Group {
                switch step {
                case .language: languagePage
                case .terms: termsPage
                case .tour: tourPage
                case .wallet: walletPage
                case .profile: profilePage
                }
            }
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            if !agreementOnly { stepDots.frame(maxHeight: .infinity, alignment: .top).padding(.top, 16) }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: step)
        .frame(width: windowW, height: windowH)
        .foregroundStyle(.white)
        .background(Color(white: 0.086))
        .onAppear {
            address = settings.walletAddress ?? ""
            if preview == nil { step = agreementOnly ? .terms : .language }
        }
    }

    private func go(_ s: OnboardingStep) {
        forward = s.rawValue > step.rawValue
        if s == .tour { tourSlide = 0 }
        step = s
    }

    private func next(after s: OnboardingStep) {
        switch s {
        case .language: go(settings.hasAcceptedTerms ? .tour : .terms)
        case .terms: go(.tour)
        case .tour: go(.wallet)
        case .wallet: if OnboardingStep.shown.contains(.profile) { go(.profile) } else { finish() }
        case .profile: finish()
        }
    }

    private func back(from s: OnboardingStep) {
        switch s {
        case .tour: go(.language)
        case .wallet: go(.tour)
        case .profile: go(.wallet)
        default: go(.language)
        }
    }

    private func finish() {
        settings.onboarded = true
        onDone()
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.shown, id: \.self) { s in
                Capsule()
                    .fill(s == step ? accentGreen : Color.white.opacity(s.rawValue < step.rawValue ? 0.45 : 0.16))
                    .frame(width: s == step ? 22 : 7, height: 7)
            }
            Text(tr("Step \(step.rawValue + 1) of \(OnboardingStep.shown.count) · \(tr(step.title))"))
                .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.4)).padding(.leading, 6)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: step)
    }

    private var languagePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            appIcon.scaleEffect(1.25).padding(.bottom, 22)
            Text(tr("Welcome to FinanceIsland")).font(.system(size: 30, weight: .bold))
            Text(tr(Self.welcome)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440).padding(.top, 8)
            HStack(spacing: 10) {
                feature("briefcase", "Hold")
                feature("chart.line.uptrend.xyaxis", "Trade")
                feature("chart.bar.xaxis", "Markets")
            }
            .padding(.top, 26)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(Self.languageOrder) { lang in
                    let on = settings.language == lang
                    Button { settings.language = lang } label: {
                        HStack(spacing: 5) {
                            if lang == .system { Image(systemName: "globe").font(.system(size: 11, weight: .semibold)) }
                            Text(lang.name).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(on ? 0.16 : 0.05)))
                        .overlay(Capsule().stroke(on ? accentGreen.opacity(0.7) : .clear))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(Self.languageSubtitle(lang))
                }
            }
            primaryButton("Get started") { next(after: .language) }.frame(width: 240).padding(.top, 18)
            Text(tr("version \(AppInfo.version) · you can change the language later in Settings"))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.35)).padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 52)
        .padding(.bottom, 28)
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(accentGreen)
            Text(tr(title)).font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 120, height: 78)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
    }

    private static let languageOrder: [AppLanguage] = [.en, .zh, .es, .de, .system]

    private static func languageSubtitle(_ l: AppLanguage) -> String {
        switch l {
        case .en: return "Continue in English"
        case .zh: return "使用简体中文继续"
        case .es: return "Continuar en español"
        case .de: return "Auf Deutsch fortfahren"
        case .system: return tr("Follow the Mac")
        }
    }

    private var termsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                appIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Welcome to FinanceIsland"))
                        .font(.system(size: 24, weight: .bold))
                    Text(tr("Rates, scalping, long-term advice and your wallets under the notch · version \(AppInfo.version)"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Text(tr("Before you start, please read and accept the user agreement. FinanceIsland shows market data and model estimates, not financial advice. It never touches your money and keeps your data on this Mac."))
                .font(.system(size: 13.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Label(tr(Legal.disclaimer), systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Accent.orange.color)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(tr(Legal.agreementTitle)).font(.system(size: 15, weight: .bold))
                    Text(tr("Version \(Legal.termsVersion) · \(Legal.date)"))
                        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                    ForEach(Legal.agreement) { sectionView($0) }
                    Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 4)
                    Text(tr(Legal.consentTitle)).font(.system(size: 15, weight: .bold))
                    ForEach(Legal.consent) { sectionView($0) }
                }
                .padding(18)
                .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1)))

            VStack(alignment: .leading, spacing: 10) {
                checkbox("I have read and accept the User Agreement, including the disclaimer of liability.",
                         isOn: $acceptTerms)
                checkbox("I consent to the processing of my personal data as described above.",
                         isOn: $acceptData)
            }

            HStack(spacing: 10) {
                Button { NSApp.terminate(nil) } label: {
                    Text(tr("Decline and quit"))
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.16)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { accept() } label: {
                    Text(tr("Accept and continue"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.96)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!(acceptTerms && acceptData))
                .opacity(acceptTerms && acceptData ? 1 : 0.45)
                .animation(.easeInOut(duration: 0.15), value: acceptTerms && acceptData)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, agreementOnly ? 40 : 48)
        .padding(.bottom, 28)
    }

    private func sectionView(_ s: Legal.Section) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr(s.title)).font(.system(size: 12.5, weight: .semibold))
            Text(Legal.rich(tr(s.body)))
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func checkbox(_ text: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isOn.wrappedValue ? accentGreen : .white.opacity(0.5))
                Text(tr(text))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func accept() {
        guard acceptTerms && acceptData else { return }
        let only = agreementOnly
        settings.acceptTerms()
        if only { onDone() } else { next(after: .terms) }
    }

    private var walletPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            appIcon

            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Track a wallet?"))
                    .font(.system(size: 26, weight: .bold))
                Text(tr("Watch a public wallet address to see your ETH balance, or continue as a guest. Either way you can follow any currencies and crypto you like, and change this later in Settings."))
                    .font(.system(size: 14.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("WALLET ADDRESS"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                TextField(tr("0x…"), text: $address)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14).monospacedDigit())
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(error == nil ? Color.white.opacity(0.14) : errorRed))
                    .onSubmit { watch() }
                Text(error ?? "Read-only. Nothing to sign, no keys ever leave your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(error == nil ? Color.white.opacity(0.5) : errorRed)
            }

            VStack(spacing: 10) {
                Button { watch() } label: {
                    Label(tr("Watch wallet"), systemImage: "wallet.pass")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.96)))
                        .foregroundStyle(.black)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { guest() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                        Text(tr("Continue as guest")).fontWeight(.semibold)
                        Text(tr("· pick currencies later")).foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.16)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            HStack {
                ghostButton("Back") { back(from: .wallet) }
                Spacer()
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 52)
        .padding(.bottom, 28)
    }

    private static let welcome = "Live rates, your portfolio, wallets and trading journal under the notch"

    private static let tour: [(title: String, body: String, points: [String])] = [
        ("The Dynamic Island",
         "A small pill sits under the MacBook notch: out of the way, with your numbers one glance away.",
         ["Tabs: Home, Markets, Portfolio and Trade.",
          "Hover the notch to open the island; click a card for its full chart, or open it in its own window.",
          "Move the pointer away and it folds back into the pill."]),
        ("Markets and Portfolio",
         "Prices, volatility estimates and what you hold. No signals and no advice.",
         ["Markets: currencies, coins and stocks with charts, price alerts and a volatility band that is an estimate, not a forecast.",
          "Portfolio: your wallets and positions with entry prices, live profit and a comparison with the S&P 500 and BTC.",
          "Everything is computed on this Mac: no server, no account."]),
        ("Wallet, journal and paper trading",
         "Watch wallets on four chains, keep a journal of your trades and practise without risking money.",
         ["Ethereum, Bitcoin, Solana and TON wallets, plus Binance with a read-only key and Wallet Perps from the Inbox.",
          "A trader's journal with results in R, and paper trading on live quotes: no orders are ever sent.",
          "Settings ▸ About shows every folder the app writes to and how much it holds."]),
    ]

    private var tourPage: some View {
        let slide = Self.tour[tourSlide]
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tr("PRODUCT TOUR · \(tourSlide + 1) OF \(Self.tour.count)"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Button { settings.tourCompleted = false; next(after: .tour) } label: {
                    Text(tr("Skip Tour"))
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 30)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.22)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tr("Jump straight to the wallet setup"))
                .keyboardShortcut(.cancelAction)
            }
            TourArt(slide: tourSlide, accent: accentGreen)
                .frame(height: 200)
                .id(tourSlide)
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 10) {
                Text(tr(slide.title)).font(.system(size: 24, weight: .bold))
                Text(tr(slide.body)).font(.system(size: 14)).foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(slide.points, id: \.self) { pt in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(accentGreen).frame(width: 6, height: 6).padding(.top, 6)
                        Text(tr(pt)).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .id("text\(tourSlide)")
            .transition(.opacity)
            Spacer(minLength: 0)
            HStack {
                ghostButton("Back") {
                    if tourSlide == 0 { back(from: .tour) } else { withAnimation { tourSlide -= 1 } }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<Self.tour.count, id: \.self) { i in
                        Capsule().fill(i == tourSlide ? Color.white : Color.white.opacity(0.22))
                            .frame(width: i == tourSlide ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                primaryButton(tourSlide == Self.tour.count - 1 ? "Finish Tour" : "Next") {
                    if tourSlide == Self.tour.count - 1 {
                        settings.tourCompleted = true
                        next(after: .tour)
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) { tourSlide += 1 }
                    }
                }
                .frame(width: 160)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 52)
        .padding(.bottom, 28)
    }

    private var profilePage: some View { EmptyView() }

    private func sectionLabel(_ s: String) -> some View {
        Text(tr(s)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).padding(.top, 4)
    }

    private func choiceCard(selected: Bool, symbol: String?, badge: String?, title: String, subtitle: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? .black : .white.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(selected ? accentGreen : Color.white.opacity(0.1)))
                    } else if let badge {
                        Text(badge).font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(selected ? .black : .white.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(selected ? accentGreen : Color.white.opacity(0.1)))
                    }
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(accentGreen) }
                }
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? accentGreen.opacity(0.12) : Color(white: 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? accentGreen : Color.white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(tr(title))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.96)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    private func ghostButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(tr(title)).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appIcon: some View { AppLogo(size: 56, color: accentGreen) }

    private func watch() {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AppSettings.isValidAddress(a) else {
            error = "That doesn't look like an Ethereum address (0x + 40 hex characters)."
            return
        }
        error = nil
        settings.walletAddress = a
        next(after: .wallet)
    }

    private func guest() {
        settings.walletAddress = nil
        next(after: .wallet)
    }
}

private struct TourArt: View {
    let slide: Int
    let accent: Color

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 16, style: .continuous), with: .color(Color(white: 0.05)))
                ctx.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 16, style: .continuous),
                           with: .color(.white.opacity(0.1)))
                switch slide {
                case 0: island(ctx, size, t)
                case 1: quant(ctx, size, t)
                default: dossiers(ctx, size, t)
                }
            }
        }
    }

    private func ease(_ x: Double) -> Double { 1 - pow(1 - min(max(x, 0), 1), 3) }

    private func island(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let cx = size.width / 2
        ctx.fill(Path(roundedRect: CGRect(x: 14, y: 12, width: size.width - 28, height: 18), cornerRadius: 6),
                 with: .color(.white.opacity(0.07)))
        let ph = t.truncatingRemainder(dividingBy: 4)
        let k = ph < 1 ? 0 : ph < 1.6 ? ease((ph - 1) / 0.6) : ph < 3 ? 1 : 1 - ease((ph - 3) / 0.5)
        let w = 130 + (300 - 130) * k, h = 26 + (150 - 26) * k
        let r = CGRect(x: cx - w / 2, y: 12, width: w, height: h)
        ctx.fill(Path(roundedRect: r, cornerRadius: 13 + 9 * k, style: .continuous), with: .color(.black))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 13 + 9 * k, style: .continuous), with: .color(.white.opacity(0.12)))
        if k < 0.35 {
            let a = 1 - k / 0.35
            ctx.fill(Path(ellipseIn: CGRect(x: r.minX + 12, y: r.midY - 3.5, width: 7, height: 7)), with: .color(accent.opacity(a)))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + 26, y: r.midY - 3, width: 40, height: 6), cornerRadius: 3), with: .color(.white.opacity(0.6 * a)))
            ctx.fill(Path(roundedRect: CGRect(x: r.maxX - 44, y: r.midY - 3, width: 32, height: 6), cornerRadius: 3), with: .color(accent.opacity(a)))
        }
        if k > 0.55 {
            let a = (k - 0.55) / 0.45
            for i in 0..<3 {
                let card = CGRect(x: r.minX + 14 + CGFloat(i) * (r.width - 28) / 3, y: r.minY + 34, width: (r.width - 28) / 3 - 8, height: 54)
                ctx.fill(Path(roundedRect: card, cornerRadius: 10), with: .color(.white.opacity(0.08 * a)))
                ctx.fill(Path(roundedRect: CGRect(x: card.minX + 8, y: card.minY + 10, width: 30, height: 6), cornerRadius: 3), with: .color(.white.opacity(0.5 * a)))
                ctx.fill(Path(roundedRect: CGRect(x: card.minX + 8, y: card.minY + 24, width: card.width - 16, height: 14), cornerRadius: 3), with: .color(accent.opacity(0.35 * a)))
            }
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + 14, y: r.minY + 100, width: r.width * 0.55, height: 8), cornerRadius: 4), with: .color(.white.opacity(0.25 * a)))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + 14, y: r.minY + 116, width: r.width * 0.35, height: 8), cornerRadius: 4), with: .color(.white.opacity(0.15 * a)))
        }
    }

    private func quant(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let plot = CGRect(x: 20, y: 36, width: size.width - 40, height: size.height - 58)
        let histW = plot.width * 0.6, n = 40
        func y(_ v: Double) -> CGFloat { plot.midY - CGFloat(v) * plot.height * 0.42 }
        var pts: [CGPoint] = []
        for i in 0...n {
            let v = -0.55 + 0.9 * Double(i) / Double(n) + 0.12 * sin(Double(i) * 0.9) + 0.06 * sin(Double(i) * 2.3)
            pts.append(CGPoint(x: plot.minX + histW * CGFloat(i) / CGFloat(n), y: y(v)))
        }
        let now = pts.last!
        for (k, op) in [(1.0, 0.16), (0.45, 0.28)] {
            var top: [CGPoint] = [], bot: [CGPoint] = []
            for d in 0...20 {
                let x = now.x + (plot.maxX - now.x) * CGFloat(d) / 20, spread = CGFloat(sqrt(Double(d) / 20)) * plot.height * 0.32 * CGFloat(k)
                let c = now.y - CGFloat(d) / 20 * 10
                top.append(CGPoint(x: x, y: c - spread)); bot.append(CGPoint(x: x, y: c + spread))
            }
            var p = Path(); p.addLines(top + bot.reversed()); p.closeSubpath()
            ctx.fill(p, with: .color(Color.blue.opacity(op)))
        }
        let wob = CGFloat(sin(t * 1.4)) * 6
        for (yy, c, label) in [(now.y - plot.height * 0.36 + wob, Color.green, "TARGET"), (now.y + plot.height * 0.2 - wob / 2, Color.red, "STOP")] {
            var l = Path(); l.move(to: CGPoint(x: now.x, y: yy)); l.addLine(to: CGPoint(x: plot.maxX, y: yy))
            ctx.stroke(l, with: .color(c.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            ctx.draw(Text(label).font(.system(size: 9.5, weight: .bold)).foregroundColor(c), at: CGPoint(x: plot.maxX, y: yy - 8), anchor: .trailing)
        }
        let shown = max(2, Int((t * 18).truncatingRemainder(dividingBy: Double(n + 30))))
        var h = Path(); h.addLines(Array(pts.prefix(min(shown, pts.count))))
        ctx.stroke(h, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        if shown > n {
            var m = Path(); m.move(to: now); m.addLine(to: CGPoint(x: plot.maxX, y: now.y - 10))
            ctx.stroke(m, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            ctx.fill(Path(ellipseIn: CGRect(x: now.x - 4.5, y: now.y - 4.5, width: 9, height: 9)), with: .color(.white))
        }
        ctx.draw(Text("15m · MOMENTUM +1.2 · BUY").font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.45)),
                 at: CGPoint(x: plot.minX, y: 18), anchor: .leading)
        ctx.draw(Text("C++").font(.system(size: 10, weight: .heavy)).foregroundColor(accent.opacity(0.8)),
                 at: CGPoint(x: plot.maxX, y: 18), anchor: .trailing)
    }

    private func dossiers(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let rows: [(String, String, Double)] = [("BTC", "BUY", 1.8), ("EUR/RUB", "SELL", -1.0), ("AAPL", "BUY", 2.1), ("ETH", "SELL", 0.6)]
        let k = Int((t * 0.8).truncatingRemainder(dividingBy: Double(rows.count + 2)))
        for (i, r) in rows.enumerated() where i <= k {
            let y = 22 + CGFloat(i) * 38
            let card = CGRect(x: 18, y: y, width: size.width * 0.56, height: 30)
            ctx.fill(Path(roundedRect: card, cornerRadius: 8), with: .color(.white.opacity(0.07)))
            ctx.draw(Text(r.0).font(.system(size: 11, weight: .bold)).foregroundColor(.white), at: CGPoint(x: card.minX + 12, y: card.midY), anchor: .leading)
            let sc: Color = r.1 == "BUY" ? .green : .red
            ctx.draw(Text(r.1).font(.system(size: 9.5, weight: .heavy)).foregroundColor(sc), at: CGPoint(x: card.minX + 86, y: card.midY), anchor: .leading)
            ctx.draw(Text(String(format: "%+.1fR", r.2)).font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundColor(r.2 >= 0 ? .green : .red), at: CGPoint(x: card.maxX - 12, y: card.midY), anchor: .trailing)
        }
        let box = CGRect(x: size.width * 0.64, y: 30, width: size.width * 0.32, height: size.height - 60)
        ctx.fill(Path(roundedRect: box, cornerRadius: 10), with: .color(.white.opacity(0.05)))
        var eq = 0.0, pts = [CGPoint(x: box.minX + 10, y: box.midY)]
        for (i, r) in rows.enumerated() where i <= k {
            eq += r.2
            pts.append(CGPoint(x: box.minX + 10 + (box.width - 20) * CGFloat(i + 1) / CGFloat(rows.count), y: box.midY - CGFloat(eq) * 14))
        }
        var p = Path(); p.addLines(pts)
        ctx.stroke(p, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        ctx.draw(Text(String(format: "TOTAL %+.1fR", eq)).font(.system(size: 10.5, weight: .bold).monospacedDigit()).foregroundColor(accent),
                 at: CGPoint(x: box.minX + 10, y: box.minY + 14), anchor: .leading)
    }
}

@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var settings: AppSettings?
    var onFinished: (@MainActor () -> Void)?

    func show(settings: AppSettings, rates: RateStore) {
        self.settings = settings
        window?.delegate = nil
        window?.close()

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: windowW, height: windowH),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(calibratedWhite: 0.086, alpha: 1)
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.delegate = self

        let view = OnboardingView(
            settings: settings,
            onDone: { [weak self] in
                rates.walletChanged()
                self?.finish()
            })
        w.contentView = NSHostingView(rootView: view)
        w.setContentSize(NSSize(width: windowW, height: windowH))
        window = w

        w.center()
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.delegate = nil
        window?.close()
        window = nil
        onFinished?()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let settings, !settings.hasAcceptedTerms else {
                if let settings, !settings.onboarded { settings.onboarded = true }
                window = nil
                onFinished?()
                return
            }
            NSApp.terminate(nil)
        }
    }
}
