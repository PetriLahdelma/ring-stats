import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

/// The optional value beside the menu-bar icon.
struct MenuBarValueTests {
    private let now = Date(timeIntervalSince1970: 30_000)

    private func snapshot(battery: BatteryReading?, batteryIsStale: Bool = false) -> HealthSnapshot {
        HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "84", detail: "Good", score: 84),
                .heartRate: MetricReading(value: "58", detail: "bpm", score: nil, observedAt: now),
                .sleep: MetricReading(value: "78", detail: "Good", score: 78).markedStale(fetchedAt: now),
                .stress: OuraAPI.placeholder(for: nil),
            ],
            battery: battery,
            fetchedAt: now,
            batteryIsStale: batteryIsStale
        )
    }

    @Test func offByDefaultAndUnknownValuesFallBackToNothing() {
        #expect(MenuBarValuePreference.resolve(nil) == .nothing)
        #expect(MenuBarValuePreference.resolve("bogus") == .nothing)
        #expect(MenuBarValuePreference.nothing.text(for: snapshot(battery: nil)) == nil)
    }

    @Test func showsTheChosenStatAndKeepsAStaleOne() {
        let snapshot = snapshot(battery: nil)
        #expect(MenuBarValuePreference.readiness.text(for: snapshot) == "84")
        #expect(MenuBarValuePreference.heartRate.text(for: snapshot) == "58")
        #expect(MenuBarValuePreference.sleep.text(for: snapshot) == "78")
        // A placeholder has no value to show.
        #expect(MenuBarValuePreference.stress.text(for: snapshot) == nil)
        #expect(MenuBarValuePreference.activity.text(for: snapshot) == nil)
        #expect(MenuBarValuePreference.readiness.accessibilityLabel(for: snapshot) == "Ring Stats, Readiness 84")
    }

    @Test func batteryShowsOnlyWhenLowAndCurrent() {
        #expect(MenuBarValuePreference.batteryWhenLow.text(for: snapshot(battery: BatteryReading(level: 76, isCharging: false))) == nil)
        #expect(MenuBarValuePreference.batteryWhenLow.text(for: snapshot(battery: BatteryReading(level: 15, isCharging: false))) == "15%")
        #expect(MenuBarValuePreference.batteryWhenLow.text(for: snapshot(battery: BatteryReading(level: 15, isCharging: false), batteryIsStale: true)) == nil)
        #expect(MenuBarValuePreference.batteryWhenLow.accessibilityLabel(for: snapshot(battery: BatteryReading(level: 15, isCharging: false))) == "Ring Stats, battery low, 15%")
        #expect(MenuBarValuePreference.nothing.accessibilityLabel(for: snapshot(battery: nil)) == "Ring Stats")
    }

    @Test func everyChoiceHasATitle() {
        for choice in MenuBarValuePreference.allCases {
            #expect(!choice.title.isEmpty && choice.title != choice.rawValue, "\(choice)")
        }
    }
}
