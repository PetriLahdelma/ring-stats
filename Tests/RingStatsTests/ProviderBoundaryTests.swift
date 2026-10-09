import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

/// The HealthProvider boundary: what a provider declares and how the app uses it.
struct ProviderBoundaryTests {
    private static let heartRateOnly = ProviderDescriptor(
        id: ProviderID(rawValue: "test"),
        displayName: "Test",
        capabilities: ProviderCapabilities(
            supportedMetrics: [.heartRate],
            reportsBattery: false,
            hasSandbox: false
        ),
        metricScopes: [.heartRate: AuthorizationScope("heart")],
        baseScopes: []
    )

    /// The app reaches the Oura module only where it chooses the provider.
    /// Any other import would let a view depend on Oura types silently.
    @Test func onlyTheCompositionRootImportsTheOuraModule() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RingStats")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        let importers = try files.filter { try String(contentsOf: $0, encoding: .utf8).contains("import RingStatsOura") }
        #expect(importers.map(\.lastPathComponent) == ["ProviderRegistry.swift"])
    }

    /// Core names no provider; the app passes the name in.
    @Test func coreCarriesNoProviderName() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RingStatsCore")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        // Comments may mention Oura's history and conventions; code and
        // strings may not.
        let offenders = try files.filter { file in
            try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .contains { $0.contains("Oura") }
        }
        #expect(offenders.isEmpty, "\(offenders.map(\.lastPathComponent))")

        #expect(RingStatsError.timedOut.message(provider: "Ultrahuman")
            == "The Ultrahuman request timed out. Check your connection and try again.")
        #expect(RingStatsError.notConnected.message(provider: "Oura") == "Connect your Oura account first.")
        #expect(RingStatsError.timedOut.errorDescription?.contains("Oura") == false)
        #expect(ShortcutFailure.notConnected.message(provider: "Ultrahuman")
            == "Ring Stats is not connected to Ultrahuman. Open Ring Stats to connect.")
        #expect(OuraProvider.descriptor.developerPortal?.host == "developer.ouraring.com")
    }

    @Test func ouraDescriptorRequestsTheSameScopesAsBefore() {
        let all = Metric.allCases
        for mask in 0..<(1 << all.count) {
            let metrics = Set(all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] })
            let expected = Set(OuraScope.required(for: metrics).map(\.rawValue))
            #expect(Set(OuraProvider.descriptor.scopes(for: metrics).map(\.rawValue)) == expected)
        }
    }

    @Test func ouraSupportsEveryMetricAndTheBattery() {
        let capabilities = OuraProvider.descriptor.capabilities
        #expect(capabilities.supportedMetrics == Set(Metric.allCases))
        #expect(capabilities.reportsBattery)
        #expect(capabilities.hasSandbox)
    }

    @Test func ouraDiagnosticNamesMatchTheirEndpoints() {
        for endpoint in OuraEndpoint.allCases where endpoint != .other {
            #expect(endpoint.diagnostic.name == endpoint.rawValue)
        }
        for scope in OuraScope.allCases {
            #expect(scope.authorizationScope.rawValue == scope.rawValue)
        }
    }

    @Test func ouraBatteryMapsChargingFromEitherFlag() {
        let docked = BatteryRecord(level: 40, charging: false, inCharger: true, timestamp: nil)
        let charging = BatteryRecord(level: 40, charging: true, inCharger: nil, timestamp: nil)
        let idle = BatteryRecord(level: nil, charging: nil, inCharger: nil, timestamp: nil)
        #expect(docked.reading == BatteryReading(level: 40, isCharging: true))
        #expect(charging.reading == BatteryReading(level: 40, isCharging: true))
        #expect(idle.reading == BatteryReading(level: nil, isCharging: false))
    }

    @Test func unsupportedMetricsAddNoScopes() {
        #expect(Self.heartRateOnly.scopes(for: [.readiness, .heartRate]).map(\.rawValue) == ["heart"])
        #expect(Self.heartRateOnly.supported([.readiness, .heartRate]) == [.heartRate])
    }

    @Test @MainActor func refreshRequestsOnlyMetricsTheProviderSupports() async {
        let now = Date(timeIntervalSince1970: 20_000)
        let snapshot = HealthSnapshot(
            readings: [.heartRate: MetricReading(value: "58", detail: "bpm", score: nil)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(snapshot)])
        let model = AppViewModel(
            auth: AuthStub(configured: true, connected: true),
            api: api,
            descriptor: Self.heartRateOnly,
            now: { now },
            checkConnectionOnInit: false
        )

        await model.refreshNow(metrics: [.readiness, .heartRate, .stress])

        #expect(await api.requestedMetrics == [[.heartRate]])
    }

    @Test @MainActor func authorizationRequestsTheProviderScopes() async {
        let probe = AuthorizationProbe(holds: false)
        let model = AppViewModel(
            auth: AuthStub(configured: true, connected: true),
            api: SnapshotStub(results: [.failure(.timedOut)]),
            descriptor: Self.heartRateOnly,
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        await model.reauthorize(metrics: [.readiness, .heartRate])

        #expect(await probe.recordedScopes == [[AuthorizationScope("heart")]])
    }
}
