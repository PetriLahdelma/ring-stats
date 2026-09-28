import Foundation
import RingStatsCore
import RingStatsOura

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case ringStats = "ring-stats"
    case landscape

    static let storageKey = "selected-theme"

    static func resolve(_ storedValue: String) -> AppTheme {
        if storedValue == "oura-original" { return .landscape }
        return AppTheme(rawValue: storedValue) ?? .ringStats
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ringStats: "Ring Stats"
        case .landscape: "Landscape"
        }
    }

    var summary: String {
        switch self {
        case .ringStats:
            "Warm canvas with signal-blue gauges and dark text."
        case .landscape:
            "Full-width landscape with white icons, numbers, and labels."
        }
    }
}
