import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

private struct FixedPower: PowerStateProviding {
    let isConstrained: Bool
}

private actor NotifierSpy: LowBatteryNotifying {
    private(set) var levels: [Int] = []
    func requestAuthorization() async -> Bool { true }
    func notifyLowBattery(level: Int) async { levels.append(level) }
}

/// Background refresh timing and the low ring battery notification.
@MainActor
struct BackgroundRefreshTests {
    private let now = Date(timeIntervalSince1970: 50_000)

    // MARK: Policies

    @Test func refreshesWhenPluggedInOrWithoutData() {
        let recent = now.addingTimeInterval(-60)
        #expect(BackgroundRefreshPolicy.shouldRefresh(lastFetchedAt: recent, now: now, constrained: false))
        #expect(BackgroundRefreshPolicy.shouldRefresh(lastFetchedAt: nil, now: now, constrained: true))
    }

    @Test func onBatteryWaitsAboutTwoHours() {
        let hourAgo = now.addingTimeInterval(-3_600)
        let twoHoursAgo = now.addingTimeInterval(-2 * 3_600)
        #expect(!BackgroundRefreshPolicy.shouldRefresh(lastFetchedAt: hourAgo, now: now, constrained: true))
        #expect(BackgroundRefreshPolicy.shouldRefresh(lastFetchedAt: twoHoursAgo, now: now, constrained: true))
    }

    @Test func alertsOncePerDrainAndRearmsAfterCharging() {
        var alert = LowBatteryAlert()
        #expect(alert.evaluate(BatteryReading(level: 40, isCharging: false), isStale: false) == nil)
        #expect(alert.evaluate(BatteryReading(level: 19, isCharging: false), isStale: false) == 19)
        #expect(alert.evaluate(BatteryReading(level: 12, isCharging: false), isStale: false) == nil)
        #expect(alert.evaluate(BatteryReading(level: 14, isCharging: true), isStale: false) == nil)
        #expect(alert.evaluate(BatteryReading(level: 18, isCharging: false), isStale: false) == 18)
    }

    @Test func staleOrUnknownBatteryNeverAlerts() {
        var alert = LowBatteryAlert()
        #expect(alert.evaluate(BatteryReading(level: 5, isCharging: false), isStale: true) == nil)
        #expect(alert.evaluate(BatteryReading(level: nil, isCharging: false), isStale: false) == nil)
        #expect(alert.evaluate(nil, isStale: false) == nil)
        #expect(alert.isArmed)
    }

    @Test func diagnosticsCarryNoBatteryLevel() {
        let summary = DiagnosticEvent.lowBatteryNotified.summary
        let hasDigit = summary.contains { $0.isNumber }
        #expect(!hasDigit)
        #expect(DiagnosticEvent.backgroundRefreshSkipped(.constrainedPower).summary
            == "Background refresh skipped: on battery power or in Low Power Mode")
    }

    // MARK: Refresher

    private func model(
        connected: Bool = true,
        results: [Result<HealthSnapshot, RingStatsError>] = []
    ) -> (AppViewModel, SnapshotStub) {
        let api = SnapshotStub(results: results)
        let now = now
        let model = AppViewModel(
            auth: AuthStub(configured: connected, connected: connected),
            api: api,
            descriptor: OuraProvider.descriptor,
            now: { now },
            checkConnectionOnInit: false
        )
        return (model, api)
    }

    private func snapshot(battery: BatteryReading?, at date: Date? = nil) -> HealthSnapshot {
        HealthSnapshot(
            readings: [.readiness: MetricReading(value: "70", detail: "Good", score: 70)],
            battery: battery,
            fetchedAt: date ?? now
        )
    }

    @Test func refreshesTheVisibleStats() async {
        let (model, api) = model(results: [.success(snapshot(battery: nil))])
        let refresher = BackgroundRefresher(
            model: model,
            power: FixedPower(isConstrained: false),
            metrics: { [.readiness, .sleep] },
            now: { [now] in now }
        )

        #expect(await refresher.runOnce())
        #expect(await api.requestedMetrics == [[.readiness, .sleep]])
    }

    @Test func skipsWhenNotConnected() async {
        let (model, api) = model(connected: false)
        let refresher = BackgroundRefresher(model: model, power: FixedPower(isConstrained: false), metrics: { [.readiness] })

        #expect(!(await refresher.runOnce()))
        #expect(await api.callCount == 0)
    }

    @Test func onBatteryPowerRecentDataIsNotRefetched() async {
        let earlier = now.addingTimeInterval(-30 * 60)
        let (model, api) = model(results: [.success(snapshot(battery: nil, at: earlier))])
        await model.refreshNow(metrics: [.readiness])
        let refresher = BackgroundRefresher(
            model: model,
            power: FixedPower(isConstrained: true),
            metrics: { [.readiness] },
            now: { [now] in now }
        )

        #expect(!(await refresher.runOnce()))
        #expect(await api.callCount == 1)
    }

    // MARK: Watcher

    @Test func lowBatteryIsAnnouncedOnceWhenEnabled() async {
        let (model, _) = model(results: [
            .success(snapshot(battery: BatteryReading(level: 15, isCharging: false))),
            .success(snapshot(battery: BatteryReading(level: 12, isCharging: false))),
        ])
        let spy = NotifierSpy()
        let watcher = LowBatteryWatcher(model: model, notifier: spy, isEnabled: { true })

        await model.refreshNow(metrics: [.readiness])
        await model.refreshNow(metrics: [.readiness])

        #expect(watcher.announcedLevels == [15])
        await waitUntil { await spy.levels == [15] }
    }

    @Test func nothingIsAnnouncedWhenDisabled() async {
        let (model, _) = model(results: [.success(snapshot(battery: BatteryReading(level: 9, isCharging: false)))])
        let watcher = LowBatteryWatcher(model: model, notifier: NotifierSpy(), isEnabled: { false })

        await model.refreshNow(metrics: [.readiness])

        #expect(watcher.announcedLevels.isEmpty)
    }
}
