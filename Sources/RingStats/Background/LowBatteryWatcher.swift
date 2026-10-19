import Combine
import Foundation
import RingStatsCore
import UserNotifications

/// Posts the app's notifications. Each carries at most one number about the
/// ring's battery and never a score; Notification Center keeps what it shows.
protocol LowBatteryNotifying: Sendable {
    func requestAuthorization() async -> Bool
    func notifyLowBattery(level: Int) async
    func notifyChargeBeforeBed(projectedLevel: Int) async
    func notifyScoresArrived() async
}

struct UserNotificationsNotifier: LowBatteryNotifying {
    static let requestIdentifier = "low-ring-battery"

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static let bedtimeIdentifier = "charge-before-bed"
    static let scoresIdentifier = "scores-arrived"

    func notifyLowBattery(level: Int) async {
        await post(
            identifier: Self.requestIdentifier,
            title: "Ring battery low",
            body: "Your ring is at \(level)%. Charge it soon to keep tracking."
        )
    }

    func notifyChargeBeforeBed(projectedLevel: Int) async {
        await post(
            identifier: Self.bedtimeIdentifier,
            title: "Charge before bed",
            body: "At today's rate the ring will be at about \(projectedLevel)% by morning. Charge it while you wind down."
        )
    }

    func notifyScoresArrived() async {
        await post(
            identifier: Self.scoresIdentifier,
            title: "Today's scores are in",
            body: "Click the ring in the menu bar to see them."
        )
    }

    private func post(identifier: String, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// The notification settings, all off by default except the threshold and
/// quiet-hour defaults that apply once their switch is on.
enum LowBatteryPreference {
    static let storageKey = "low-battery-notifications"
    static let thresholdKey = "low-battery-threshold"
    static let quietHoursKey = "quiet-hours"
    static let quietStartKey = "quiet-hours-start"
    static let quietEndKey = "quiet-hours-end"
    static let bedtimeKey = "charge-before-bed"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }

    static var threshold: Int {
        let stored = UserDefaults.standard.integer(forKey: thresholdKey)
        return LowBatteryAlert.thresholds.contains(stored) ? stored : LowBatteryAlert.threshold
    }

    static var quietHours: QuietHours? {
        guard UserDefaults.standard.bool(forKey: quietHoursKey) else { return nil }
        let defaults = UserDefaults.standard
        return QuietHours(
            start: defaults.object(forKey: quietStartKey) == nil ? QuietHours.default.start : defaults.integer(forKey: quietStartKey),
            end: defaults.object(forKey: quietEndKey) == nil ? QuietHours.default.end : defaults.integer(forKey: quietEndKey)
        )
    }

    static var bedtimeReminder: Bool {
        UserDefaults.standard.bool(forKey: bedtimeKey)
    }
}

enum ScoresNotificationPreference {
    static let storageKey = "scores-notifications"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// What the battery watcher reads on every snapshot. Tests supply fixed
/// values; the app reads the preferences.
struct BatteryNotificationSettings: Sendable, Equatable {
    var lowBattery = false
    var threshold = LowBatteryAlert.threshold
    var quietHours: QuietHours?
    var bedtimeReminder = false

    @MainActor static var current: BatteryNotificationSettings {
        BatteryNotificationSettings(
            lowBattery: LowBatteryPreference.isEnabled,
            threshold: LowBatteryPreference.threshold,
            quietHours: LowBatteryPreference.quietHours,
            bedtimeReminder: LowBatteryPreference.bedtimeReminder
        )
    }
}

/// Watches every snapshot the model publishes, whether from the popover, a
/// Shortcut, or a background refresh, and announces a low ring battery once
/// per drain, plus the charge-before-bed suggestion. During quiet hours the
/// low-battery alert waits: the next snapshot outside them announces it if
/// the ring is still low. State lives in memory only.
@MainActor
final class LowBatteryWatcher {
    private let notifier: any LowBatteryNotifying
    private let settings: @MainActor () -> BatteryNotificationSettings
    private let now: @MainActor () -> Date
    private var alert: LowBatteryAlert?
    private var bedtime = BedtimeNudge()
    private var subscription: AnyCancellable?
    /// Levels announced so far. Tests read it.
    private(set) var announcedLevels: [Int] = []
    /// Projected morning levels the bedtime nudge announced. Tests read it.
    private(set) var bedtimeProjections: [Int] = []

    init(
        model: AppViewModel,
        notifier: any LowBatteryNotifying = UserNotificationsNotifier(),
        settings: @escaping @MainActor () -> BatteryNotificationSettings = { .current },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.notifier = notifier
        self.settings = settings
        self.now = now
        subscription = model.$snapshot.sink { [weak self] snapshot in
            MainActor.assumeIsolated { self?.evaluate(snapshot) }
        }
    }

    private func evaluate(_ snapshot: HealthSnapshot) {
        let settings = settings()
        let now = now()
        if alert == nil || alert?.threshold != settings.threshold {
            alert = LowBatteryAlert(threshold: settings.threshold)
        }
        let notifier = notifier
        let quiet = settings.quietHours?.contains(now) ?? false
        if settings.lowBattery, !quiet,
           let level = alert?.evaluate(snapshot.battery, isStale: snapshot.batteryIsStale) {
            announcedLevels.append(level)
            DiagnosticsLog.shared.record(.lowBatteryNotified)
            Task { await notifier.notifyLowBattery(level: level) }
        }
        if settings.bedtimeReminder,
           let projected = bedtime.evaluate(
               snapshot.battery,
               isStale: snapshot.batteryIsStale,
               now: now,
               quietHours: settings.quietHours ?? .default,
               threshold: settings.threshold
           ) {
            bedtimeProjections.append(projected)
            DiagnosticsLog.shared.record(.chargeBeforeBedNotified)
            Task { await notifier.notifyChargeBeforeBed(projectedLevel: projected) }
        }
    }
}

/// Says once a day that today's scores have arrived, after a refresh that
/// found them missing. Opt-in; the notification names no value.
@MainActor
final class ScoresArrivedWatcher {
    private let notifier: any LowBatteryNotifying
    private let isEnabled: @MainActor () -> Bool
    private let now: @MainActor () -> Date
    private var arrival = ScoresArrival()
    private var subscription: AnyCancellable?
    /// How many times the arrival was announced. Tests read it.
    private(set) var announcements = 0

    init(
        model: AppViewModel,
        notifier: any LowBatteryNotifying = UserNotificationsNotifier(),
        isEnabled: @escaping @MainActor () -> Bool = { ScoresNotificationPreference.isEnabled },
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.notifier = notifier
        self.isEnabled = isEnabled
        self.now = now
        subscription = model.$snapshot.sink { [weak self] snapshot in
            MainActor.assumeIsolated { self?.evaluate(snapshot) }
        }
    }

    private func evaluate(_ snapshot: HealthSnapshot) {
        // The tracker runs even while disabled, so turning the switch on at
        // noon does not announce scores that were already there.
        let arrived = arrival.evaluate(snapshot, now: now())
        guard arrived, isEnabled() else { return }
        announcements += 1
        DiagnosticsLog.shared.record(.scoresArrivedNotified)
        let notifier = notifier
        Task { await notifier.notifyScoresArrived() }
    }
}
