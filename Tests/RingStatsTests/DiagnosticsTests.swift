import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

/// The diagnostics report is meant to be shared. These tests plant values that
/// must never leave the app and check that none of them appear.
struct DiagnosticsTests {
    @Test @MainActor func reportDescribesStateWithoutHealthValuesOrSecrets() async {
        let now = Date(timeIntervalSince1970: 50_000)
        let snapshot = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "8737", detail: "Optimal", score: 87),
                .heartRate: MetricReading(value: "4219", detail: "bpm", score: nil),
                .stress: OuraAPI.placeholder(for: .insufficientScope),
            ],
            battery: BatteryReading(level: 6613, isCharging: false),
            fetchedAt: now,
            coveredMetrics: [.readiness, .heartRate, .stress],
            failedMetrics: [.stress: .insufficientScope]
        )
        let model = AppViewModel(
            auth: AuthStub(configured: true, connected: true),
            api: SnapshotStub(results: [.success(snapshot)]),
            descriptor: OuraProvider.descriptor,
            now: { now },
            checkConnectionOnInit: false
        )
        await model.refreshNow(metrics: [.readiness, .heartRate, .stress])

        let log = DiagnosticsLog(clock: { now })
        log.record(.refreshFailed(.server("upstream body SECRET-BODY with Bearer abc.def")))
        log.record(.authorizationFailed(.callback("state=PLANTED-STATE")))
        log.record(.tokenRefreshFailed(.credentialStore("keychain said PLANTED-KEYCHAIN")))
        log.record(.endpointResponse(endpoint: OuraEndpoint(path: "/v2/usercollection/daily_readiness").diagnostic, status: 503))

        let report = DiagnosticsReport.make(model: model, log: log, now: now)

        for planted in ["8737", "4219", "6613", "SECRET-BODY", "Bearer", "PLANTED-STATE", "PLANTED-KEYCHAIN", "Optimal"] {
            #expect(!report.contains(planted), "report leaked \(planted)")
        }
        #expect(report.contains("Connection: connected"))
        #expect(report.contains("readiness: available"))
        #expect(report.contains("stress: needs access (insufficient-scope)"))
        #expect(report.contains("Refresh failed: server"))
        #expect(report.contains("daily_readiness: HTTP 503"))
    }

    @Test func logKeepsOnlyTheMostRecentEvents() {
        let log = DiagnosticsLog(capacity: 3)
        for status in 200..<205 {
            log.record(.endpointResponse(endpoint: OuraEndpoint.dailySleep.diagnostic, status: status))
        }
        #expect(log.entries.map(\.event) == [202, 203, 204].map {
            .endpointResponse(endpoint: OuraEndpoint.dailySleep.diagnostic, status: $0)
        })
    }

    @Test func endpointsAreIdentifiedWithoutQueryStrings() {
        #expect(OuraEndpoint(path: "/v2/usercollection/heartrate") == .heartRate)
        #expect(OuraEndpoint(path: "/oauth/revoke") == .revoke)
        #expect(OuraEndpoint(path: "/somewhere/else") == .other)
    }

    @Test func partialRefreshSummaryNamesMetricsAndErrorKindsOnly() {
        let event = DiagnosticEvent.refreshPartial(
            failed: [.sleep: .timedOut, .activity: .server("maintenance window 42")],
            batteryFailed: true
        )
        #expect(event.summary == "Refresh partial: activity=server, sleep=timed-out, battery")
        #expect(event.isFailure)
    }
}
