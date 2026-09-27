import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var snapshot = HealthSnapshot.empty
    @Published private(set) var state = AppState.unconfigured
    @Published var errorMessage: String?
    @Published private(set) var lastRefreshOutcome = RefreshOutcome.none

    static let partialRefreshMessage =
        "Some stats could not be updated. Showing the last known values where available."

    var connected: Bool { state.isConnected }
    var configured: Bool { state.isConfigured }
    var loading: Bool { state.isLoading }
    var isRefreshing: Bool { state == .refreshing }
    var lastUpdatedAt: Date? { snapshot.hasData ? snapshot.fetchedAt : nil }
    var isShowingStaleData: Bool {
        snapshot.hasData
            && (errorMessage != nil || !snapshot.staleMetrics.isEmpty || snapshot.batteryIsStale)
    }

    private let auth: any OAuthServicing
    private let api: any SnapshotFetching
    private let now: @Sendable () -> Date
    private let refreshTTL: TimeInterval
    private let authorizationHandler: (@Sendable (Set<OuraScope>) async throws -> Void)?
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

    init() {
        let auth = OAuthClient()
        self.auth = auth
        self.api = OuraAPI(auth: auth)
        self.now = Date.init
        self.refreshTTL = 5 * 60
        self.authorizationHandler = nil
        Task { await updateConnectionState() }
    }

    init(
        auth: any OAuthServicing,
        api: any SnapshotFetching,
        refreshTTL: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        authorizationHandler: (@Sendable (Set<OuraScope>) async throws -> Void)? = nil,
        checkConnectionOnInit: Bool = true
    ) {
        self.auth = auth
        self.api = api
        self.refreshTTL = refreshTTL
        self.now = now
        self.authorizationHandler = authorizationHandler
        if checkConnectionOnInit {
            Task { await updateConnectionState() }
        }
    }

    func updateConnectionState() async {
        if let startupError = await auth.startupError {
            errorMessage = startupError.localizedDescription
            state = .failed(message: startupError.localizedDescription, connected: false, configured: true)
            return
        }
        let configured = await auth.isConfigured
        let connected = await auth.isConnected
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
        let generation = operationGeneration
        if let authorizationTask {
            await waitFor(authorizationTask)
            guard operationIsCurrent(generation) else { return }
        }
        if let refreshTask {
            let coveredByActiveRefresh = activeRefreshMetrics.isSuperset(of: metrics)
                && (policy == .ifStale || activeRefreshPolicy == .force)
            await waitFor(refreshTask)
            guard operationIsCurrent(generation) else { return }
            if coveredByActiveRefresh { return }
        }

        guard operationIsCurrent(generation) else { return }
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
            return
        }

        state = .refreshing
        do {
            let refreshedSnapshot = try await api.fetchSnapshot(metrics: metrics, now: now())
            guard operationIsCurrent(generation) else { return }
            apply(refreshedSnapshot)
            state = .connected
        } catch let error as RingStatsError where error == .authenticationRequired || error == .notConnected {
            guard operationIsCurrent(generation) else { return }
            errorMessage = error.localizedDescription
            lastRefreshOutcome = .failed(at: now())
            state = .authorizationExpired
        } catch {
            // Keep the last successful snapshot visible. Freshness and the error
            // state make it explicit that the values could not be updated.
            guard operationIsCurrent(generation) else { return }
            errorMessage = error.localizedDescription
            lastRefreshOutcome = .failed(at: now())
            let configured = await auth.isConfigured
            guard operationIsCurrent(generation) else { return }
            let connected = await auth.isConnected
            guard operationIsCurrent(generation) else { return }
            state = .failed(
                message: error.localizedDescription,
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
            try await auth.configure(ClientCredentials(clientID: trimmedID, clientSecret: trimmedSecret))
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
        if let authorizationTask {
            await waitFor(authorizationTask)
            return
        }
        if let refreshTask {
            await waitFor(refreshTask)
            guard operationIsCurrent(generation) else { return }
        }
        if let authorizationTask {
            await waitFor(authorizationTask)
            return
        }
        guard operationIsCurrent(generation) else { return }
        let operationID = UUID()
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
            let scopes = OuraScope.required(for: metrics)
            if let authorizationHandler {
                try await authorizationHandler(scopes)
            } else {
                try await authorizeConfiguredApplication(scopes: scopes)
            }
            guard operationIsCurrent(generation) else { return }
            try Task.checkCancellation()
            let refreshedSnapshot = try await api.fetchSnapshot(metrics: metrics, now: now())
            guard operationIsCurrent(generation) else { return }
            apply(refreshedSnapshot)
            state = .connected
        } catch {
            guard operationIsCurrent(generation) else { return }
            if error is CancellationError {
                errorMessage = nil
                await updateConnectionState()
                return
            }
            errorMessage = error.localizedDescription
            let configured = await auth.isConfigured
            let connected = await auth.isConnected
            state = connected
                ? .failed(message: error.localizedDescription, connected: true, configured: configured)
                : Self.connectionState(configured: configured, connected: false)
        }
    }

    /// Accepts a fetched snapshot. Values that failed transiently keep their
    /// previous reading, and a partial result is reported rather than hidden.
    private func apply(_ refreshed: HealthSnapshot) {
        let merged = refreshed.merging(previous: snapshot)
        snapshot = merged
        if merged.hasTransientFailures {
            errorMessage = Self.partialRefreshMessage
            lastRefreshOutcome = .partial(at: merged.fetchedAt)
        } else {
            errorMessage = nil
            lastRefreshOutcome = .succeeded(at: merged.fetchedAt)
        }
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
        } catch {
            errorMessage = error.localizedDescription
            let configured = await auth.isConfigured
            let connected = await auth.isConnected
            state = .failed(
                message: error.localizedDescription,
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

    private func authorizeConfiguredApplication(scopes: Set<OuraScope>) async throws {
        try Task.checkCancellation()
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
            throw RingStatsError.callback("Could not open the browser for Oura authorization.")
        }
        let callback = try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await server.waitForCallback() }
            group.addTask {
                try await Task.sleep(for: .seconds(300))
                throw RingStatsError.callback("Oura authorization timed out. Start the connection again.")
            }
            guard let first = try await group.next() else {
                throw RingStatsError.callback("Oura authorization did not complete.")
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
            throw RingStatsError.callback("Oura authorization failed: \(oauthError)")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw RingStatsError.callback("Oura did not return an authorization code.")
        }
        try Task.checkCancellation()
        try await auth.exchange(code: code)
    }

    private func waitFor(_ task: Task<Void, Never>) async {
        waitingOperationCount += 1
        defer { waitingOperationCount -= 1 }
        await task.value
    }

    private static func connectionState(configured: Bool, connected: Bool) -> AppState {
        if connected { return .connected }
        return configured ? .configured : .unconfigured
    }

    private func operationIsCurrent(_ generation: UInt64) -> Bool {
        !isDisconnecting && generation == operationGeneration
    }
}
