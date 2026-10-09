import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

/// What the Shortcuts actions answer, and what they fetch to answer it.
@MainActor
struct ShortcutAnswersTests {
    private let now = Date(timeIntervalSince1970: 30_000)

    private func model(
        connected: Bool = true,
        results: [Result<HealthSnapshot, RingStatsError>]
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

    private func snapshot(
        _ readings: [Metric: MetricReading],
        battery: BatteryReading? = nil,
        batteryFailure: RingStatsError? = nil
    ) -> HealthSnapshot {
        HealthSnapshot(
            readings: readings,
            battery: battery,
            fetchedAt: now,
            batteryFailure: batteryFailure
        )
    }

    @Test func scoreAnswersWithValueAndBand() async throws {
        let (model, api) = model(results: [.success(snapshot([
            .readiness: MetricReading(value: "84", detail: "Good", score: 84),
            .sleep: MetricReading(value: "78", detail: "Good", score: 78),
        ]))])

        let answer = try await ShortcutAnswers.reading(for: .readiness, model: model, visible: [.readiness, .sleep])

        #expect(answer == ShortcutAnswer(value: "84", dialog: "Readiness 84, Good."))
        #expect(await api.requestedMetrics == [[.readiness, .sleep]])
    }

    @Test func hiddenStatIsFetchedWithTheVisibleOnes() async throws {
        let (model, api) = model(results: [.success(snapshot([
            .readiness: MetricReading(value: "84", detail: "Good", score: 84),
            .heartRate: MetricReading(value: "58", detail: "bpm", score: nil),
        ]))])

        let answer = try await ShortcutAnswers.reading(for: .heartRate, model: model, visible: [.readiness])

        #expect(answer.dialog == "Heart rate 58 bpm.")
        #expect(await api.requestedMetrics == [[.readiness, .heartRate]])
    }

    @Test func freshSnapshotIsReusedWithoutFetching() async throws {
        let first = snapshot([.readiness: MetricReading(value: "84", detail: "Good", score: 84)])
        let (model, api) = model(results: [.success(first)])
        await model.refreshNow(metrics: [.readiness])

        _ = try await ShortcutAnswers.reading(for: .readiness, model: model, visible: [.readiness])

        #expect(await api.callCount == 1)
    }

    @Test func missingPermissionAndNoDataExplainThemselves() async {
        let (model, _) = model(results: [.success(snapshot([
            .stress: OuraAPI.placeholder(for: .insufficientScope),
            .sleep: OuraAPI.placeholder(for: nil),
        ]))])

        await #expect(throws: ShortcutFailure.needsAccess(.stress)) {
            try await ShortcutAnswers.reading(for: .stress, model: model, visible: [.stress, .sleep])
        }
        await #expect(throws: ShortcutFailure.noData(.sleep)) {
            try await ShortcutAnswers.reading(for: .sleep, model: model, visible: [.stress, .sleep])
        }
    }

    @Test func disconnectedAppDoesNotFetch() async {
        let (model, api) = model(connected: false, results: [])

        await #expect(throws: ShortcutFailure.notConnected) {
            try await ShortcutAnswers.reading(for: .readiness, model: model, visible: [.readiness])
        }
        #expect(await api.callCount == 0)
    }

    @Test func expiredAuthorizationAsksToReauthorize() async {
        let (model, _) = model(results: [.failure(.authenticationRequired)])

        await #expect(throws: ShortcutFailure.authorizationExpired) {
            try await ShortcutAnswers.reading(for: .readiness, model: model, visible: [.readiness])
        }
    }

    @Test func batteryAnswersWithLevelAndChargingState() async throws {
        let (model, _) = model(results: [.success(snapshot(
            [.readiness: MetricReading(value: "84", detail: "Good", score: 84)],
            battery: BatteryReading(level: 64, isCharging: true)
        ))])

        let answer = try await ShortcutAnswers.battery(model: model, visible: [.readiness])

        #expect(answer == ShortcutAnswer(value: 64, dialog: "Ring battery 64%, charging."))
    }

    @Test func batteryWithoutPermissionSaysSo() async {
        let (model, _) = model(results: [.success(snapshot(
            [.readiness: MetricReading(value: "84", detail: "Good", score: 84)],
            batteryFailure: .insufficientScope
        ))])

        await #expect(throws: ShortcutFailure.needsBatteryAccess) {
            try await ShortcutAnswers.battery(model: model, visible: [.readiness])
        }
    }

    @Test func failureMessagesCarryNoValues() {
        let failures: [ShortcutFailure] = [
            .notConnected, .authorizationExpired, .needsAccess(.stress), .needsBatteryAccess,
            .noData(.sleep), .unavailable(.readiness), .batteryUnavailable,
        ]
        for failure in failures {
            let hasDigit = failure.message(provider: "Oura").contains { $0.isNumber }
            #expect(!hasDigit, "\(failure)")
        }
    }

    @Test func everyRingStatMapsToItsMetric() {
        #expect(RingStat.allCases.map(\.metric) == Metric.allCases)
        #expect(RingStat.allCases.map(\.rawValue) == Metric.allCases.map(\.rawValue))
    }
}
