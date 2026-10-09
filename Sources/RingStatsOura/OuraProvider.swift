import Foundation
import RingStatsCore

/// Oura, through its documented v2 user API and OAuth.
package struct OuraProvider: HealthProvider {
    package static let descriptor = ProviderDescriptor(
        id: ProviderID(rawValue: "oura"),
        displayName: "Oura",
        capabilities: ProviderCapabilities(
            supportedMetrics: Set(Metric.allCases),
            reportsBattery: true,
            // Verified by OuraSandboxTests against /v2/sandbox/usercollection/.
            hasSandbox: true
        ),
        metricScopes: Dictionary(uniqueKeysWithValues: Metric.allCases.map {
            ($0, $0.requiredScope.authorizationScope)
        }),
        baseScopes: [OuraScope.ringConfiguration.authorizationScope],
        developerPortal: URL(string: "https://developer.ouraring.com/applications")
    )

    package let account: any OAuthServicing
    package let snapshots: any SnapshotFetching

    package var descriptor: ProviderDescriptor { Self.descriptor }

    package init(account: OAuthClient = OAuthClient()) {
        self.account = account
        self.snapshots = OuraAPI(auth: account)
    }
}

package enum OuraScope: String, CaseIterable, Sendable {
    case daily
    case heartRate = "heartrate"
    case stress
    case ringConfiguration = "ring_configuration"

    package static func required(for metrics: Set<Metric>) -> Set<OuraScope> {
        Set(metrics.map(\.requiredScope)).union([.ringConfiguration])
    }

    package var authorizationScope: AuthorizationScope {
        switch self {
        case .daily: AuthorizationScope("daily")
        case .heartRate: AuthorizationScope("heartrate")
        case .stress: AuthorizationScope("stress")
        case .ringConfiguration: AuthorizationScope("ring_configuration")
        }
    }
}

extension Metric {
    package var dailyScoreEndpoint: String? {
        switch self {
        case .readiness: "daily_readiness"
        case .sleep: "daily_sleep"
        case .activity: "daily_activity"
        case .heartRate, .stress, .resilience: nil
        }
    }

    package var requiredScope: OuraScope {
        switch self {
        case .readiness, .sleep, .activity, .resilience: .daily
        case .heartRate: .heartRate
        case .stress: .stress
        }
    }
}

/// The Oura endpoints the app calls. Logging a case instead of a URL keeps
/// query strings, which can hold tokens, out of diagnostics.
package enum OuraEndpoint: String, Sendable, CaseIterable {
    case dailyReadiness = "daily_readiness"
    case dailySleep = "daily_sleep"
    case dailyActivity = "daily_activity"
    case heartRate = "heartrate"
    case dailyStress = "daily_stress"
    case dailyResilience = "daily_resilience"
    case ringBatteryLevel = "ring_battery_level"
    case token = "oauth/token"
    case revoke = "oauth/revoke"
    case other

    package init(path: String) {
        self = Self.allCases.first { $0 != .other && path.hasSuffix($0.rawValue) } ?? .other
    }

    package var diagnostic: DiagnosticEndpoint {
        switch self {
        case .dailyReadiness: DiagnosticEndpoint("daily_readiness")
        case .dailySleep: DiagnosticEndpoint("daily_sleep")
        case .dailyActivity: DiagnosticEndpoint("daily_activity")
        case .heartRate: DiagnosticEndpoint("heartrate")
        case .dailyStress: DiagnosticEndpoint("daily_stress")
        case .dailyResilience: DiagnosticEndpoint("daily_resilience")
        case .ringBatteryLevel: DiagnosticEndpoint("ring_battery_level")
        case .token: DiagnosticEndpoint("oauth/token")
        case .revoke: DiagnosticEndpoint("oauth/revoke")
        case .other: DiagnosticEndpoint("other")
        }
    }
}
