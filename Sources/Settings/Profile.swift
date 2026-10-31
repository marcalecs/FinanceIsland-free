import Foundation

enum ProfileMode: String, CaseIterable, Identifiable {
    case novice, pro
    var id: String { rawValue }

    var title: String {
        switch self {
        case .novice: return "Novice"
        case .pro: return "Quant Pro"
        }
    }

    var symbol: String {
        switch self {
        case .novice: return "leaf"
        case .pro: return "function"
        }
    }

    var blurb: String {
        switch self {
        case .novice: return "Plain words, a simple signal card and risk warnings in the Assistant."
        case .pro: return "Full statistics: barrier odds, Kelly inputs, scenario percentiles, horizon picker and data export."
        }
    }
}

enum ReportQuota: Int, CaseIterable, Identifiable {
    case mb100 = 100, mb500 = 500, gb2 = 2048, unlimited = 0
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mb100: return "100 MB"
        case .mb500: return "500 MB"
        case .gb2: return "2 GB"
        case .unlimited: return "Unlimited"
        }
    }

    var bytes: Int64? { rawValue == 0 ? nil : Int64(rawValue) * 1024 * 1024 }
}

enum RetentionPolicy: String, CaseIterable, Identifiable {
    case fifo, manual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifo: return "Auto-Prune"
        case .manual: return "Manual Clearance"
        }
    }

    var symbol: String {
        switch self {
        case .fifo: return "arrow.triangle.2.circlepath"
        case .manual: return "hand.raised"
        }
    }

    var blurb: String {
        switch self {
        case .fifo: return "Delete the oldest dossiers automatically (FIFO)."
        case .manual: return "Alert me and ask before deleting anything."
        }
    }
}
