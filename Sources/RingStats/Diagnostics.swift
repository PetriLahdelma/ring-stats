import Foundation
import OSLog

/// Something worth recording to explain a failure later. Payloads are limited
/// to values that are safe to share by construction: metric and endpoint
/// names, HTTP status codes, and error kinds. There is deliberately no case
/// that accepts free text, so health values, tokens, credentials, and server
/// response bodies cannot reach the log or a diagnostics report.
enum DiagnosticEvent: Sendable, Equatable {
    case refreshStarted(metrics: Set<Metric>, forced: Bool)
    case refreshSucceeded(metrics: Set<Metric>)
    case refreshPartial(failed: [Metric: RingStatsError], batteryFailed: Bool)
    case refreshFailed(RingStatsError)
    case authorizationStarted(scopes: Set<OuraScope>)
    case authorizationSucceeded
    case authorizationCancelled
    case authorizationFailed(RingStatsError)
    case endpointResponse(endpoint: OuraEndpoint, status: Int)
    case endpointUnreachable(endpoint: OuraEndpoint, error: RingStatsError)
    case tokenRefreshed
    case tokenRefreshFailed(RingStatsError)
    case callbackRejected
    case callbackAccepted
    case disconnected

    var category: DiagnosticCategory {
        switch self {
        case .refreshStarted, .refreshSucceeded, .refreshPartial, .refreshFailed: .refresh
        case .authorizationStarted, .authorizationSucceeded, .authorizationCancelled,
             .authorizationFailed, .tokenRefreshed, .tokenRefreshFailed, .disconnected: .authorization
        case .endpointResponse, .endpointUnreachable: .network
        case .callbackRejected, .callbackAccepted: .callback
        }
    }

    var isFailure: Bool {
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

    var summary: String {
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
            "\(endpoint.rawValue): HTTP \(status)"
        case .endpointUnreachable(let endpoint, let error):
            "\(endpoint.rawValue): \(error.diagnosticKind)"
        case .tokenRefreshed:
            "Access token refreshed"
        case .tokenRefreshFailed(let error):
            "Access token refresh failed: \(error.diagnosticKind)"
        case .callbackRejected:
            "Rejected an invalid loopback callback request"
        case .callbackAccepted:
            "Accepted the OAuth callback"
        case .disconnected:
            "Disconnected and deleted local authorization"
        }
    }

    private static func names(_ metrics: Set<Metric>) -> String {
        metrics.map(\.rawValue).sorted().joined(separator: ", ")
    }
}

enum DiagnosticCategory: String, Sendable {
    case refresh
    case authorization
    case network
    case callback
}

/// The Oura endpoints the app calls. Logging a case instead of a URL keeps
/// query strings, which can hold tokens, out of diagnostics.
enum OuraEndpoint: String, Sendable, CaseIterable {
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

    init(path: String) {
        self = Self.allCases.first { $0 != .other && path.hasSuffix($0.rawValue) } ?? .other
    }
}

extension RingStatsError {
    /// A stable identifier with no associated text. Messages from upstream
    /// services are dropped because they can echo request data.
    var diagnosticKind: String {
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
final class DiagnosticsLog: @unchecked Sendable {
    static let shared = DiagnosticsLog()
    static let subsystem = "com.digitaltableteur.ringstats"

    struct Entry: Sendable, Equatable {
        let date: Date
        let event: DiagnosticEvent
    }

    private let capacity: Int
    private let lock = NSLock()
    private var buffer: [Entry] = []
    private let clock: @Sendable () -> Date

    init(capacity: Int = 200, clock: @escaping @Sendable () -> Date = Date.init) {
        self.capacity = capacity
        self.clock = clock
    }

    var entries: [Entry] { lock.withLock { buffer } }

    func record(_ event: DiagnosticEvent) {
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

    func clear() {
        lock.withLock { buffer.removeAll() }
    }
}

/// A plain-text report for a support request. It describes state and recent
/// events without any health values, identifiers, or secrets.
enum DiagnosticsReport {
    @MainActor
    static func make(model: AppViewModel, log: DiagnosticsLog = .shared, now: Date = Date()) -> String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif

        var lines = [
            "Ring Stats diagnostics",
            "Generated: \(timestamp(now))",
            "",
            "This report contains no health values, credentials, tokens, or account identifiers.",
            "",
            "App: \(version) (\(build)), \(architecture)",
            "macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "Connection: \(connectionSummary(model.state))",
            "Last refresh: \(outcomeSummary(model.lastRefreshOutcome, now: now))",
        ]

        let readings = model.snapshot.readings.sorted { $0.key.rawValue < $1.key.rawValue }
        if !readings.isEmpty {
            lines.append("Stats:")
            for (metric, reading) in readings {
                var line = "  \(metric.rawValue): \(availabilitySummary(reading.availability))"
                if let failure = model.snapshot.failedMetrics[metric] {
                    line += " (\(failure.diagnosticKind))"
                }
                lines.append(line)
            }
        }
        let battery = model.snapshot.battery == nil
            ? "none"
            : (model.snapshot.batteryIsStale ? "stale" : "available")
        lines.append("Battery reading: \(battery)")

        let entries = log.entries
        lines.append("")
        lines.append("Recent events (\(entries.count)):")
        if entries.isEmpty {
            lines.append("  none")
        }
        for entry in entries {
            lines.append("  \(timestamp(entry.date))  \(entry.event.summary)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func connectionSummary(_ state: AppState) -> String {
        switch state {
        case .unconfigured: "not configured"
        case .configured: "configured, not connected"
        case .authorizing: "authorizing"
        case .connected: "connected"
        case .refreshing: "refreshing"
        case .authorizationExpired: "authorization expired"
        case .failed(_, let connected, let configured):
            "failed (\(connected ? "connected" : "not connected"), \(configured ? "configured" : "not configured"))"
        }
    }

    private static func outcomeSummary(_ outcome: RefreshOutcome, now: Date) -> String {
        func age(_ date: Date) -> String { "\(Int(max(0, now.timeIntervalSince(date))))s ago" }
        return switch outcome {
        case .none: "none"
        case .succeeded(let at): "succeeded \(age(at))"
        case .partial(let at): "partial \(age(at))"
        case .failed(let at): "failed \(age(at))"
        }
    }

    private static func availabilitySummary(_ availability: MetricAvailability) -> String {
        switch availability {
        case .available: "available"
        case .stale: "stale"
        case .permissionRequired: "needs access"
        case .unavailable: "unavailable"
        case .noData: "no data yet"
        }
    }
}
