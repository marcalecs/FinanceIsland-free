import Foundation

enum Legal {
    static let termsVersion = "1.5 beta"
    static let disclaimer = "Information, not investment advice. Trading involves the risk of losing money."
    static let date = "25 October 2026"
    static let appName = "FinanceIsland"
    static let author = "marcalecs"
    static let supportTelegram = "@marcalecs"
    static let supportTelegramURL = "https://t.me/marcalecs"
    static let supportEmail: String? = nil
    static let bot = "@FinanceIsland_agent"

    static func contact(or word: String) -> String {
        "[\(supportTelegram)](\(supportTelegramURL))" + (supportEmail.map { " \(word) [\($0)](mailto:\($0))" } ?? "")
    }

    static func rich(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    struct Section: Identifiable {
        let id: Int
        let title: String
        let body: String
    }

    static let agreementTitle = "User Agreement"

    static var agreement: [Section] {
        switch L10n.current {
        case .zh: return LegalZH.agreement
        case .es: return LegalES.agreement
        case .de: return LegalDE.agreement
        default: return agreementEN
        }
    }
    static var consent: [Section] {
        switch L10n.current {
        case .zh: return LegalZH.consent
        case .es: return LegalES.consent
        case .de: return LegalDE.consent
        default: return consentEN
        }
    }
    static let consentTitle = "Consent to Personal Data Processing"

    static let agreementEN: [Section] = [
        Section(id: 1, title: "1. Acceptance", body: """
        This User Agreement ("Agreement") governs your use of \(appName) ("the App"). By clicking \
        "Accept and continue" you confirm that you have read and understood this Agreement and agree \
        to be bound by it. If you do not agree, do not use the App and quit it. You confirm that you \
        are of legal age and have full legal capacity to accept this Agreement under the laws of your country.
        """),
        Section(id: 2, title: "2. What the App does", body: """
        The App shows currency, stock and cryptocurrency prices obtained from third-party sources; an \
        Assistant that turns recent prices into momentum signals (BUY, SELL as a short trade, or HOLD), \
        probabilities, simulated price scenarios, stop and target levels and a suggested position size; a \
        trader's journal; optional news headlines and summaries written by an AI service you choose; and, if \
        you choose, the balances of public wallet addresses (including the TON wallet in Wallet in Telegram) and of a \
        Binance account through a read-only key. The App is read-only: it is not a broker, never \
        asks for private keys, seed phrases, passwords or bank details, cannot place orders or sign \
        transactions, and cannot move funds. Wallet in Telegram has no read-only API, so the App never connects \
        to a Wallet account; Wallet Perps positions appear only from files you place in the App's Inbox folder.
        """),
        Section(id: 3, title: "3. Not financial advice", body: """
        Everything the App shows is general information produced by automated models. It is not financial, \
        investment, tax or legal advice, not an offer, and not a recommendation to buy, sell, short or hold \
        any asset. Signals, probabilities, scenarios, levels and position sizes are estimates calculated from \
        past prices with fixed mechanical rules and random simulations; they do not know your goals, finances \
        or risk tolerance, can be wrong, and past behaviour does not predict future results. Intraday trading \
        and short selling are especially risky: prices can move fast, gaps can jump over a stop, and you can \
        lose more than you expected. Prices may be delayed, incomplete or inaccurate and may differ from \
        those at your bank, broker or exchange. AI summaries can be wrong or out of date. Always check \
        information with an authoritative source, consider talking to a licensed adviser, and only risk money \
        you can afford to lose.
        """),
        Section(id: 4, title: "4. Your decisions", body: """
        You alone decide whether and how to trade. Any order you place is placed by you, with a broker or \
        exchange of your choice, under their terms. The App does not monitor your positions and will not warn \
        you when a stop or target is reached.
        """),
        Section(id: 5, title: "5. No warranty", body: """
        The App is provided "as is" and "as available", without warranties of any kind, express or implied, \
        including warranties of accuracy, completeness, timeliness, merchantability, fitness for a particular \
        purpose or uninterrupted operation. Data sources may change, be delayed or stop working at any time.
        """),
        Section(id: 6, title: "6. Limitation of liability", body: """
        To the maximum extent permitted by applicable law, the developer of the App shall not be liable for \
        any direct, indirect, incidental, special, consequential or punitive damages, including trading or \
        investment losses, loss of profits, loss of data or business interruption, arising out of or in \
        connection with the use of, or inability to use, the App, reliance on any signal or data shown in it, \
        or the operation of third-party services. You use the App at your own risk. Nothing in this Agreement \
        limits liability that cannot be limited under applicable law.
        """),
        Section(id: 7, title: "7. Third-party services", body: """
        The App connects to services that are not controlled by the developer: Yahoo Finance, Binance, \
        Coinbase, Kraken, CoinGecko, Nasdaq, the Federal Reserve Bank of St. Louis (FRED), the European \
        Central Bank, ExchangeRate-API, CBOE and US Treasury data, news feeds, public Ethereum RPC providers \
        (publicnode.com, llamarpc.com, ankr.com), mempool.space, the public Solana RPC, toncenter.com, tonapi.io, the Binance \
        account API (only with a read-only key you add) and, only if you turn it on, the AI service you select. \
        Their own terms and privacy policies apply to those connections. The developer is not responsible for \
        their availability, content or data handling. The App connects to no server operated by the developer. Pro licences come from the Telegram bot \(bot) \
        (see the Consent, "Operations and storage").
        """),
        Section(id: 8, title: "8. Licence and restrictions", body: """
        \(appName) is © 2026 \(author). All rights reserved. You are granted a personal, non-exclusive, non-transferable licence to use the App on your own \
        devices. You may not use the App for any unlawful purpose, to offer investment services to others, or \
        in a way that violates the terms of the data sources it relies on.
        """),
        Section(id: 9, title: "9. Changes and termination", body: """
        The developer may update the App and this Agreement. When the text changes, the App will ask you to \
        accept the new version before you can continue. You may stop using the App at any time by quitting and \
        deleting it, and you may withdraw your consent in Settings ▸ About.
        """),
        Section(id: 10, title: "10. Contact", body: """
        The App is developed by \(author). Questions about this Agreement, payments or your data: Telegram \
        \(contact(or: "or e-mail")).
        """),
        Section(id: 11, title: "11. Payments and refunds", body: """
        Subscriptions are sold for Telegram Stars through the bot \(bot). For a refund or a payment problem, send \
        /paysupport to \(bot) or write to \(contact(or: "or")). Stars are refunded through Telegram under its \
        rules. Access to subscriber features ends when a payment is refunded.
        """),
        Section(id: 12, title: "12. AI providers", body: """
        AI news summaries are off by default. If you turn them on and choose a provider (Pollinations, Groq, \
        Google Gemini, OpenRouter, or Ollama running on your own Mac), the asset's name and its latest headlines \
        (title, publisher, date) are sent to that provider to write the summary. That provider's own terms and \
        privacy policy apply. Your portfolio, wallets, exchange keys, journal and settings are never sent. You \
        can turn summaries off at any time in Settings ▸ Assistant.
        """),
    ]

    static let consentEN: [Section] = [
        Section(id: 101, title: "Consent", body: """
        By ticking the consent box you freely, specifically, knowingly and unambiguously consent to the \
        processing of your personal data by the developer of \(appName) on the terms below, including where \
        applicable under the EU General Data Protection Regulation (GDPR), the UK GDPR and the California \
        Consumer Privacy Act (CCPA).
        """),
        Section(id: 102, title: "Data processed", body: """
        • The public Ethereum wallet address you enter, if any. A public address can in some cases be linked \
        to a real person, so it is treated as personal data.
        • Your App settings: currencies, watched stocks and crypto pairs, appearance and the AI provider you \
        selected. API keys you enter are kept in the macOS Keychain.
        • Your trader's journal: the notes, trades, prices and tags you write.
        • Local market data: price history, signal changes, engine reports and cached AI answers.
        • An app log of errors and events (it can be turned off and cleared in Settings ▸ Logs).
        • The date and version of the Agreement you accepted.
        • If you buy Pro: your Telegram ID, your payments and the Mac code you send to the bot (the first 16 \
        characters of a one-way hash of your Mac's hardware identifier), kept by the bot to issue licences.
        • Technical data that is necessarily transmitted when the App connects to the internet, such as your \
        IP address, which becomes visible to the services listed in section 7.
        """),
        Section(id: 103, title: "Purposes", body: """
        To show prices, to calculate signals, probabilities and plans, to keep your journal, to show the \
        balance of the address you chose to watch, to remember your settings, to help find problems through \
        the app log, and to record that you accepted this Agreement.
        """),
        Section(id: 104, title: "Operations and storage", body: """
        Collection, recording, storage, use, transfer and deletion. All data stays on your Mac: in the App's \
        preferences, in ~/Library/Application Support/FinanceIsland (database, journal, reports), in \
        ~/Library/Logs/FinanceIsland (app log) and in the Keychain. Settings ▸ Logs shows each folder and its \
        size. The App sends nothing to the developer. If you buy Pro, the Telegram bot \(bot) keeps your Telegram ID, \
        your payments and up to two Mac codes to sign offline licences; the licence is checked on your Mac without a \
        network. Your portfolio, wallet addresses, exchange keys, journal and settings are never sent to the bot. The wallet address is sent only \
        to the Ethereum RPC providers in section 7, to request its balance. When AI news summaries are on, the \
        asset name and its public headlines are sent to the AI service you selected (section 12); your journal, \
        wallet address and settings are never sent. No data is sold or used for advertising.
        """),
        Section(id: 105, title: "Term and withdrawal", body: """
        This consent is valid until you withdraw it. You can withdraw it at any time in Settings ▸ About ▸ \
        Withdraw consent: the App will immediately delete all data it stored, including your journal, and \
        return to the welcome screen. Deleting the App also ends processing. You have the right to access, \
        correct and delete your data, which you can do directly in the App.
        """),
    ]
}
