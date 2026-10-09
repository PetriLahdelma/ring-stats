import Foundation
import OSLog

/// Something worth recording to explain a failure later. Payloads are limited
/// to values that are safe to share by construction: metric and endpoint
/// names, HTTP status codes, and error kinds. There is deliberately no case
/// that accepts free text, so health values, tokens, credentials, and server
/// response bodies cannot reach the log or a diagnostics report.
package enum DiagnosticEvent: Sendable, Equatable {
    case refreshStarted(metrics: Set<Metric>, forced: Bool)
    case refreshSucceeded(metrics: Set<Metric>)
    case refreshPartial(failed: [Metric: RingStatsError], batteryFailed: Bool)
    case refreshFailed(RingStatsError)
    case authorizationStarted(scopes: Set<AuthorizationScope>)
    case authorizationSucceeded
    case authorizationCancelled
    case authorizationFailed(RingStatsError)
    case endpointResponse(endpoint: DiagnosticEndpoint, status: Int)
    case endpointUnreachable(endpoint: DiagnosticEndpoint, error: RingStatsError)
    case tokenRefreshed
    /// A fresh token is in use but could not be written to the Keychain.
    case tokenPersistFailed
    case tokenRefreshFailed(RingStatsError)
    case callbackRejected
    case callbackAccepted
    case disconnected
    case backgroundRefreshSkipped(BackgroundRefreshSkip)
    case lowBatteryNotified

    package var category: DiagnosticCategory {
        switch self {
        case .refreshStarted, .refreshSucceeded, .refreshPartial, .refreshFailed: .refresh
        case .authorizationStarted, .authorizationSucceeded, .authorizationCancelled,
             .authorizationFailed, .tokenRefreshed, .tokenRefreshFailed, .tokenPersistFailed, .disconnected: .authorization
        case .endpointResponse, .endpointUnreachable: .network
        case .callbackRejected, .callbackAccepted: .callback
        case .backgroundRefreshSkipped: .refresh
        case .lowBatteryNotified: .notification
        }
    }

    package var isFailure: Bool {
        switch self {
        case .refreshPartial, .refreshFailed, .authorizationFailed, .endpointUnreachable,
             .tokenRefreshFailed, .callbackRejected:
            true
        case .endpointResponse(_, let status):
            !(200..<300).contains(status)
        default:
            false
        }
    }

    package var summary: String {
        switch self {
        case .refreshStarted(let metrics, let forced):
            "Refresh started (\(forced ? "manual" : "on open")): \(Self.names(metrics))"
        case .refreshSucceeded(let metrics):
            "Refresh succeeded: \(Self.names(metrics))"
        case .refreshPartial(let failed, let batteryFailed):
            "Refresh partial: "
                + failed.sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\($0.key.rawValue)=\($0.value.diagnosticKind)" }
                    .joined(separator: ", ")
                + (batteryFailed ? (failed.isEmpty ? "battery" : ", battery") : "")
        case .refreshFailed(let error):
            "Refresh failed: \(error.diagnosticKind)"
        case .authorizationStarted(let scopes):
            "Authorization started: \(scopes.map(\.rawValue).sorted().joined(separator: " "))"
        case .authorizationSucceeded:
            "Authorization succeeded"
        case .authorizationCancelled:
            "Authorization cancelled"
        case .authorizationFailed(let error):
            "Authorization failed: \(error.diagnosticKind)"
        case .endpointResponse(let endpoint, let status):
            "\(endpoint.name): HTTP \(status)"
        case .endpointUnreachable(let endpoint, let error):
            "\(endpoint.name): \(error.diagnosticKind)"
        case .tokenRefreshed:
            "Access token refreshed"
        case .tokenPersistFailed:
            "Fresh access token kept in memory; Keychain write failed"
        case .tokenRefreshFailed(let error):
            "Access token refresh failed: \(error.diagnosticKind)"
        case .callbackRejected:
            "Rejected an invalid loopback callback request"
        case .callbackAccepted:
            "Accepted the OAuth callback"
        case .backgroundRefreshSkipped(let reason):
            "Background refresh skipped: \(reason.rawValue)"
        case .lowBatteryNotified:
            "Low ring battery notification sent"
        case .disconnected:
            "Disconnected and deleted local authorization"
        }
    }

    private static func names(_ metrics: Set<Metric>) -> String {
        metrics.map(\.rawValue).sorted().joined(separator: ", ")
    }
}

package enum DiagnosticCategory: String, Sendable {
    case refresh
    case authorization
    case network
    case callback
    case notification
}

/// Why a scheduled background refresh did not fetch.
package enum BackgroundRefreshSkip: String, Sendable {
    case notConnected = "not connected"
    case constrainedPower = "on battery power or in Low Power Mode"
}

/// The name of a provider endpoint. It is created only from a string literal,
/// so query strings, which can hold tokens, cannot reach diagnostics.
package struct DiagnosticEndpoint: Hashable, Sendable {
    package let name: String

    package init(_ literal: StaticString) {
        self.name = "\(literal)"
    }
}

extension RingStatsError {
    /// A stable identifier with no associated text. Messages from upstream
    /// services are dropped because they can echo request data.
    package var diagnosticKind: String {
        switch self {
        case .notConfigured: "not-configured"
        case .notConnected: "not-connected"
        case .invalidResponse: "invalid-response"
        case .authenticationRequired: "authentication-required"
        case .invalidClientCredentials: "invalid-client-credentials"
        case .authorizationRestartRequired: "authorization-restart-required"
        case .invalidRequestedScope: "invalid-requested-scope"
        case .insufficientScope: "insufficient-scope"
        case .rateLimited: "rate-limited"
        case .timedOut: "timed-out"
        case .malformedData: "malformed-data"
        case .credentialStore: "credential-store"
        case .transport: "transport"
        case .server: "server"
        case .callback: "callback"
        }
    }
}

/// Records diagnostic events to the unified log and keeps the most recent ones
/// in memory for a user-reviewed report. Nothing is written to disk by the app
/// and nothing is sent anywhere.
package final class DiagnosticsLog: @unchecked Sendable {
    package static let shared = DiagnosticsLog()
    package static let subsystem = "com.digitaltableteur.ringstats"

    package struct Entry: Sendable, Equatable {
        package let date: Date
        package let event: DiagnosticEvent
    }

    private let capacity: Int
    private let lock = NSLock()
    private var buffer: [Entry] = []
    private let clock: @Sendable () -> Date

    package init(capacity: Int = 200, clock: @escaping @Sendable () -> Date = Date.init) {
        self.capacity = capacity
        self.clock = clock
    }

    package var entries: [Entry] { lock.withLock { buffer } }

    package func record(_ event: DiagnosticEvent) {
        let entry = Entry(date: clock(), event: event)
        lock.withLock {
            buffer.append(entry)
            if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        }
        let logger = Logger(subsystem: Self.subsystem, category: event.category.rawValue)
        let summary = event.summary
        if event.isFailure {
            logger.error("\(summary, privacy: .public)")
        } else {
            logger.info("\(summary, privacy: .public)")
        }
    }

    package func clear() {
        lock.withLock { buffer.removeAll() }
    }
}
