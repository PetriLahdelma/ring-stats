import Foundation
import IOKit.ps
import RingStatsCore

/// Whether the Mac is on battery power or in Low Power Mode.
protocol PowerStateProviding: Sendable {
    var isConstrained: Bool { get }
}

struct SystemPowerState: PowerStateProviding {
    var isConstrained: Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }
        guard let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else { return false }
        return (source as String) == kIOPMBatteryPowerKey
    }
}

/// Refreshes the popover's stats in the background so they are current when
/// the popover opens and a low battery can be noticed. It uses the same
/// refresh as a popover open, so it fetches only the visible stats and reuses
/// data younger than the refresh interval.
@MainActor
final class BackgroundRefresher {
    static let activityIdentifier = "com.digitaltableteur.ringstats.background-refresh"

    private let model: AppViewModel
    private let power: any PowerStateProviding
    private let metrics: @MainActor () -> Set<Metric>
    private let now: @Sendable () -> Date
    private var scheduler: NSBackgroundActivityScheduler?

    init(
        model: AppViewModel,
        power: any PowerStateProviding = SystemPowerState(),
        metrics: @escaping @MainActor () -> Set<Metric>,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.model = model
        self.power = power
        self.metrics = metrics
        self.now = now
    }

    func start() {
        guard scheduler == nil else { return }
        let scheduler = NSBackgroundActivityScheduler(identifier: Self.activityIdentifier)
        scheduler.repeats = true
        scheduler.interval = BackgroundRefreshPolicy.interval
        scheduler.tolerance = 5 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            Task { @MainActor in
                await self?.runOnce()
                completion(.finished)
            }
        }
        self.scheduler = scheduler
    }

    func stop() {
        scheduler?.invalidate()
        scheduler = nil
    }

    /// One scheduled pass. Returns whether it fetched.
    @discardableResult
    func runOnce() async -> Bool {
        if !model.connected {
            await model.updateConnectionState()
        }
        guard model.connected else {
            DiagnosticsLog.shared.record(.backgroundRefreshSkipped(.notConnected))
            return false
        }
        guard BackgroundRefreshPolicy.shouldRefresh(
            lastFetchedAt: model.lastUpdatedAt,
            now: now(),
            constrained: power.isConstrained
        ) else {
            DiagnosticsLog.shared.record(.backgroundRefreshSkipped(.constrainedPower))
            return false
        }
        await model.refreshOnOpen(metrics: metrics())
        return true
    }
}
