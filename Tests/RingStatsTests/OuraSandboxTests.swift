import Foundation
import Testing
@testable import RingStatsCore
@testable import RingStatsOura

/// The real Oura client against Oura's public sandbox, which serves fixed test
/// data for any bearer token. It needs the network, so it runs only when
/// RING_STATS_LIVE_SANDBOX=1; the regular suite stays offline.
struct OuraSandboxTests {
    static let sandboxURL = URL(string: "https://api.ouraring.com/v2/sandbox/usercollection/")!

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RING_STATS_LIVE_SANDBOX"] == "1"))
    func everyMetricAndTheBatteryDecodeFromTheSandbox() async throws {
        let api = OuraAPI(auth: AccessTokenStub(tokens: ["sandbox"]), baseURL: Self.sandboxURL)

        let snapshot = try await api.fetchSnapshot(metrics: Set(Metric.allCases))

        #expect(snapshot.failedMetrics.isEmpty, "\(snapshot.failedMetrics)")
        #expect(snapshot.batteryFailure == nil)
        for metric in Metric.allCases {
            let reading = try #require(snapshot.readings[metric], "\(metric)")
            #expect(reading.availability == .available, "\(metric): \(reading.detail)")
        }
        let battery = try #require(snapshot.battery)
        #expect(battery.level.map { (0...100).contains($0) } == true)
    }
}
