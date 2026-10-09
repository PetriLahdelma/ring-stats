import AppKit
import Foundation
import SwiftUI
import RingStatsCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot.empty
    @Published private(set) var state = AppState.unconfigured
    @Published var errorMessage: String?
    @Published private(set) var lastRefreshOutcome = RefreshOutcome.none

    var connected: Bool { state.isConnected }
    var configured: Bool { state.isConfigured }
    var loading: Bool { state.isLoading }
    var isRefreshing: Bool { state == .refreshing }
    var refreshInterval: TimeInterval { refreshTTL }
    var lastUpdatedAt: Date? { snapshot.hasData ? snapshot.fetchedAt : nil }
    /// When the last refresh ran, whether or not it succeeded.
    var lastRefreshAttemptAt: Date? {
        switch lastRefreshOutcome {
        case .none: nil
        case .succeeded(let at), .partial(let at), .failed(let at): at
        }
    }
    var isShowingStaleData: Bool {
        snapshot.hasData
            && (errorMessage != nil || !snapshot.staleMetrics.isEmpty || snapshot.batteryIsStale)
    }

    let descriptor: ProviderDescriptor
    private let auth: any OAuthServicing
    private let api: any SnapshotFetching
    private let now: @Sendable () -> Date
    private let refreshTTL: TimeInterval
    private let authorizationHandler: (@Sendable (Set<AuthorizationScope>) async throws -> Void)?
    private var activeCallbackServer: CallbackServer?
    private var refreshTask: Task<Void, Never>?
    private var refreshOperationID: UUID?
    private var activeRefreshMetrics: Set<Metric> = []
    private var activeRefreshPolicy: RefreshPolicy?
    private var authorizationTask: Task<Void, Never>?
    private var authorizationOperationID: UUID?
    private var isDisconnecting = false
    private var operationGeneration: UInt64 = 0
    /// Operations currently waiting for another refresh or authorization to
    /// finish. Tests use it to know a request is queued without sleeping.
    private(set) var waitingOperationCount = 0

    convenience init() {
        self.init(provider: ProviderRegistry.makeDefault())
    }

    convenience init(provider: any HealthProvider) {
        self.init(auth: provider.account, api: provider.snapshots, descriptor: provider.descriptor)
    }

    init(
        auth: any OAuthServicing,
        api: any SnapshotFetching,
        descriptor: ProviderDescriptor,
        refreshTTL: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        authorizationHandler: (@Sendable (Set<AuthorizationScope>) async throws -> Void)? = nil,
        checkConnectionOnInit: Bool = true
    ) {
        self.auth = auth
        self.api = api
        self.descriptor = descriptor
        self.refreshTTL = refreshTTL
        self.now = now
        self.authorizationHandler = authorizationHandler
        if checkConnectionOnInit {
            Task { await updateConnectionState() }
        }
    }

    func updateConnectionState() async {
        if let startupError = await auth.startupError {
            errorMessage = describe(startupError)
            state = .failed(message: describe(startupError), connected: false, configured: true)
            return
        }
        let configured = await auth.isConfigured
        let connected = await auth.isConnected
        // An expired authorization has already cleared its token, so it
        // would read as merely configured; keep the more useful state.
        if state == .authorizationExpired, !connected { return }
        state = Self.connectionState(configured: configured, connected: connected)
    }

    /// Refreshes when the current snapshot is older than the TTL. Call this every
    /// time the menu-bar panel opens.
    func refreshOnOpen(metrics: Set<Metric> = Set(Metric.defaultVisible)) async {
        await refresh(metrics: metrics, policy: .ifStale)
    }

    /// Always refreshes. Use this for an explicit "Refresh Now" action.
    func refreshNow(metrics: Set<Metric> = Set(Metric.defaultVisible)) async {
        await refresh(metrics: metrics, policy: .force)
    }

    func refresh(
        metrics: Set<Metric> = Set(Metric.defaultVisible),
        policy: RefreshPolicy = .ifStale
    ) async {
        guard !isDisconnecting else { return }
        let metrics = descriptor.supported(metrics)
        let generation = operationGeneration
        // Another waiter can start a refresh or an authorization while this
        // one waits, so keep waiting until nothing is running, and judge
        // coverage against each refresh as it runs.
        while authorizationTask != nil || refreshTask != nil {
            if let authorizationTask {
                await waitFor(authorizationTask)
                guard operationIsCurrent(generation) else { return }
                // Same as below: the finished authorization clears itself in
                // its own continuation, which must run before this loop looks.
                if self.authorizationTask == authorizationTask { await Task.yield() }
                continue
            }
            guard let running = refreshTask else { continue }
            let coveredByActiveRefresh = activeRefreshMetrics.isSuperset(of: metrics)
                && (policy == .ifStale || activeRefreshPolicy == .force)
            await waitFor(running)
            guard operationIsCurrent(generation) else { return }
            if coveredByActiveRefresh { return }
            // The finished refresh clears itself in its own continuation;
            // yield so that runs before this loop looks again.
            if refreshTask == running { await Task.yield() }
        }
        let requestedMetrics = metrics
        let operationID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh(
                metrics: requestedMetrics,
                policy: policy,
                generation: generation
            )
        }
        refreshOperationID = operationID
        activeRefreshMetrics = requestedMetrics
        activeRefreshPolicy = policy
        refreshTask = task
        await task.value
        if refreshOperationID == operationID {
            refreshTask = nil
            refreshOperationID = nil
            activeRefreshMetrics = []
            activeRefreshPolicy = nil
        }
    }

    private func performRefresh(
        metrics: Set<Metric>,
        policy: RefreshPolicy,
        generation: UInt64
    ) async {
        let configured = await auth.isConfigured
        guard operationIsCurrent(generation) else { return }
        let connected = await auth.isConnected
        guard operationIsCurrent(generation) else { return }
        guard connected else {
            state = Self.connectionState(configured: configured, connected: connected)
            return
        }
        if policy == .ifStale, snapshot.isFresh(for: metrics, at: now(), ttl: refreshTTL) {
            state = .connected
            errorMessage = nil
            return
        }

        state = .refreshing
        DiagnosticsLog.shared.record(.refreshStarted(metrics: metrics, forced: policy == .force))
        do {
            let refreshedSnapshot = try await api.fetchSnapshot(metrics: metrics, now: now())
            guard operationIsCurrent(generation) else { return }
            apply(refreshedSnapshot)
            state = .connected
        } catch let error as RingStatsError where error == .authenticationRequired || error == .notConnected {
            guard operationIsCurrent(generation) else { return }
            errorMessage = describe(error)
            lastRefreshOutcome = .failed(at: now())
            DiagnosticsLog.shared.record(.refreshFailed(error))
            state = .authorizationExpired
        } catch {
            // Keep the last successful snapshot visible. Freshness and the error
            // state make it explicit that the values could not be updated.
            guard operationIsCurrent(generation) else { return }
            errorMessage = describe(error)
            lastRefreshOutcome = .failed(at: now())
            DiagnosticsLog.shared.record(.refreshFailed(Self.classified(error)))
            let configured = await auth.isConfigured
            guard operationIsCurrent(generation) else { return }
            let connected = await auth.isConnected
            guard operationIsCurrent(generation) else { return }
            state = .failed(
                message: describe(error),
                connected: connected,
                configured: configured
            )
        }
    }

    func connect(
        clientID: String,
        clientSecret: String,
        metrics: Set<Metric> = Set(Metric.defaultVisible)
    ) async {
        await authorize(metrics: metrics) { [auth] in
            let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else { throw RingStatsError.notConfigured }
            try await auth.configure(ClientCredentials(
                clientID: trimmedID,
                clientSecret: trimmedSecret,
                redirectURI: OAuthLoopback.callbackURL
            ))
        }
    }

    func reauthorize(metrics: Set<Metric> = Set(Metric.defaultVisible)) async {
        await authorize(metrics: metrics, prepare: {})
    }

    private func authorize(
        metrics: Set<Metric>,
        prepare: @escaping @MainActor @Sendable () async throws -> Void
    ) async {
        guard !isDisconnecting else { return }
        let generation = operationGeneration
        // A refresh started by another waiter must not run beside the
        // browser flow, or it would overwrite the authorizing state.
        while authorizationTask != nil || refreshTask != nil {
            if let authorizationTask {
                await waitFor(authorizationTask)
                return
            }
            guard let running = refreshTask else { continue }
            await waitFor(running)
            guard operationIsCurrent(generation) else { return }
            if refreshTask == running { await Task.yield() }
        }
        let operationID = UUID()
        let metrics = descriptor.supported(metrics)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performAuthorization(
                metrics: metrics,
                prepare: prepare,
                generation: generation
            )
        }
        authorizationOperationID = operationID
        authorizationTask = task
        await task.value
        if authorizationOperationID == operationID {
            authorizationTask = nil
            authorizationOperationID = nil
        }
    }

    private func performAuthorization(
        metrics: Set<Metric>,
        prepare: @MainActor @Sendable () async throws -> Void,
        generation: UInt64
    ) async {
        guard operationIsCurrent(generation) else { return }
        state = .authorizing
        do {
            try await prepare()
            guard operationIsCurrent(generation) else { return }
            try Task.checkCancellation()
            let scopes = descriptor.scopes(for: metrics)
            DiagnosticsLog.shared.record(.authorizationStarted(scopes: scopes))
            if let authorizationHandler {
                try await authorizationHandler(scopes)
            } else {
                try await authorizeConfiguredApplication(scopes: scopes)
            }
            guard operationIsCurrent(generation) else { return }
            try Task.checkCancellation()
            DiagnosticsLog.shared.record(.authorizationSucceeded)
            let refreshedSnapshot = try await api.fetchSnapshot(metrics: metrics, now: now())
            guard operationIsCurrent(generation) else { return }
            apply(refreshedSnapshot)
            state = .connected
        } catch {
            guard operationIsCurrent(generation) else { return }
            if error is CancellationError {
                DiagnosticsLog.shared.record(.authorizationCancelled)
                errorMessage = nil
                await updateConnectionState()
                return
            }
            errorMessage = describe(error)
            DiagnosticsLog.shared.record(.authorizationFailed(Self.classified(error)))
            let configured = await auth.isConfigured
            let connected = await auth.isConnected
            if connected {
                // Authorization succeeded but the first fetch did not; the
                // status must not keep claiming an earlier success.
                lastRefreshOutcome = .failed(at: now())
            }
            state = connected
                ? .failed(message: describe(error), connected: true, configured: configured)
                : Self.connectionState(configured: configured, connected: false)
        }
    }

    /// Accepts a fetched snapshot. Values that failed transiently keep their
    /// previous reading. A partial result is reported through
    /// `lastRefreshOutcome` and each affected tile, not a second error line.
    private func apply(_ refreshed: HealthSnapshot) {
        let merged = refreshed.merging(previous: snapshot)
        snapshot = merged
        errorMessage = nil
        if merged.hasTransientFailures {
            lastRefreshOutcome = .partial(at: merged.fetchedAt)
            DiagnosticsLog.shared.record(
                .refreshPartial(failed: merged.failedMetrics, batteryFailed: merged.batteryFailure != nil)
            )
        } else {
            lastRefreshOutcome = .succeeded(at: merged.fetchedAt)
            DiagnosticsLog.shared.record(.refreshSucceeded(metrics: merged.coveredMetrics))
        }
    }

    private static func classified(_ error: any Error) -> RingStatsError {
        (error as? RingStatsError) ?? .transport("")
    }

    func disconnect() async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        operationGeneration &+= 1
        defer { isDisconnecting = false }
        let pendingAuthorization = authorizationTask
        let pendingRefresh = refreshTask
        pendingAuthorization?.cancel()
        pendingRefresh?.cancel()
        await activeCallbackServer?.cancel()
        await pendingAuthorization?.value
        await pendingRefresh?.value
        authorizationTask = nil
        authorizationOperationID = nil
        refreshTask = nil
        refreshOperationID = nil
        activeRefreshMetrics = []
        activeRefreshPolicy = nil
        snapshot = .empty
        lastRefreshOutcome = .none
        do {
            try await auth.disconnect()
            errorMessage = nil
            state = .unconfigured
            DiagnosticsLog.shared.record(.disconnected)
        } catch {
            errorMessage = describe(error)
            let configured = await auth.isConfigured
            let connected = await auth.isConnected
            state = .failed(
                message: describe(error),
                connected: connected,
                configured: configured
            )
        }
    }

    func cancelAuthorization() async {
        authorizationTask?.cancel()
        await activeCallbackServer?.cancel()
        activeCallbackServer = nil
        if let authorizationTask {
            await authorizationTask.value
        }
        authorizationTask = nil
        authorizationOperationID = nil
        errorMessage = nil
        await updateConnectionState()
    }

    private func authorizeConfiguredApplication(scopes: Set<AuthorizationScope>) async throws {
        try Task.checkCancellation()
        let providerName = descriptor.displayName
        let state = UUID().uuidString
        let browserURL = try await auth.authorizationRequest(state: state, scopes: scopes)
        let server = CallbackServer(expectedState: state)
        activeCallbackServer = server
        defer {
            activeCallbackServer = nil
            Task { await server.cancel() }
        }
        try await server.start()
        try Task.checkCancellation()
        guard NSWorkspace.shared.open(browserURL) else {
            throw RingStatsError.callback("Could not open the browser for \(providerName) authorization.")
        }
        let callback = try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await server.waitForCallback() }
            group.addTask {
                try await Task.sleep(for: .seconds(300))
                throw RingStatsError.callback("\(providerName) authorization timed out. Start the connection again.")
            }
            guard let first = try await group.next() else {
                throw RingStatsError.callback("\(providerName) authorization did not complete.")
            }
            group.cancelAll()
            return first
        }
        guard callback.path == OAuthLoopback.path else {
            throw RingStatsError.callback("Unexpected callback path.")
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw RingStatsError.callback("The connection state did not match.")
        }
        if let oauthError = items.first(where: { $0.name == "error" })?.value {
            throw RingStatsError.callback("\(providerName) authorization failed: \(oauthError)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw RingStatsError.callback("\(providerName) did not return an authorization code.")
        }
        try Task.checkCancellation()
        try await auth.exchange(code: code)
    }

    private func waitFor(_ task: Task<Void, Never>) async {
        waitingOperationCount += 1
        defer { waitingOperationCount -= 1 }
        await task.value
    }

    /// The user-facing text for an error, naming the provider.
    private func describe(_ error: Error) -> String {
        (error as? RingStatsError)?.message(provider: descriptor.displayName) ?? error.localizedDescription
    }

    private static func connectionState(configured: Bool, connected: Bool) -> AppState {
        if connected { return .connected }
        return configured ? .configured : .unconfigured
    }

    private func operationIsCurrent(_ generation: UInt64) -> Bool {
        !isDisconnecting && generation == operationGeneration
    }
}
