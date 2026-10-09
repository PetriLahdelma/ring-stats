import Foundation
import RingStatsCore

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
