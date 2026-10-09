import Foundation
import RingStatsCore

/// The optional value shown beside the menu-bar icon, so a glance needs no
/// click. Off by default: a number in the menu bar is visible to anyone
/// looking at the screen, so showing one is the user's choice.
enum MenuBarValuePreference: String, CaseIterable, Identifiable {
    case nothing
    case readiness
    case sleep
    case activity
    case heartRate = "heart-rate"
    case batteryWhenLow = "battery-when-low"

    static let storageKey = "menu-bar-value"

    var id: String { rawValue }

    static func resolve(_ storedValue: String?) -> MenuBarValuePreference {
        storedValue.flatMap(MenuBarValuePreference.init(rawValue:)) ?? .nothing
    }

    var title: String {
        switch self {
        case .nothing: "Nothing"
        case .batteryWhenLow: "Battery, only when low"
        default: metric?.title ?? rawValue
        }
    }

    var metric: Metric? {
        switch self {
        case .readiness: .readiness
        case .sleep: .sleep
        case .activity: .activity
        case .heartRate: .heartRate
        case .nothing, .batteryWhenLow: nil
        }
    }

    /// The text to show beside the icon, or nil to show the icon alone. A
    /// stale stat still shows, as it does in the popover; a stale battery
    /// level does not, because "low" must be current to be worth a glance.
    /// Only values that read on their own are offered: Stress ("42m") and
    /// Resilience ("Solid") would be riddles beside an icon.
    func text(for snapshot: HealthSnapshot) -> String? {
        switch self {
        case .nothing:
            return nil
        case .batteryWhenLow:
            guard !snapshot.batteryIsStale, let level = snapshot.battery?.level,
                  level < LowBatteryAlert.threshold else { return nil }
            return "\(level)%"
        case .heartRate:
            guard let reading = snapshot.readings[.heartRate], reading.hasValue else { return nil }
            return "\(reading.value) bpm"
        case .readiness, .sleep, .activity:
            guard let metric, let reading = snapshot.readings[metric], reading.hasValue else { return nil }
            return reading.value
        }
    }

    /// What VoiceOver reads for the menu-bar item.
    func accessibilityLabel(for snapshot: HealthSnapshot) -> String {
        guard let text = text(for: snapshot) else { return "Ring Stats" }
        switch self {
        case .batteryWhenLow: return "Ring Stats, battery low, \(text)"
        default: return "Ring Stats, \(title) \(text)"
        }
    }
}
