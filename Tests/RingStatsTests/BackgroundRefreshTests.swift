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
    private(set) var bedtimeLevels: [Int] = []
    private(set) var scoreAnnouncements = 0
    func requestAuthorization() async -> Bool { true }
    func notifyLowBattery(level: Int) async { levels.append(level) }
    func notifyChargeBeforeBed(projectedLevel: Int) async { bedtimeLevels.append(projectedLevel) }
    func notifyScoresArrived() async { scoreAnnouncements += 1 }
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

    /// A full charge between two half-hourly samples arrives as "100%, not
    /// charging"; it must still re-arm, or the alert would never fire again.
    @Test func recoveredLevelRearmsWithoutACharginSample() {
        var alert = LowBatteryAlert()
        #expect(alert.evaluate(BatteryReading(level: 19, isCharging: false), isStale: false) == 19)
        #expect(alert.evaluate(BatteryReading(level: 45, isCharging: false), isStale: false) == nil)
        #expect(!alert.isArmed)
        #expect(alert.evaluate(BatteryReading(level: 100, isCharging: false), isStale: false) == nil)
        #expect(alert.isArmed)
        #expect(alert.evaluate(BatteryReading(level: 17, isCharging: false), isStale: false) == 17)
    }

    @Test func thresholdIsTheUsersChoiceWithinTheOfferedLevels() {
        var low = LowBatteryAlert(threshold: 10)
        let above = low.evaluate(BatteryReading(level: 15, isCharging: false), isStale: false)
        let below = low.evaluate(BatteryReading(level: 9, isCharging: false), isStale: false)
        #expect(above == nil)
        #expect(below == 9)
        var high = LowBatteryAlert(threshold: 30)
        let nearThirty = high.evaluate(BatteryReading(level: 29, isCharging: false), isStale: false)
        #expect(nearThirty == 29)
        #expect(LowBatteryAlert(threshold: 42).threshold == 20)
    }

    @Test func quietHoursWrapMidnight() {
        let quiet = QuietHours(start: 22, end: 7)
        #expect(quiet.contains(hour: 22))
        #expect(quiet.contains(hour: 3))
        #expect(!quiet.contains(hour: 7))
        #expect(!quiet.contains(hour: 12))
        #expect(!QuietHours(start: 9, end: 9).contains(hour: 9))
        #expect(QuietHours(start: 9, end: 17).contains(hour: 12))
    }

    /// At 18:00 with a ring that lost 30% since 08:00, the projection for
    /// 07:00 is below the threshold, so the nudge fires once; a charge resets.
    @Test func bedtimeNudgeFiresOncePerEveningWhenTheRingWillNotLast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = try #require(ISO8601DateFormatter().date(from: "2026-10-19T08:00:00Z"))
        var nudge = BedtimeNudge()
        let quiet = QuietHours.default
        func eval(_ level: Int, hoursLater: Double, charging: Bool = false) -> Int? {
            nudge.evaluate(
                BatteryReading(level: level, isCharging: charging), isStale: false,
                now: morning.addingTimeInterval(hoursLater * 3_600), quietHours: quiet, threshold: 20, calendar: calendar
            )
        }
        let first = eval(60, hoursLater: 0)
        let midday = eval(45, hoursLater: 5)
        let projected = eval(30, hoursLater: 10)
        let again = eval(28, hoursLater: 10.5)
        let charging = eval(80, hoursLater: 11, charging: true)
        #expect(first == nil)
        #expect(midday == nil, "13:00 is outside the evening window")
        #expect(projected != nil && projected! < 20, "\(String(describing: projected))")
        #expect(again == nil, "once per day")
        #expect(charging == nil)
        #expect(nudge.samples.isEmpty, "a charge resets the drain history")
    }

    @Test func bedtimeNudgeStaysQuietWhenTheRingWillLast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = try #require(ISO8601DateFormatter().date(from: "2026-10-19T08:00:00Z"))
        var nudge = BedtimeNudge()
        _ = nudge.evaluate(BatteryReading(level: 90, isCharging: false), isStale: false, now: morning, quietHours: .default, threshold: 20, calendar: calendar)
        let evening = morning.addingTimeInterval(10 * 3_600)
        let result = nudge.evaluate(BatteryReading(level: 85, isCharging: false), isStale: false, now: evening, quietHours: .default, threshold: 20, calendar: calendar)
        #expect(result == nil)
    }

    /// Scores arriving after a morning of "Not published" announce once;
    /// launching with them present, or a later score, says nothing.
    @Test func scoresArrivalAnnouncesTheFirstScoresOfTheDayOnce() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-19T07:30:00Z"))
        let today = QueryDates.dayString(for: now, calendar: calendar)
        let empty = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "—", detail: "Not published", score: nil, availability: .noData)],
            battery: nil, fetchedAt: now
        )
        let arrived = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "84", detail: "Good", score: 84, sourceDay: today)],
            battery: nil, fetchedAt: now
        )
        var fresh = ScoresArrival()
        let atLaunch = fresh.evaluate(arrived, now: now, calendar: calendar)
        #expect(!atLaunch, "already there at launch")
        var tracker = ScoresArrival()
        let whileMissing = tracker.evaluate(empty, now: now, calendar: calendar)
        let whenArrived = tracker.evaluate(arrived, now: now.addingTimeInterval(1_800), calendar: calendar)
        let later = tracker.evaluate(arrived, now: now.addingTimeInterval(3_600), calendar: calendar)
        #expect(!whileMissing)
        #expect(whenArrived)
        #expect(!later, "once per day")
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

    /// A refresh that failed still counts as an attempt, so a Mac on battery
    /// without network waits the two hours instead of retrying every wake.
    @Test func onBatteryPowerAFailedAttemptAlsoWaits() async {
        let (model, api) = model(results: [.failure(.timedOut), .failure(.timedOut)])
        await model.refreshNow(metrics: [.readiness])
        #expect(model.lastRefreshAttemptAt == now)
        let refresher = BackgroundRefresher(
            model: model,
            power: FixedPower(isConstrained: true),
            metrics: { [.readiness] },
            now: { [now] in now.addingTimeInterval(30 * 60) }
        )

        #expect(!(await refresher.runOnce()))
        #expect(await api.callCount == 1)
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
        let watcher = LowBatteryWatcher(model: model, notifier: spy, settings: { BatteryNotificationSettings(lowBattery: true) })

        await model.refreshNow(metrics: [.readiness])
        await model.refreshNow(metrics: [.readiness])

        #expect(watcher.announcedLevels == [15])
        await waitUntil { await spy.levels == [15] }
    }

    @Test func nothingIsAnnouncedWhenDisabled() async {
        let (model, _) = model(results: [.success(snapshot(battery: BatteryReading(level: 9, isCharging: false)))])
        let watcher = LowBatteryWatcher(model: model, notifier: NotifierSpy(), settings: { BatteryNotificationSettings() })

        await model.refreshNow(metrics: [.readiness])

        #expect(watcher.announcedLevels.isEmpty)
    }

    /// A low battery seen during quiet hours is announced by the next
    /// snapshot outside them, not swallowed.
    @Test func quietHoursHoldTheLowBatteryAlertUntilTheyEnd() async throws {
        let (model, _) = model(results: [
            .success(snapshot(battery: BatteryReading(level: 15, isCharging: false))),
            .success(snapshot(battery: BatteryReading(level: 14, isCharging: false))),
        ])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let night = try #require(ISO8601DateFormatter().date(from: "2026-10-19T23:00:00Z"))
        let morning = try #require(ISO8601DateFormatter().date(from: "2026-10-20T08:00:00Z"))
        var clock = night
        let quiet = QuietHours(start: 22, end: 7)
        let spy = NotifierSpy()
        let watcher = LowBatteryWatcher(
            model: model, notifier: spy,
            settings: { BatteryNotificationSettings(lowBattery: true, quietHours: quiet) },
            now: { clock }
        )
        _ = calendar
        await model.refreshNow(metrics: [.readiness])
        #expect(watcher.announcedLevels.isEmpty)
        clock = morning
        await model.refreshNow(metrics: [.readiness])
        #expect(watcher.announcedLevels == [14])
    }

    @Test func scoresArrivalIsAnnouncedOnceWhenEnabled() async throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-19T07:30:00Z"))
        let today = QueryDates.dayString(for: now)
        let empty = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "—", detail: "Not published", score: nil, availability: .noData)],
            battery: nil, fetchedAt: now, coveredMetrics: [.readiness]
        )
        let arrived = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "84", detail: "Good", score: 84, sourceDay: today)],
            battery: nil, fetchedAt: now.addingTimeInterval(1_800), coveredMetrics: [.readiness]
        )
        let (model, _) = model(results: [.success(empty), .success(arrived), .success(arrived)])
        let spy = NotifierSpy()
        let watcher = ScoresArrivedWatcher(model: model, notifier: spy, isEnabled: { true }, now: { now.addingTimeInterval(3_600) })
        await model.refreshNow(metrics: [.readiness])
        await model.refreshNow(metrics: [.readiness])
        await model.refreshNow(metrics: [.readiness])
        #expect(watcher.announcements == 1)
        await waitUntil { await spy.scoreAnnouncements == 1 }
    }
}
