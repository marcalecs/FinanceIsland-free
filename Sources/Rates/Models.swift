import Foundation

enum AssetKind: String {
    case fiat = "fx"
    case crypto = "cr"
}

struct Asset: Identifiable, Hashable {
    let kind: AssetKind
    let code: String
    let name: String
    let yahoo: String
    let unit: String
    let base: String
    var id: String { kind.rawValue + ":" + code }

    var isFiat: Bool { kind == .fiat }

    static func make(id: String, base: String) -> Asset? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let kind = AssetKind(rawValue: parts[0]) else { return nil }
        return make(kind: kind, code: parts[1], base: base)
    }

    static func make(kind: AssetKind, code: String, base: String) -> Asset {
        let entry = Catalog.entry(kind: kind, code: code)
        switch kind {
        case .fiat:
            return Asset(kind: .fiat, code: code, name: entry?.name ?? code,
                         yahoo: "\(code)\(base)=X", unit: Catalog.symbol(base), base: base)
        case .crypto:
            return Asset(kind: .crypto, code: code, name: entry?.name ?? code,
                         yahoo: entry?.yahoo ?? "\(code)-USD", unit: "USD", base: "USD")
        }
    }

    static let ethID = "cr:ETH"
}

struct CatalogEntry: Identifiable, Hashable {
    let kind: AssetKind
    let code: String
    let name: String
    var yahoo: String? = nil
    var id: String { kind.rawValue + ":" + code }
}

enum Catalog {
    static let fiat: [CatalogEntry] = [
        ("USD", "US Dollar"), ("EUR", "Euro"), ("GBP", "British Pound"), ("JPY", "Japanese Yen"),
        ("CNY", "Chinese Yuan"), ("CHF", "Swiss Franc"), ("CAD", "Canadian Dollar"), ("AUD", "Australian Dollar"),
        ("NZD", "New Zealand Dollar"), ("HKD", "Hong Kong Dollar"), ("SGD", "Singapore Dollar"), ("INR", "Indian Rupee"),
        ("KRW", "South Korean Won"), ("MXN", "Mexican Peso"), ("BRL", "Brazilian Real"), ("SEK", "Swedish Krona"),
        ("NOK", "Norwegian Krone"), ("ZAR", "South African Rand"), ("TRY", "Turkish Lira"), ("AED", "UAE Dirham"),
    ].map { CatalogEntry(kind: .fiat, code: $0.0, name: $0.1) }

    static let crypto: [CatalogEntry] = [
        CatalogEntry(kind: .crypto, code: "BTC", name: "Bitcoin"),
        CatalogEntry(kind: .crypto, code: "ETH", name: "Ethereum"),
        CatalogEntry(kind: .crypto, code: "SOL", name: "Solana"),
        CatalogEntry(kind: .crypto, code: "TON", name: "Toncoin", yahoo: "TON11419-USD"),
        CatalogEntry(kind: .crypto, code: "USDT", name: "Tether"),
        CatalogEntry(kind: .crypto, code: "BNB", name: "BNB"),
        CatalogEntry(kind: .crypto, code: "XRP", name: "XRP"),
        CatalogEntry(kind: .crypto, code: "DOGE", name: "Dogecoin"),
        CatalogEntry(kind: .crypto, code: "ADA", name: "Cardano"),
        CatalogEntry(kind: .crypto, code: "TRX", name: "TRON"),
    ]

    static let bases = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "CNY"]

    static func entry(kind: AssetKind, code: String) -> CatalogEntry? {
        (kind == .fiat ? fiat : crypto).first { $0.code == code }
    }

    static func symbol(_ code: String) -> String {
        switch code {
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "CNY": return "CN¥"
        case "JPY": return "¥"
        case "TRY": return "₺"
        case "INR": return "₹"
        case "KRW": return "₩"
        default: return code
        }
    }
}

enum ChartStyle: String, CaseIterable, Identifiable {
    case line = "Line", area = "Area", bars = "Bars", step = "Steps"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .line: return "chart.xyaxis.line"
        case .area: return "chart.line.uptrend.xyaxis"
        case .bars: return "chart.bar.xaxis"
        case .step: return "stairs"
        }
    }
}

enum SparkRange: String, CaseIterable, Identifiable {
    case d5 = "5D", m1 = "1M", m3 = "3M"
    var id: String { rawValue }
    var yahoo: String {
        switch self {
        case .d5: return "5d"
        case .m1: return "1mo"
        case .m3: return "3mo"
        }
    }
    var label: String {
        switch self {
        case .d5: return "5 days"
        case .m1: return "30 days"
        case .m3: return "3 months"
        }
    }
}

enum Timeframe: String, CaseIterable, Identifiable {
    case h1 = "1H", h24 = "24H", w1 = "1W", m1 = "1M", all = "ALL"
    var id: String { rawValue }

    var range: String {
        switch self {
        case .h1: return "1d"
        case .h24: return "5d"
        case .w1, .m1: return "1mo"
        case .all: return "max"
        }
    }
    var interval: String {
        switch self {
        case .h1: return "1m"
        case .h24: return "15m"
        case .w1: return "1h"
        case .m1: return "1d"
        case .all: return "1mo"
        }
    }
    var window: TimeInterval? {
        switch self {
        case .h1: return 3600
        case .h24: return 86_400
        case .w1: return 7 * 86_400
        case .m1, .all: return nil
        }
    }
    var axisFormat: String {
        switch self {
        case .h1, .h24: return "HH:mm"
        case .w1, .m1: return "d MMM"
        case .all: return "MMM yyyy"
        }
    }
    var tableFormat: String {
        switch self {
        case .h1, .h24, .w1: return "MMM d, HH:mm"
        case .m1: return "MMM d"
        case .all: return "MMM yyyy"
        }
    }
}

struct PricePoint: Hashable {
    let time: Date
    let value: Double
}

struct Quote {
    let price: Double
    let prev: Double
    let history: [Double]
    var asOf: Date? = nil
    var change: Double { price - prev }
    var pct: Double { prev == 0 ? 0 : change / prev * 100 }
    var isUp: Bool { price >= prev }
}

enum Fmt {
    nonisolated(unsafe) private static var numberCache: [Int: NumberFormatter] = [:]
    nonisolated(unsafe) private static var dateCache: [String: DateFormatter] = [:]

    static func number(_ v: Double, min: Int = 2, max: Int = 2) -> String {
        let key = min * 100 + max
        let f = numberCache[key] ?? {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.locale = Locale(identifier: "en_US")
            f.minimumFractionDigits = min
            f.maximumFractionDigits = max
            numberCache[key] = f
            return f
        }()
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    static func amount(_ v: Double) -> String {
        let a = abs(v)
        if a >= 10 || a == 0 { return number(v) }
        if a >= 1 { return number(v, min: 4, max: 4) }
        if a >= 0.01 { return number(v, min: 4, max: 4) }
        return number(v, min: 6, max: 6)
    }

    static func price(_ v: Double, _ a: Asset) -> String {
        amount(v) + " " + a.unit
    }

    static func date(_ d: Date, _ format: String) -> String {
        let lang = L10n.current
        let key = format + "|" + lang.rawValue
        let f = dateCache[key] ?? {
            let f = DateFormatter()
            f.locale = lang == .en ? Locale(identifier: "en_US_POSIX") : lang.locale
            f.dateFormat = format
            dateCache[key] = f
            return f
        }()
        return f.string(from: d)
    }

    static func shortAddress(_ a: String) -> String {
        guard a.count > 10 else { return a }
        return String(a.prefix(5)) + "…" + String(a.suffix(4))
    }
}
