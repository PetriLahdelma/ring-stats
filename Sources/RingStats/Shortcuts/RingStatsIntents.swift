import AppIntents
import Foundation
import RingStatsCore

/// The app's model, for intents that run inside the running app. Set once by
/// the app delegate.
@MainActor
enum ShortcutBridge {
    static weak var model: AppViewModel?

    static var visibleMetrics: [Metric] {
        MetricConfiguration.decode(
            UserDefaults.standard.string(forKey: MetricConfiguration.storageKey)
        ).visibleMetrics
    }

    static func connectedModel() throws(ShortcutFailure) -> AppViewModel {
        guard let model else { throw .notConnected }
        return model
    }
}

enum RingStat: String, AppEnum {
    case readiness
    case sleep
    case activity
    case heartRate
    case stress
    case resilience

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ring Stat"
    static let caseDisplayRepresentations: [RingStat: DisplayRepresentation] = [
        .readiness: "Readiness",
        .sleep: "Sleep",
        .activity: "Activity",
        .heartRate: "Heart rate",
        .stress: "Stress",
        .resilience: "Resilience",
    ]

    var metric: Metric {
        switch self {
        case .readiness: .readiness
        case .sleep: .sleep
        case .activity: .activity
        case .heartRate: .heartRate
        case .stress: .stress
        case .resilience: .resilience
        }
    }
}

struct GetRingStatIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Ring Stat"
    static let description = IntentDescription(
        "Returns a stat from Ring Stats, refreshed from Oura when it is more than five minutes old."
    )

    @Parameter(title: "Stat", default: .readiness)
    var stat: RingStat

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$stat)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let model = try ShortcutBridge.connectedModel()
            let answer = try await ShortcutAnswers.reading(
                for: stat.metric,
                model: model,
                visible: ShortcutBridge.visibleMetrics
            )
            return .result(value: answer.value, dialog: IntentDialog(stringLiteral: answer.dialog))
        } catch {
            throw ShortcutIntentError(error)
        }
    }
}

struct GetRingBatteryIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Ring Battery"
    static let description = IntentDescription(
        "Returns the ring battery percentage from Ring Stats, refreshed from Oura when it is more than five minutes old."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        do {
            let model = try ShortcutBridge.connectedModel()
            let answer = try await ShortcutAnswers.battery(model: model, visible: ShortcutBridge.visibleMetrics)
            return .result(value: answer.value, dialog: IntentDialog(stringLiteral: answer.dialog))
        } catch {
            throw ShortcutIntentError(error)
        }
    }
}

/// Carries a `ShortcutFailure` message to Shortcuts.
struct ShortcutIntentError: Error, CustomLocalizedStringResourceConvertible {
    let failure: ShortcutFailure

    init(_ failure: ShortcutFailure) {
        self.failure = failure
    }

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: failure.message)
    }
}

struct RingStatsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRingStatIntent(),
            phrases: [
                "Get \(\.$stat) from \(.applicationName)",
                "What is my \(\.$stat) in \(.applicationName)",
            ],
            shortTitle: "Get Ring Stat",
            systemImageName: "circle.dashed"
        )
        AppShortcut(
            intent: GetRingBatteryIntent(),
            phrases: [
                "Get ring battery from \(.applicationName)",
                "\(.applicationName) ring battery",
            ],
            shortTitle: "Ring Battery",
            systemImageName: "battery.75percent"
        )
    }
}
