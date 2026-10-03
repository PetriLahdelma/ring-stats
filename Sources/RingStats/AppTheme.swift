import Foundation
import RingStatsCore
import RingStatsOura

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case ringStats = "ring-stats"
    case landscape
    case holographic

    static let storageKey = "selected-theme"

    static func resolve(_ storedValue: String) -> AppTheme {
        if storedValue == "oura-original" { return .landscape }
        return AppTheme(rawValue: storedValue) ?? .ringStats
    }

    var id: String { rawValue }

    /// The theme above (`-1`) or below (`1`) this one in Appearance, or nil
    /// at either end.
    func neighbor(_ offset: Int) -> AppTheme? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return nil }
        let target = index + offset
        return all.indices.contains(target) ? all[target] : nil
    }

    var title: String {
        switch self {
        case .ringStats: "Ring Stats"
        case .landscape: "Landscape"
        case .holographic: "Holographic"
        }
    }

    var summary: String {
        switch self {
        case .ringStats:
            "Warm canvas with signal-blue gauges and dark text."
        case .landscape:
            "Full-width landscape with white icons, numbers, and labels."
        case .holographic:
            "Pastel holographic gradient with black gauges, icons, and text."
        }
    }
}
