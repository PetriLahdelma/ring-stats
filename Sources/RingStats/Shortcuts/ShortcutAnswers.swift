import Foundation
import RingStatsCore

/// What a Shortcuts action returns: a value for the next action and a
/// sentence for Siri or the Shortcuts result.
struct ShortcutAnswer<Value: Sendable & Equatable>: Sendable, Equatable {
    let value: Value
    let dialog: String
}

/// Why a Shortcuts action could not answer. Each case tells the user what to
/// do, and none carries a health value.
enum ShortcutFailure: Error, Equatable {
    case notConnected
    case authorizationExpired
    case needsAccess(Metric)
    case needsBatteryAccess
    case noData(Metric)
    case unavailable(Metric)
    case batteryUnavailable

    var message: String {
        switch self {
        case .notConnected:
            "Ring Stats is not connected to Oura. Open Ring Stats to connect."
        case .authorizationExpired:
            "Your Oura authorization has expired. Open Ring Stats to reauthorize."
        case .needsAccess(let metric):
            "Ring Stats does not have Oura permission for \(metric.title). Reauthorize in Ring Stats with that stat shown."
        case .needsBatteryAccess:
            "Ring Stats does not have Oura permission for the ring battery. Reauthorize in Ring Stats."
        case .noData(let metric):
            "Oura has no \(metric.title) data yet. Open the Oura phone app to sync."
        case .unavailable(let metric):
            "\(metric.title) could not be fetched from Oura. Try again shortly."
        case .batteryUnavailable:
            "The ring battery could not be fetched from Oura. Try again shortly."
        }
    }
}

/// Answers Shortcuts actions from the running app's model. Values are read from
/// memory, after the same refresh a popover open would do, so nothing is
/// written to disk. The refresh includes the popover's visible stats, so a
/// Shortcut does not leave the popover with a partial snapshot.
@MainActor
enum ShortcutAnswers {
    static func reading(
        for metric: Metric,
        model: AppViewModel,
        visible: [Metric]
    ) async throws(ShortcutFailure) -> ShortcutAnswer<String> {
        try await refresh(model: model, metrics: Set(visible).union([metric]))
        guard let reading = model.snapshot.readings[metric] else {
            throw .unavailable(metric)
        }
        switch reading.availability {
        case .available, .stale:
            return ShortcutAnswer(value: reading.value, dialog: dialog(for: metric, reading: reading))
        case .permissionRequired:
            throw .needsAccess(metric)
        case .noData:
            throw .noData(metric)
        case .unavailable:
            throw .unavailable(metric)
        }
    }

    static func battery(model: AppViewModel, visible: [Metric]) async throws(ShortcutFailure) -> ShortcutAnswer<Int> {
        try await refresh(model: model, metrics: Set(visible))
        guard let battery = model.snapshot.battery, let level = battery.level else {
            throw model.snapshot.batteryNeedsPermission ? .needsBatteryAccess : .batteryUnavailable
        }
        var sentence = "Ring battery \(level)%"
        if battery.isCharging {
            sentence += level >= 100 ? ", charged" : ", charging"
        }
        if model.snapshot.batteryIsStale {
            sentence += ". The latest refresh failed, so this is the last known level"
        }
        return ShortcutAnswer(value: level, dialog: sentence + ".")
    }

    private static func refresh(model: AppViewModel, metrics: Set<Metric>) async throws(ShortcutFailure) {
        if !model.connected {
            await model.updateConnectionState()
        }
        if model.state == .authorizationExpired { throw .authorizationExpired }
        guard model.connected else { throw .notConnected }
        await model.refreshOnOpen(metrics: metrics)
        if model.state == .authorizationExpired { throw .authorizationExpired }
    }

    private static func dialog(for metric: Metric, reading: MetricReading) -> String {
        var sentence = switch metric {
        case .heartRate: "\(metric.title) \(reading.value) bpm"
        default: "\(metric.title) \(reading.value)" + (reading.detail.map { ", \($0)" } ?? "")
        }
        if reading.availability == .stale {
            sentence += ". The latest refresh failed, so this is the last known value"
        }
        return sentence + "."
    }
}
