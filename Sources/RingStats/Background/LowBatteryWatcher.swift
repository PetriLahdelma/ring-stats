import Combine
import Foundation
import RingStatsCore
import UserNotifications

/// Posts the low-battery notification.
protocol LowBatteryNotifying: Sendable {
    func requestAuthorization() async -> Bool
    func notifyLowBattery(level: Int) async
}

struct UserNotificationsNotifier: LowBatteryNotifying {
    static let requestIdentifier = "low-ring-battery"

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notifyLowBattery(level: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Ring battery low"
        content.body = "Your ring is at \(level)%. Charge it soon to keep tracking."
        content.sound = .default
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

enum LowBatteryPreference {
    static let storageKey = "low-battery-notifications"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// Watches every snapshot the model publishes, whether from the popover, a
/// Shortcut, or a background refresh, and announces a low ring battery once
/// per drain. It keeps its state in memory only.
@MainActor
final class LowBatteryWatcher {
    private let notifier: any LowBatteryNotifying
    private let isEnabled: @MainActor () -> Bool
    private var alert = LowBatteryAlert()
    private var subscription: AnyCancellable?
    /// Levels announced so far. Tests read it.
    private(set) var announcedLevels: [Int] = []

    init(
        model: AppViewModel,
        notifier: any LowBatteryNotifying = UserNotificationsNotifier(),
        isEnabled: @escaping @MainActor () -> Bool = { LowBatteryPreference.isEnabled }
    ) {
        self.notifier = notifier
        self.isEnabled = isEnabled
        subscription = model.$snapshot.sink { [weak self] snapshot in
            MainActor.assumeIsolated { self?.evaluate(snapshot) }
        }
    }

    private func evaluate(_ snapshot: HealthSnapshot) {
        guard isEnabled(),
              let level = alert.evaluate(snapshot.battery, isStale: snapshot.batteryIsStale) else { return }
        announcedLevels.append(level)
        DiagnosticsLog.shared.record(.lowBatteryNotified)
        let notifier = notifier
        Task { await notifier.notifyLowBattery(level: level) }
    }
}
