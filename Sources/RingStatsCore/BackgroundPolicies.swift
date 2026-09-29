import Foundation

/// When a scheduled background refresh may fetch. It keeps the popover fresh
/// without drawing power the user needs elsewhere.
package enum BackgroundRefreshPolicy {
    /// How often the scheduler wakes the app.
    package static let interval: TimeInterval = 30 * 60
    /// The minimum age of the data before a refresh on battery power or in Low
    /// Power Mode.
    package static let constrainedInterval: TimeInterval = 2 * 3_600

    /// - Parameters:
    ///   - lastFetchedAt: When the current data was fetched, or nil if none.
    ///   - constrained: Whether the Mac is on battery power or in Low Power Mode.
    package static func shouldRefresh(lastFetchedAt: Date?, now: Date, constrained: Bool) -> Bool {
        guard constrained, let lastFetchedAt else { return true }
        // The scheduler fires within a tolerance, so allow a little early.
        return now.timeIntervalSince(lastFetchedAt) >= constrainedInterval * 0.9
    }
}

/// Decides when to announce a low ring battery: once when the level drops
/// below the threshold, and not again until the ring has been charging. An old
/// reading kept from an earlier refresh never triggers it.
package struct LowBatteryAlert: Sendable, Equatable {
    /// The level at which the battery icon also turns to Alert.
    package static let threshold = 20

    package private(set) var isArmed = true

    package init() {}

    /// Returns the level to announce, or nil when nothing should be announced.
    package mutating func evaluate(_ battery: BatteryReading?, isStale: Bool) -> Int? {
        guard let battery, !isStale, let level = battery.level else { return nil }
        if battery.isCharging {
            isArmed = true
            return nil
        }
        guard level < Self.threshold, isArmed else { return nil }
        isArmed = false
        return level
    }
}
