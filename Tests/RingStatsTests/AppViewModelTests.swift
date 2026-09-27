import Foundation
import Testing
@testable import RingStats

/// Refresh, authorization, and disconnect orchestration in AppViewModel.
struct AppViewModelTests {
    @Test @MainActor func refreshOnOpenUsesTTLAndForwardsOnlyVisibleMetrics() async {
        let now = LockedClock(Date(timeIntervalSince1970: 10_000))
        let auth = AuthStub(configured: true, connected: true)
        let first = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "72", detail: "Good", score: 72)],
            battery: nil,
            fetchedAt: now.value
        )
        let api = SnapshotStub(results: [.success(first)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            refreshTTL: 300,
            now: { now.value },
            checkConnectionOnInit: false
        )

        await model.updateConnectionState()
        await model.refreshOnOpen(metrics: [.readiness])
        now.value = now.value.addingTimeInterval(60)
        await model.refreshOnOpen(metrics: [.readiness])

        #expect(await api.callCount == 1)
        #expect(await api.requestedMetrics == [[.readiness]])
        #expect(model.lastUpdatedAt == first.fetchedAt)
        #expect(model.state == .connected)
    }

    @Test @MainActor func enablingMetricWithinTTLFetchesExpandedMetricSet() async {
        let now = LockedClock(Date(timeIntervalSince1970: 11_000))
        let auth = AuthStub(configured: true, connected: true)
        let readiness = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "72", detail: "Good", score: 72)],
            battery: nil,
            fetchedAt: now.value,
            coveredMetrics: [.readiness]
        )
        let expanded = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "72", detail: "Good", score: 72),
                .heartRate: MetricReading(value: "64", detail: "bpm", score: nil),
            ],
            battery: nil,
            fetchedAt: now.value,
            coveredMetrics: [.readiness, .heartRate]
        )
        let api = SnapshotStub(results: [.success(readiness), .success(expanded)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            refreshTTL: 300,
            now: { now.value },
            checkConnectionOnInit: false
        )

        await model.refreshOnOpen(metrics: [.readiness])
        now.value = now.value.addingTimeInterval(30)
        await model.refreshOnOpen(metrics: [.readiness, .heartRate])

        #expect(await api.requestedMetrics == [[.readiness], [.readiness, .heartRate]])
        #expect(model.snapshot.coveredMetrics == [.readiness, .heartRate])
    }

    @Test @MainActor func concurrentRefreshesCoalesceIntoOneFetch() async {
        let now = Date(timeIntervalSince1970: 12_000)
        let auth = AuthStub(configured: true, connected: true)
        let snapshot = HealthSnapshot(
            readings: [.sleep: MetricReading(value: "80", detail: "Good", score: 80)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(snapshot)], holdsFirstCall: true)
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )

        let first = Task { await model.refreshNow(metrics: [.sleep]) }
        await api.started.wait()
        let second = Task { await model.refreshNow(metrics: [.sleep]) }
        await waitUntil("second refresh to queue") { model.waitingOperationCount == 1 }
        api.release.open()
        await first.value
        await second.value

        #expect(await api.callCount == 1)
        #expect(model.state == .connected)
    }

    @Test @MainActor func forceRefreshRequestsOnlyCurrentlyVisibleMetrics() async {
        let now = Date(timeIntervalSince1970: 13_000)
        let auth = AuthStub(configured: true, connected: true)
        let expanded = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "72", detail: "Good", score: 72),
                .heartRate: MetricReading(value: "64", detail: "bpm", score: nil),
            ],
            battery: nil,
            fetchedAt: now,
            coveredMetrics: [.readiness, .heartRate]
        )
        let narrowed = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "73", detail: "Good", score: 73)],
            battery: nil,
            fetchedAt: now,
            coveredMetrics: [.readiness]
        )
        let api = SnapshotStub(results: [.success(expanded), .success(narrowed)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )

        await model.refreshNow(metrics: [.readiness, .heartRate])
        await model.refreshNow(metrics: [.readiness])

        #expect(await api.requestedMetrics == [[.readiness, .heartRate], [.readiness]])
        #expect(model.snapshot.coveredMetrics == [.readiness])
        #expect(model.snapshot.readings[.heartRate] == nil)
    }

    @Test @MainActor func disconnectWaitsForCancelledRefreshBeforeClearingState() async {
        let now = Date(timeIntervalSince1970: 14_000)
        let auth = AuthStub(configured: true, connected: true)
        let delayed = HealthSnapshot(
            readings: [.activity: MetricReading(value: "90", detail: "Optimal", score: 90)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(delayed)], holdsFirstCall: true)
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )

        let refresh = Task { await model.refreshNow(metrics: [.activity]) }
        await api.started.wait()
        await model.disconnect()
        await refresh.value

        #expect(model.snapshot == .empty)
        #expect(model.state == .unconfigured)
        #expect(!(await auth.isConnected))
        #expect(!(await auth.isConfigured))
    }

    @Test @MainActor func disconnectFencesRefreshQueuedBehindAuthorization() async {
        let auth = AuthStub(configured: true, connected: false)
        let probe = AuthorizationProbe()
        let api = SnapshotStub(results: [])
        let model = AppViewModel(
            auth: auth,
            api: api,
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let authorization = Task { await model.reauthorize(metrics: [.readiness]) }
        await probe.started.wait()
        let queuedRefresh = Task { await model.refreshNow(metrics: [.readiness]) }
        await waitUntil("refresh to queue behind authorization") { model.waitingOperationCount == 1 }

        await model.disconnect()
        await authorization.value
        await queuedRefresh.value

        #expect(await api.callCount == 0)
        #expect(model.snapshot == .empty)
        #expect(model.state == .unconfigured)
        #expect(!(await auth.isConfigured))
    }

    @Test @MainActor func disconnectFencesAuthorizationQueuedBehindRefresh() async {
        let now = Date(timeIntervalSince1970: 14_500)
        let auth = AuthStub(configured: true, connected: true)
        let delayed = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "72", detail: "Good", score: 72)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(delayed)], holdsFirstCall: true)
        let probe = AuthorizationProbe(holds: false)
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let refresh = Task { await model.refreshNow(metrics: [.readiness]) }
        await api.started.wait()
        let queuedAuthorization = Task { await model.reauthorize(metrics: [.readiness]) }
        await waitUntil("authorization to queue behind refresh") { model.waitingOperationCount == 1 }

        await model.disconnect()
        await refresh.value
        await queuedAuthorization.value

        #expect(await probe.callCount == 0)
        #expect(model.snapshot == .empty)
        #expect(model.state == .unconfigured)
        #expect(!(await auth.isConfigured))
    }

    @Test @MainActor func duplicateAuthorizationCoalescesAndCancellationReachesOperation() async {
        let auth = AuthStub(configured: true, connected: false)
        let probe = AuthorizationProbe()
        let api = SnapshotStub(results: [])
        let model = AppViewModel(
            auth: auth,
            api: api,
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let first = Task { await model.reauthorize(metrics: [.readiness]) }
        await probe.started.wait()
        let second = Task { await model.reauthorize(metrics: [.readiness]) }
        await waitUntil("duplicate authorization to join") { model.waitingOperationCount == 1 }
        #expect(await probe.callCount == 1)

        await model.cancelAuthorization()
        await first.value
        await second.value

        #expect(await probe.wasCancelled)
        #expect(model.state == .configured)
    }

    @Test @MainActor func duplicateConnectRequestsShareOneAuthorizationAndFetch() async {
        let now = Date(timeIntervalSince1970: 15_000)
        let auth = AuthStub(configured: false, connected: false)
        let probe = AuthorizationProbe()
        let snapshot = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "72", detail: "Good", score: 72)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(snapshot)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let first = Task {
            await model.connect(clientID: "client", clientSecret: "secret", metrics: [.readiness])
        }
        await probe.started.wait()
        let second = Task {
            await model.connect(clientID: "client", clientSecret: "secret", metrics: [.readiness])
        }
        await waitUntil("duplicate connect to join") { model.waitingOperationCount == 1 }
        probe.release.open()
        await first.value
        await second.value

        #expect(await probe.callCount == 1)
        #expect(await api.callCount == 1)
        #expect(model.state == .connected)
    }

    @Test @MainActor func failedRefreshRetainsLastSuccessfulSnapshot() async {
        let now = LockedClock(Date(timeIntervalSince1970: 20_000))
        let auth = AuthStub(configured: true, connected: true)
        let first = HealthSnapshot(
            readings: [.sleep: MetricReading(value: "84", detail: "Good", score: 84)],
            battery: nil,
            fetchedAt: now.value
        )
        let api = SnapshotStub(results: [
            .success(first),
            .failure(.rateLimited(retryAfter: 30)),
        ])
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now.value },
            checkConnectionOnInit: false
        )

        await model.refreshNow(metrics: [.sleep])
        now.value = now.value.addingTimeInterval(600)
        await model.refreshNow(metrics: [.sleep])

        #expect(model.snapshot == first)
        #expect(model.isShowingStaleData)
        #expect(model.errorMessage?.contains("30 seconds") == true)
        #expect(model.state.isConnected)
    }

    @Test @MainActor func authenticationFailureTransitionsToExpiredWithoutErasingData() async {
        let now = Date(timeIntervalSince1970: 30_000)
        let auth = AuthStub(configured: true, connected: true)
        let first = HealthSnapshot(
            readings: [.activity: MetricReading(value: "76", detail: "Good", score: 76)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(first), .failure(.authenticationRequired)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )

        await model.refreshNow(metrics: [.activity])
        await model.refreshNow(metrics: [.activity])

        #expect(model.snapshot == first)
        #expect(model.state == .authorizationExpired)
        #expect(model.isShowingStaleData)
    }

    // MARK: Partial refresh

    @Test @MainActor func transientMetricFailureKeepsLastKnownValueMarkedStale() async {
        let now = LockedClock(Date(timeIntervalSince1970: 40_000))
        let auth = AuthStub(configured: true, connected: true)
        let first = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "72", detail: "Good", score: 72),
                .activity: MetricReading(value: "80", detail: "Good", score: 80),
            ],
            battery: BatteryRecord(level: 64, charging: false, inCharger: false, timestamp: nil),
            fetchedAt: now.value
        )
        let partial = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "75", detail: "Good", score: 75),
                .activity: OuraAPI.placeholder(for: .timedOut),
            ],
            battery: nil,
            fetchedAt: now.value.addingTimeInterval(600),
            coveredMetrics: [.readiness, .activity],
            failedMetrics: [.activity: .timedOut],
            batteryFailed: true
        )
        let api = SnapshotStub(results: [.success(first), .success(partial)])
        let model = AppViewModel(auth: auth, api: api, now: { now.value }, checkConnectionOnInit: false)

        await model.refreshNow(metrics: [.readiness, .activity])
        now.value = now.value.addingTimeInterval(600)
        await model.refreshNow(metrics: [.readiness, .activity])

        #expect(model.snapshot.readings[.readiness]?.value == "75")
        #expect(model.snapshot.readings[.readiness]?.availability == .available)
        #expect(model.snapshot.readings[.activity]?.value == "80")
        #expect(model.snapshot.readings[.activity]?.availability == .stale)
        #expect(model.snapshot.battery?.level == 64)
        #expect(model.snapshot.batteryIsStale)
        #expect(model.errorMessage == nil)
        #expect(model.lastRefreshOutcome == .partial(at: partial.fetchedAt))
        #expect(model.isShowingStaleData)
        #expect(model.state == .connected)
    }

    @Test @MainActor func transientFailureWithoutEarlierValueStaysUnavailable() async {
        let now = Date(timeIntervalSince1970: 41_000)
        let auth = AuthStub(configured: true, connected: true)
        let partial = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "75", detail: "Good", score: 75),
                .activity: OuraAPI.placeholder(for: .timedOut),
            ],
            battery: nil,
            fetchedAt: now,
            coveredMetrics: [.readiness, .activity],
            failedMetrics: [.activity: .timedOut]
        )
        let api = SnapshotStub(results: [.success(partial)])
        let model = AppViewModel(auth: auth, api: api, now: { now }, checkConnectionOnInit: false)

        await model.refreshNow(metrics: [.readiness, .activity])

        #expect(model.snapshot.readings[.activity]?.availability == .unavailable)
        #expect(model.snapshot.readings[.activity]?.value == "—")
    }

    @Test @MainActor func permissionFailureIsNotMaskedByAnEarlierValue() async {
        let now = LockedClock(Date(timeIntervalSince1970: 42_000))
        let auth = AuthStub(configured: true, connected: true)
        let first = HealthSnapshot(
            readings: [.stress: MetricReading(value: "12m", detail: "Normal", score: nil)],
            battery: nil,
            fetchedAt: now.value
        )
        let denied = HealthSnapshot(
            readings: [
                .stress: OuraAPI.placeholder(for: .insufficientScope),
                .readiness: MetricReading(value: "70", detail: "Good", score: 70),
            ],
            battery: nil,
            fetchedAt: now.value.addingTimeInterval(600),
            coveredMetrics: [.stress, .readiness],
            failedMetrics: [.stress: .insufficientScope]
        )
        let api = SnapshotStub(results: [.success(first), .success(denied)])
        let model = AppViewModel(auth: auth, api: api, now: { now.value }, checkConnectionOnInit: false)

        await model.refreshNow(metrics: [.stress])
        now.value = now.value.addingTimeInterval(600)
        await model.refreshNow(metrics: [.stress, .readiness])

        #expect(model.snapshot.readings[.stress]?.availability == .permissionRequired)
        #expect(model.errorMessage == nil)
        #expect(model.lastRefreshOutcome == .succeeded(at: denied.fetchedAt))
    }

    @Test @MainActor func openingAgainRetriesTransientFailuresWithinTTL() async {
        let now = LockedClock(Date(timeIntervalSince1970: 43_000))
        let auth = AuthStub(configured: true, connected: true)
        let partial = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "75", detail: "Good", score: 75),
                .activity: OuraAPI.placeholder(for: .timedOut),
            ],
            battery: nil,
            fetchedAt: now.value,
            coveredMetrics: [.readiness, .activity],
            failedMetrics: [.activity: .timedOut]
        )
        let complete = HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "75", detail: "Good", score: 75),
                .activity: MetricReading(value: "81", detail: "Good", score: 81),
            ],
            battery: nil,
            fetchedAt: now.value.addingTimeInterval(30),
            coveredMetrics: [.readiness, .activity]
        )
        let api = SnapshotStub(results: [.success(partial), .success(complete)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            refreshTTL: 300,
            now: { now.value },
            checkConnectionOnInit: false
        )

        await model.refreshOnOpen(metrics: [.readiness, .activity])
        now.value = now.value.addingTimeInterval(30)
        await model.refreshOnOpen(metrics: [.readiness, .activity])

        #expect(await api.callCount == 2)
        #expect(model.snapshot.readings[.activity]?.value == "81")
        #expect(model.errorMessage == nil)
        #expect(model.lastRefreshOutcome == .succeeded(at: complete.fetchedAt))
    }
}
