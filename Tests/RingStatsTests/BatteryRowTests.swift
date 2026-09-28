import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore

/// What the battery row says for each charging state.
@MainActor
struct BatteryRowTests {
    private func row(_ battery: BatteryReading?, needsPermission: Bool = false) -> BatteryRow {
        BatteryRow(battery: battery, loading: false, needsPermission: needsPermission, theme: .ringStats)
    }

    @Test func notChargingShowsNoText() {
        #expect(BatteryRow.chargeState(for: BatteryReading(level: 76, isCharging: false)) == nil)
        #expect(BatteryRow.chargeState(for: BatteryReading(level: 100, isCharging: false)) == nil)
    }

    @Test func chargingReadsChargingUntilFull() {
        #expect(BatteryRow.chargeState(for: BatteryReading(level: 99, isCharging: true)) == "Charging")
        #expect(BatteryRow.chargeState(for: BatteryReading(level: nil, isCharging: true)) == "Charging")
        #expect(BatteryRow.chargeState(for: BatteryReading(level: 100, isCharging: true)) == "Charged")
    }

    @Test func voiceOverAlwaysHearsTheChargingState() {
        #expect(row(BatteryReading(level: 76, isCharging: false)).accessibilityDescription
            == "Battery 76%, Not charging")
        #expect(row(BatteryReading(level: 64, isCharging: true)).accessibilityDescription
            == "Battery 64%, Charging")
        #expect(row(BatteryReading(level: 100, isCharging: true)).accessibilityDescription
            == "Battery 100%, Charged")
    }

    @Test func missingReadingsStillExplainThemselves() {
        #expect(row(nil).accessibilityDescription == "Battery, Unavailable")
        #expect(row(nil, needsPermission: true).accessibilityDescription == "Battery, Needs access")
    }
}
