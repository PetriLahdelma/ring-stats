import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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

    /// Two callers waiting on one refresh must not both start their own
    /// afterwards. The second waiter judges coverage against the refresh the
    /// first waiter starts, not the one that already finished.
    @Test @MainActor func waitersDoNotStartOverlappingRefreshes() async {
        let now = Date(timeIntervalSince1970: 12_500)
        func snapshot(_ metrics: Set<Metric>) -> HealthSnapshot {
            HealthSnapshot(
                readings: Dictionary(uniqueKeysWithValues: metrics.map {
                    ($0, MetricReading(value: "70", detail: "Good", score: 70))
                }),
                battery: nil,
                fetchedAt: now,
                coveredMetrics: metrics
            )
        }
        let api = SnapshotStub(
            results: [.success(snapshot([.sleep])), .success(snapshot([.sleep, .resilience])), .success(snapshot([.sleep]))],
            holdsFirstCall: true
        )
        let model = AppViewModel(
            auth: AuthStub(configured: true, connected: true),
            api: api,
            descriptor: OuraProvider.descriptor,
            now: { now },
            checkConnectionOnInit: false
        )

        let first = Task { await model.refreshNow(metrics: [.sleep]) }
        await api.started.wait()
        // Not covered by the running refresh, so it will start its own.
        let wider = Task { await model.refreshNow(metrics: [.sleep, .resilience]) }
        await waitUntil("wider refresh to queue") { model.waitingOperationCount == 1 }
        // Covered by the wider refresh once it starts, so it must join that
        // one rather than start a third.
        let narrow = Task { await model.refreshNow(metrics: [.sleep]) }
        await waitUntil("narrow refresh to queue") { model.waitingOperationCount == 2 }
        api.release.open()
        await first.value
        await wider.value
        await narrow.value

        #expect(await api.callCount == 2)
        #expect(model.snapshot.coveredMetrics == [.sleep, .resilience])
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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

    /// A refresh queued behind an authorization must finish once the
    /// authorization does. The waiter can resume before the authorization's
    /// own cleanup, so it has to yield instead of spinning on the main actor.
    @Test(.timeLimit(.minutes(1))) @MainActor func refreshQueuedBehindAnAuthorizationCompletes() async {
        let now = Date(timeIntervalSince1970: 14_000)
        let auth = AuthStub(configured: true, connected: false)
        let probe = AuthorizationProbe()
        let snapshot = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "80", detail: "Good", score: 80)],
            battery: nil,
            fetchedAt: now
        )
        let api = SnapshotStub(results: [.success(snapshot), .success(snapshot)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            descriptor: OuraProvider.descriptor,
            now: { now },
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let authorization = Task { await model.reauthorize(metrics: [.readiness]) }
        await probe.started.wait()
        let refresh = Task { await model.refreshNow(metrics: [.readiness]) }
        await waitUntil("refresh to queue behind the authorization") { model.waitingOperationCount == 1 }
        await auth.markConnected()
        probe.release.open()
        await authorization.value
        await refresh.value

        #expect(model.state == .connected)
        #expect(await api.callCount >= 1)
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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
            descriptor: OuraProvider.descriptor,
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
            battery: BatteryReading(level: 64, isCharging: false),
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
            batteryFailure: .timedOut
        )
        let api = SnapshotStub(results: [.success(first), .success(partial)])
        let model = AppViewModel(auth: auth, api: api, descriptor: OuraProvider.descriptor, now: { now.value }, checkConnectionOnInit: false)

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
        let model = AppViewModel(auth: auth, api: api, descriptor: OuraProvider.descriptor, now: { now }, checkConnectionOnInit: false)

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
        let model = AppViewModel(auth: auth, api: api, descriptor: OuraProvider.descriptor, now: { now.value }, checkConnectionOnInit: false)

        await model.refreshNow(metrics: [.stress])
        now.value = now.value.addingTimeInterval(600)
        await model.refreshNow(metrics: [.stress, .readiness])

        #expect(model.snapshot.readings[.stress]?.availability == .permissionRequired)
        #expect(model.errorMessage == nil)
        #expect(model.lastRefreshOutcome == .succeeded(at: denied.fetchedAt))
    }

    @Test @MainActor func failedStatsRetryAfterTheRetryIntervalNotOnEveryOpen() async {
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
            fetchedAt: now.value.addingTimeInterval(61),
            coveredMetrics: [.readiness, .activity]
        )
        let api = SnapshotStub(results: [.success(partial), .success(complete)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            descriptor: OuraProvider.descriptor,
            refreshTTL: 300,
            now: { now.value },
            checkConnectionOnInit: false
        )

        await model.refreshOnOpen(metrics: [.readiness, .activity])
        now.value = now.value.addingTimeInterval(30)
        await model.refreshOnOpen(metrics: [.readiness, .activity])
        #expect(await api.callCount == 1, "an open within the retry interval must not refetch")

        now.value = now.value.addingTimeInterval(31)
        await model.refreshOnOpen(metrics: [.readiness, .activity])

        #expect(await api.callCount == 2)
        #expect(model.snapshot.readings[.activity]?.value == "81")
        #expect(model.errorMessage == nil)
        #expect(model.lastRefreshOutcome == .succeeded(at: complete.fetchedAt))
    }

    @Test @MainActor func batteryPermissionFailureIsNotAPartialRefresh() async {
        let now = LockedClock(Date(timeIntervalSince1970: 44_000))
        let snapshot = HealthSnapshot(
            readings: [.readiness: MetricReading(value: "75", detail: "Good", score: 75)],
            battery: nil,
            fetchedAt: now.value,
            coveredMetrics: [.readiness],
            batteryFailure: .insufficientScope
        )
        let api = SnapshotStub(results: [.success(snapshot)])
        let model = AppViewModel(
            auth: AuthStub(configured: true, connected: true),
            api: api,
            descriptor: OuraProvider.descriptor,
            refreshTTL: 300,
            now: { now.value },
            checkConnectionOnInit: false
        )

        await model.refreshOnOpen(metrics: [.readiness])
        now.value = now.value.addingTimeInterval(120)
        await model.refreshOnOpen(metrics: [.readiness])

        #expect(await api.callCount == 1, "missing permission must not force a refetch on every open")
        #expect(model.lastRefreshOutcome == .succeeded(at: snapshot.fetchedAt))
        #expect(model.snapshot.batteryNeedsPermission)
    }

    @Test @MainActor func failedFetchAfterAuthorizationIsRecordedAsFailed() async {
        let now = Date(timeIntervalSince1970: 45_000)
        let auth = AuthStub(configured: true, connected: false)
        let api = SnapshotStub(results: [.failure(.timedOut)])
        let model = AppViewModel(
            auth: auth,
            api: api,
            descriptor: OuraProvider.descriptor,
            now: { now },
            authorizationHandler: { _ in await auth.markConnected() },
            checkConnectionOnInit: false
        )

        await model.reauthorize(metrics: [.readiness])

        #expect(model.lastRefreshOutcome == .failed(at: now))
        #expect(model.errorMessage != nil)
    }
}

/// Retry and retention rules on the snapshot itself.
struct SnapshotFreshnessTests {
    private func partial(failure: RingStatsError, at date: Date) -> HealthSnapshot {
        HealthSnapshot(
            readings: [
                .readiness: MetricReading(value: "75", detail: "Good", score: 75),
                .sleep: OuraAPI.placeholder(for: failure),
            ],
            battery: nil,
            fetchedAt: date,
            coveredMetrics: [.readiness, .sleep],
            failedMetrics: [.sleep: failure]
        )
    }

    @Test func rateLimitedFailuresWaitForRetryAfter() {
        let start = Date(timeIntervalSince1970: 60_000)
        let limited = partial(failure: .rateLimited(retryAfter: 120), at: start)
        let metrics: Set<Metric> = [.readiness, .sleep]
        #expect(limited.isFresh(for: metrics, at: start.addingTimeInterval(90), ttl: 300))
        #expect(!limited.isFresh(for: metrics, at: start.addingTimeInterval(121), ttl: 300))

        let timedOut = partial(failure: .timedOut, at: start)
        #expect(timedOut.isFresh(for: metrics, at: start.addingTimeInterval(59), ttl: 300))
        #expect(!timedOut.isFresh(for: metrics, at: start.addingTimeInterval(61), ttl: 300))
    }

    /// A Retry-After the app cannot act on is ignored rather than trusted:
    /// "inf" and "1e400" parse as infinity, which crashed the message, and a
    /// huge value would have silenced refresh-on-open for years.
    @Test func retryAfterAcceptsOnlyWholeSecondsUpToAnHour() {
        #expect(OuraAPI.retryAfter("30") == 30)
        #expect(OuraAPI.retryAfter(" 3600 ") == 3_600)
        for bad in ["inf", "nan", "1e400", "-5", "0", "3601", "abc", "1.5", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            #expect(OuraAPI.retryAfter(bad) == nil, "\(bad)")
        }
        #expect(OuraAPI.retryAfter(nil) == nil)
        let limited = partial(failure: .rateLimited(retryAfter: .infinity), at: Date())
        #expect(limited.retryDelay == 3_600)
        #expect(RingStatsError.rateLimited(retryAfter: .infinity).errorDescription?.contains("shortly") == true)
    }

    /// A battery reading kept through failures expires like a stale stat,
    /// instead of showing a week-old percentage with full confidence.
    @Test func staleBatteryIsDroppedAfterTheRetentionLimit() {
        let start = Date(timeIntervalSince1970: 80_000)
        let original = HealthSnapshot(
            readings: [.sleep: MetricReading(value: "80", detail: "Good", score: 80)],
            battery: BatteryReading(level: 63, isCharging: false),
            fetchedAt: start
        )
        func batteryFailed(at date: Date) -> HealthSnapshot {
            HealthSnapshot(
                readings: [.sleep: MetricReading(value: "81", detail: "Good", score: 81)],
                battery: nil,
                fetchedAt: date,
                batteryFailure: .timedOut
            )
        }
        let hourLater = batteryFailed(at: start.addingTimeInterval(3_600)).merging(previous: original)
        #expect(hourLater.battery?.level == 63)
        #expect(hourLater.batteryIsStale)
        #expect(hourLater.batteryFetchedAt == start)

        let dayLater = batteryFailed(at: start.addingTimeInterval(25 * 3_600)).merging(previous: hourLater)
        #expect(dayLater.battery == nil)
        #expect(!dayLater.batteryIsStale)
    }

    @Test func staleValuesAreDroppedAfterTheRetentionLimit() {
        let start = Date(timeIntervalSince1970: 70_000)
        let original = HealthSnapshot(
            readings: [.sleep: MetricReading(value: "80", detail: "Good", score: 80)],
            battery: nil,
            fetchedAt: start
        )
        let hourLater = partial(failure: .timedOut, at: start.addingTimeInterval(3_600))
        let kept = hourLater.merging(previous: original)
        #expect(kept.readings[.sleep]?.availability == .stale)
        #expect(kept.readings[.sleep]?.lastFetchedAt == start)

        // Still failing a day later: the retained value keeps its original
        // fetch time and is now too old to show.
        let dayLater = partial(failure: .timedOut, at: start.addingTimeInterval(25 * 3_600))
        let dropped = dayLater.merging(previous: kept)
        #expect(dropped.readings[.sleep]?.availability == .unavailable)
    }
}
