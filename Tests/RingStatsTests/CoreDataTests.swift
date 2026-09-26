import Foundation
import Testing
@testable import RingStats

@Suite(.serialized)
struct CoreDataTests {
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
        let api = SnapshotStub(results: [.success(snapshot)], delay: .milliseconds(75))
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )

        async let first: Void = model.refreshNow(metrics: [.sleep])
        async let second: Void = model.refreshNow(metrics: [.sleep])
        _ = await (first, second)

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
        let api = SnapshotStub(results: [.success(delayed)], delay: .seconds(30))
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            checkConnectionOnInit: false
        )

        let refresh = Task { await model.refreshNow(metrics: [.activity]) }
        try? await Task.sleep(for: .milliseconds(30))
        await model.disconnect()
        await refresh.value

        #expect(model.snapshot == .empty)
        #expect(model.state == .unconfigured)
        #expect(!(await auth.isConnected))
        #expect(!(await auth.isConfigured))
    }

    @Test @MainActor func disconnectFencesRefreshQueuedBehindAuthorization() async {
        let auth = AuthStub(configured: true, connected: false)
        let probe = AuthorizationProbe(delay: .seconds(30))
        let api = SnapshotStub(results: [])
        let model = AppViewModel(
            auth: auth,
            api: api,
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let authorization = Task { await model.reauthorize(metrics: [.readiness]) }
        try? await Task.sleep(for: .milliseconds(20))
        let queuedRefresh = Task { await model.refreshNow(metrics: [.readiness]) }
        try? await Task.sleep(for: .milliseconds(20))

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
        let api = SnapshotStub(results: [.success(delayed)], delay: .seconds(30))
        let probe = AuthorizationProbe(delay: .milliseconds(1))
        let model = AppViewModel(
            auth: auth,
            api: api,
            now: { now },
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let refresh = Task { await model.refreshNow(metrics: [.readiness]) }
        try? await Task.sleep(for: .milliseconds(20))
        let queuedAuthorization = Task { await model.reauthorize(metrics: [.readiness]) }
        try? await Task.sleep(for: .milliseconds(20))

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
        let probe = AuthorizationProbe(delay: .seconds(30))
        let api = SnapshotStub(results: [])
        let model = AppViewModel(
            auth: auth,
            api: api,
            authorizationHandler: { scopes in try await probe.run(scopes: scopes) },
            checkConnectionOnInit: false
        )

        let first = Task { await model.reauthorize(metrics: [.readiness]) }
        let second = Task { await model.reauthorize(metrics: [.readiness]) }
        try? await Task.sleep(for: .milliseconds(30))
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
        let probe = AuthorizationProbe(delay: .milliseconds(75))
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

        async let first: Void = model.connect(
            clientID: "client",
            clientSecret: "secret",
            metrics: [.readiness]
        )
        async let second: Void = model.connect(
            clientID: "client",
            clientSecret: "secret",
            metrics: [.readiness]
        )
        _ = await (first, second)

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

    @Test func hiddenMetricsDoNotProduceNetworkRequests() async throws {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            switch request.url?.lastPathComponent {
            case "daily_readiness":
                return Self.response(request, 200, #"{"data":[{"day":"2026-09-26","score":72}]}"#)
            case "ring_battery_level":
                return Self.response(request, 200, #"{"data":[{"level":90}]}"#)
            default:
                return Self.response(request, 500, "unexpected endpoint")
            }
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        _ = try await api.fetchSnapshot(
            metrics: [.readiness],
            now: Date(timeIntervalSince1970: 1_790_467_200)
        )

        let paths = Set(recorder.requests.compactMap(\.url?.lastPathComponent))
        #expect(paths == ["daily_readiness", "ring_battery_level"])
        #expect(!paths.contains("daily_resilience"))
        #expect(!paths.contains("heartrate"))
    }

    @Test func partialEndpointFailureReturnsAvailableDataAndPlaceholder() async throws {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            switch request.url?.lastPathComponent {
            case "daily_readiness":
                return Self.response(request, 200, #"{"data":[{"day":"2026-09-26","score":72}]}"#)
            case "daily_activity":
                return Self.response(request, 503, #"{"detail":"maintenance"}"#)
            case "ring_battery_level":
                return Self.response(request, 200, #"{"data":[]}"#)
            default:
                return Self.response(request, 500, "unexpected")
            }
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        let snapshot = try await api.fetchSnapshot(metrics: [.readiness, .activity], now: Date())

        #expect(snapshot.readings[.readiness]?.score == 72)
        #expect(snapshot.readings[.activity]?.detail == "Unavailable")
        #expect(snapshot.readings[.activity]?.availability == .unavailable)
    }

    @Test func malformedPayloadIsReportedWhenNoUsableDataExists() async {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            Self.response(request, 200, #"{"unexpected":true}"#)
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        await #expect(throws: RingStatsError.malformedData) {
            try await api.fetchSnapshot(metrics: [.readiness], now: Date())
        }
    }

    @Test func cancelledHealthRequestPropagatesCancellation() async {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { _ in throw URLError(.cancelled) }
        let api = OuraAPI(auth: auth, session: recorder.session)

        await #expect(throws: CancellationError.self) {
            try await api.fetchSnapshot(metrics: [.readiness], now: Date())
        }
    }

    @Test func unauthorizedResponseRefreshesTokenOnceAndRetries() async throws {
        let auth = AccessTokenStub(tokens: ["expired", "fresh"])
        let recorder = CoreRequestRecorder { request in
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired" {
                return Self.response(request, 401, #"{"detail":"expired"}"#)
            }
            switch request.url?.lastPathComponent {
            case "daily_sleep":
                return Self.response(request, 200, #"{"data":[{"day":"2026-09-26","score":84}]}"#)
            default:
                return Self.response(request, 200, #"{"data":[]}"#)
            }
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        let snapshot = try await api.fetchSnapshot(metrics: [.sleep], now: Date())

        #expect(snapshot.readings[.sleep]?.score == 84)
        #expect(await auth.forceRefreshes == 1)
    }

    @Test func secondUnauthorizedResponseInvalidatesRefreshedTokenDurably() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(accessToken: "old", refreshToken: "refresh", expiresAt: .distantFuture),
            account: "oauth-token"
        )
        let recorder = CoreRequestRecorder { request in
            if request.url?.path == "/oauth/token" {
                return Self.response(
                    request,
                    200,
                    #"{"access_token":"fresh","refresh_token":"next","expires_in":3600}"#
                )
            }
            return Self.response(request, 401, #"{"detail":"unauthorized"}"#)
        }
        let client = OAuthClient(store: store, session: recorder.session)
        let api = OuraAPI(auth: client, session: recorder.session)

        await #expect(throws: RingStatsError.authenticationRequired) {
            try await api.fetchSnapshot(metrics: [.sleep], now: Date())
        }

        #expect(await client.isConfigured)
        #expect(!(await client.isConnected))
        #expect(try store.load(StoredOAuthAuthorization.self, account: "oauth-authorization") == .empty)
        #expect(try store.load(OAuthToken.self, account: "oauth-token") == nil)
        let restarted = OAuthClient(store: store, session: recorder.session)
        #expect(await restarted.isConfigured)
        #expect(!(await restarted.isConnected))
    }

    @Test func forbiddenResponseBecomesPermissionPlaceholderWhenOtherDataExists() async throws {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            if request.url?.lastPathComponent == "daily_stress" {
                return Self.response(request, 403, #"{"detail":"scope"}"#)
            }
            return Self.response(request, 200, #"{"data":[{"level":80}]}"#)
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        let snapshot = try await api.fetchSnapshot(metrics: [.stress], now: Date())

        #expect(snapshot.battery?.level == 80)
        #expect(snapshot.readings[.stress]?.detail == "Permission required")
        #expect(snapshot.readings[.stress]?.availability == .permissionRequired)
    }

    @Test func rateLimitIncludesRetryAfter() async {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            Self.response(request, 429, #"{"detail":"slow down"}"#, headers: ["Retry-After": "45"])
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        await #expect(throws: RingStatsError.rateLimited(retryAfter: 45)) {
            try await api.fetchSnapshot(metrics: [], now: Date())
        }
    }

    @Test func scopesAreDerivedFromEnabledMetricsAndBattery() {
        #expect(OuraScope.required(for: [.heartRate]) == [.heartRate, .ringConfiguration])
        #expect(
            OuraScope.required(for: [.readiness, .stress])
                == [.daily, .stress, .ringConfiguration]
        )
    }

    @Test func snapshotKeepsSourceFreshnessAndSortsTimestamps() async throws {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            switch request.url?.lastPathComponent {
            case "daily_readiness":
                return Self.response(request, 200, #"{"data":[{"day":"2026-09-25","score":72}]}"#)
            case "heartrate":
                return Self.response(
                    request,
                    200,
                    #"{"data":[{"timestamp":"2026-09-26T09:00:00Z","bpm":70,"source":"awake"},{"timestamp":"2026-09-26T10:00:00Z","bpm":80,"source":"awake"}]}"#
                )
            case "daily_stress":
                return Self.response(
                    request,
                    200,
                    #"{"data":[{"day":"2026-09-25","day_summary":"restored","stress_high":600},{"day":"2026-09-26"}]}"#
                )
            case "ring_battery_level":
                return Self.response(
                    request,
                    200,
                    #"{"data":[{"level":40,"timestamp":"2026-09-26T08:00:00Z"},{"level":90,"timestamp":"2026-09-26T11:00:00Z"}]}"#
                )
            default:
                return Self.response(request, 500, "unexpected")
            }
        }
        let api = OuraAPI(auth: auth, session: recorder.session)
        let now = ISO8601DateFormatter().date(from: "2026-09-26T12:00:00Z")!

        let snapshot = try await api.fetchSnapshot(
            metrics: [.readiness, .heartRate, .stress],
            now: now
        )

        #expect(snapshot.readings[.readiness]?.sourceDay == "2026-09-25")
        #expect(snapshot.readings[.readiness]?.detail?.contains("2026-09-25") == true)
        #expect(snapshot.readings[.heartRate]?.value == "80")
        #expect(snapshot.readings[.heartRate]?.observedAt == ISO8601DateFormatter().date(from: "2026-09-26T10:00:00Z"))
        #expect(snapshot.readings[.stress]?.sourceDay == "2026-09-25")
        #expect(snapshot.battery?.level == 90)
    }

    @Test func resilienceIgnoresNewestRecordWithoutLevel() async throws {
        let auth = AccessTokenStub(tokens: ["access"])
        let recorder = CoreRequestRecorder { request in
            switch request.url?.lastPathComponent {
            case "daily_resilience":
                return Self.response(
                    request,
                    200,
                    #"{"data":[{"day":"2026-09-25","level":"solid"},{"day":"2026-09-26","level":null}]}"#
                )
            case "ring_battery_level":
                return Self.response(request, 200, #"{"data":[]}"#)
            default:
                return Self.response(request, 500, "unexpected")
            }
        }
        let api = OuraAPI(auth: auth, session: recorder.session)

        let snapshot = try await api.fetchSnapshot(metrics: [.resilience], now: Date())

        #expect(snapshot.readings[.resilience]?.value == "Solid")
        #expect(snapshot.readings[.resilience]?.sourceDay == "2026-09-25")
    }

    @Test func failedReauthorizationExchangeKeepsExistingToken() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(
                accessToken: "working-token",
                refreshToken: "working-refresh",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
            account: "oauth-token"
        )
        let recorder = CoreRequestRecorder { request in
            Self.response(request, 400, #"{"error":"invalid_grant"}"#)
        }
        let client = OAuthClient(store: store, session: recorder.session)

        await #expect(throws: RingStatsError.authorizationRestartRequired) {
            try await client.exchange(code: "cancelled-or-invalid")
        }

        #expect(try await client.accessToken(forceRefresh: false) == "working-token")
        #expect(
            try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            )?.token?.accessToken == "working-token"
        )
    }

    @Test func authenticationFailureDoesNotExposeUpstreamResponseBody() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        let recorder = CoreRequestRecorder { request in
            Self.response(
                request,
                503,
                "<html>internal diagnostic: request-id-private</html>"
            )
        }
        let client = OAuthClient(store: store, session: recorder.session)

        do {
            try await client.exchange(code: "temporary-code")
            Issue.record("Expected the token exchange to fail.")
        } catch let error as RingStatsError {
            #expect(error.localizedDescription == "Oura authentication failed (HTTP 503).")
            #expect(!error.localizedDescription.contains("request-id-private"))
        }
    }

    @Test func cancelledTokenExchangePropagatesCancellation() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        let recorder = CoreRequestRecorder { _ in throw URLError(.cancelled) }
        let client = OAuthClient(store: store, session: recorder.session)

        await #expect(throws: CancellationError.self) {
            try await client.exchange(code: "temporary-code")
        }
    }

    @Test func tokenExchangeClassifiesInvalidClientWithoutExposingDescription() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "wrong", clientSecret: "wrong"),
            account: "client-credentials"
        )
        let recorder = CoreRequestRecorder { request in
            Self.response(
                request,
                401,
                #"{"error":"invalid_client","error_description":"private upstream detail"}"#
            )
        }
        let client = OAuthClient(store: store, session: recorder.session)

        do {
            try await client.exchange(code: "temporary-code")
            Issue.record("Expected invalid client credentials.")
        } catch let error as RingStatsError {
            #expect(error == .invalidClientCredentials)
            #expect(!error.localizedDescription.contains("private upstream detail"))
        }
    }

    @Test func concurrentExpiredTokenRequestsShareOneRefresh() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(
                accessToken: "expired",
                refreshToken: "refresh",
                expiresAt: .distantPast
            ),
            account: "oauth-token"
        )
        let recorder = CoreRequestRecorder { request in
            Thread.sleep(forTimeInterval: 0.05)
            return Self.response(
                request,
                200,
                #"{"access_token":"fresh","refresh_token":"next","expires_in":3600}"#
            )
        }
        let client = OAuthClient(store: store, session: recorder.session)

        async let first = client.accessToken(forceRefresh: false)
        async let second = client.accessToken(forceRefresh: false)
        let values = try await [first, second]

        #expect(values == ["fresh", "fresh"])
        #expect(recorder.requests.count == 1)
    }

    @Test func rejectedTokenRefreshDurablyExpiresAuthorizationButKeepsCredentials() async throws {
        let store = CoreMemoryCredentialStore()
        let credentials = ClientCredentials(clientID: "client", clientSecret: "secret")
        try store.save(credentials, account: "client-credentials")
        try store.save(
            OAuthToken(accessToken: "expired", refreshToken: "invalid", expiresAt: .distantPast),
            account: "oauth-token"
        )
        let recorder = CoreRequestRecorder { request in
            Self.response(request, 400, #"{"error":"invalid_grant"}"#)
        }
        let client = OAuthClient(store: store, session: recorder.session)

        await #expect(throws: RingStatsError.authenticationRequired) {
            try await client.accessToken(forceRefresh: false)
        }

        #expect(await client.isConfigured)
        #expect(!(await client.isConnected))
        #expect(try store.load(StoredOAuthAuthorization.self, account: "oauth-authorization") == .empty)
        #expect(try store.load(OAuthToken.self, account: "oauth-token") == nil)
        #expect(try store.load(ClientCredentials.self, account: "client-credentials") == credentials)

        let restarted = OAuthClient(store: store, session: recorder.session)
        #expect(await restarted.isConfigured)
        #expect(!(await restarted.isConnected))
    }

    @Test func failedOldTokenRevocationIsPersistedAndRetried() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture),
            account: "oauth-token"
        )
        let revocations = LockedInt()
        let recorder = CoreRequestRecorder { request in
            if request.url?.path == "/oauth/token" {
                return Self.response(
                    request,
                    200,
                    #"{"access_token":"new","refresh_token":"new-refresh","expires_in":3600}"#
                )
            }
            let attempt = revocations.increment()
            return Self.response(request, attempt == 1 ? 503 : 200, "")
        }
        let client = OAuthClient(store: store, session: recorder.session)

        try await client.exchange(code: "valid")
        #expect(try await client.accessToken(forceRefresh: false) == "new")
        try? await Task.sleep(for: .milliseconds(50))

        #expect(revocations.value == 2)
        #expect(
            try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            )?.pendingRevocationAccessTokens.isEmpty == true
        )
    }

    @Test func multipleFailedRevocationsRemainQueuedUntilEachSucceeds() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture),
            account: "oauth-token"
        )
        let exchanges = LockedInt()
        let revocations = LockedInt()
        let recorder = CoreRequestRecorder { request in
            if request.url?.path == "/oauth/token" {
                let index = exchanges.increment()
                return Self.response(
                    request,
                    200,
                    """
                    {"access_token":"new-\(index)","refresh_token":"refresh-\(index)","expires_in":3600}
                    """
                )
            }
            let attempt = revocations.increment()
            return Self.response(request, attempt <= 3 ? 503 : 200, "")
        }
        let client = OAuthClient(store: store, session: recorder.session)

        try await client.exchange(code: "first")
        try await client.exchange(code: "second")
        #expect(
            try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            )?.pendingRevocationAccessTokens == ["old", "new-1"]
        )

        for _ in 0..<5 {
            #expect(try await client.accessToken(forceRefresh: false) == "new-2")
            try? await Task.sleep(for: .milliseconds(30))
            if try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            )?.pendingRevocationAccessTokens.isEmpty == true {
                break
            }
        }
        #expect(
            try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            )?.pendingRevocationAccessTokens.isEmpty == true
        )

        let revokedTokens: Set<String> = Set(recorder.requests.compactMap { request -> String? in
            guard request.url?.path == "/oauth/revoke" else { return nil }
            return URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "access_token" })?.value
        })
        #expect(revokedTokens == ["old", "new-1"])
    }

    @Test func inFlightRevocationRetryDoesNotDropNewlyQueuedToken() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture),
            account: "oauth-token"
        )
        let exchanges = LockedInt()
        let recorder = CoreRequestRecorder { request in
            if request.url?.path == "/oauth/token" {
                let index = exchanges.increment()
                return Self.response(
                    request,
                    200,
                    """
                    {"access_token":"new-\(index)","refresh_token":"refresh-\(index)","expires_in":3600}
                    """
                )
            }
            Thread.sleep(forTimeInterval: 0.075)
            return Self.response(request, 503, "")
        }
        let client = OAuthClient(store: store, session: recorder.session)

        try await client.exchange(code: "first")
        try? await Task.sleep(for: .milliseconds(15))
        try await client.exchange(code: "second")
        try? await Task.sleep(for: .milliseconds(100))

        #expect(
            try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            )?.pendingRevocationAccessTokens == ["old", "new-1"]
        )
    }

    @Test func authorizationUsesNumericLoopbackCallback() async throws {
        let store = CoreMemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        let recorder = CoreRequestRecorder { request in
            Self.response(request, 500, "unused")
        }
        let client = OAuthClient(store: store, session: recorder.session)
        let url = try await client.authorizationRequest(state: "state", scopes: [.daily])
        let redirect = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "redirect_uri" })?.value
        let scope = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "scope" })?.value
        #expect(redirect == "http://127.0.0.1:43828/oauth/callback")
        #expect(scope == "daily")
    }

    @Test func credentialLoadFailureIsSurfacedInsteadOfTreatedAsSignedOut() async {
        let recorder = CoreRequestRecorder { request in Self.response(request, 500, "unused") }
        let client = OAuthClient(
            store: CoreFailingCredentialStore(),
            session: recorder.session
        )

        #expect(await client.startupError != nil)
        await #expect(throws: RingStatsError.self) {
            try await client.accessToken(forceRefresh: false)
        }
    }

    @Test func disconnectCanClearUnreadableSavedCredentials() async throws {
        let store = CoreInitiallyUnreadableCredentialStore()
        let recorder = CoreRequestRecorder { request in Self.response(request, 500, "unused") }
        let client = OAuthClient(store: store, session: recorder.session)

        #expect(await client.startupError != nil)
        #expect(await client.isConfigured)

        try await client.disconnect()

        #expect(await client.startupError == nil)
        #expect(!(await client.isConfigured))
        #expect(store.deletedAccounts == [
            "client-credentials",
            "oauth-token",
            "pending-revocation-access-token",
        ])
    }

    @Test func emptyAuthorizationTombstonePreventsLegacyTokenResurrection() async throws {
        let store = CoreLegacyDeletionFailingStore()
        try store.save(
            ClientCredentials(clientID: "client", clientSecret: "secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(accessToken: "legacy", refreshToken: "refresh", expiresAt: .distantFuture),
            account: "oauth-token"
        )
        store.failLegacyTokenDeletion = true
        let recorder = CoreRequestRecorder { request in Self.response(request, 200, "") }
        let client = OAuthClient(store: store, session: recorder.session)

        #expect(await client.isConnected)
        try await client.invalidateAuthorization()
        #expect(try store.load(StoredOAuthAuthorization.self, account: "oauth-authorization") == .empty)
        #expect(try store.load(OAuthToken.self, account: "oauth-token")?.accessToken == "legacy")

        let restarted = OAuthClient(store: store, session: recorder.session)
        #expect(await restarted.isConfigured)
        #expect(!(await restarted.isConnected))
        #expect(try store.load(StoredOAuthAuthorization.self, account: "oauth-authorization") == .empty)
    }

    private static func response(
        _ request: URLRequest,
        _ status: Int,
        _ body: String,
        headers: [String: String]? = nil
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return (response, Data(body.utf8))
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private actor SnapshotStub: SnapshotFetching {
    private var results: [Result<HealthSnapshot, RingStatsError>]
    private let delay: Duration?
    private(set) var requestedMetrics: [Set<Metric>] = []

    init(results: [Result<HealthSnapshot, RingStatsError>], delay: Duration? = nil) {
        self.results = results
        self.delay = delay
    }

    var callCount: Int { requestedMetrics.count }

    func fetchSnapshot(metrics: Set<Metric>, now: Date) async throws -> HealthSnapshot {
        requestedMetrics.append(metrics)
        if let delay { try await Task.sleep(for: delay) }
        guard !results.isEmpty else { throw RingStatsError.server("No stub result.") }
        return try results.removeFirst().get()
    }
}

private actor AuthorizationProbe {
    private let delay: Duration
    private(set) var callCount = 0
    private(set) var wasCancelled = false

    init(delay: Duration) { self.delay = delay }

    func run(scopes: Set<OuraScope>) async throws {
        _ = scopes
        callCount += 1
        do {
            try await Task.sleep(for: delay)
        } catch {
            wasCancelled = true
            throw error
        }
    }
}

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}

private actor AuthStub: OAuthServicing {
    var startupError: RingStatsError?
    private(set) var isConfigured: Bool
    private(set) var isConnected: Bool

    init(configured: Bool, connected: Bool, startupError: RingStatsError? = nil) {
        self.isConfigured = configured
        self.isConnected = connected
        self.startupError = startupError
    }

    func configure(_ credentials: ClientCredentials) async throws { isConfigured = true }
    func disconnect() async throws { isConfigured = false; isConnected = false }
    func exchange(code: String) async throws { isConnected = true }
    func accessToken(forceRefresh: Bool) async throws -> String { "access" }
    func invalidateAuthorization() async throws { isConnected = false }

    func authorizationRequest(state: String, scopes: Set<OuraScope>) async throws -> URL {
        var components = URLComponents(string: "https://cloud.ouraring.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "scope", value: scopes.map(\.rawValue).sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}

private actor AccessTokenStub: AccessTokenProviding {
    private var tokens: [String]
    private(set) var forceRefreshes = 0

    init(tokens: [String]) { self.tokens = tokens }

    func accessToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh { forceRefreshes += 1 }
        guard !tokens.isEmpty else { throw RingStatsError.notConnected }
        if forceRefresh {
            if tokens.count > 1 { tokens.removeFirst() }
            return tokens[0]
        }
        return tokens[0]
    }

    func invalidateAuthorization() async throws {
        tokens = []
    }
}

private final class CoreMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T? {
        guard let data = lock.withLock({ values[account] }) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        lock.withLock { values[account] = data }
    }

    func delete(account: String) throws {
        lock.withLock { values[account] = nil }
    }
}

private struct CoreFailingCredentialStore: CredentialStoring {
    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T? {
        throw RingStatsError.credentialStore("Unreadable test store.")
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {
        throw RingStatsError.credentialStore("Unwritable test store.")
    }

    func delete(account: String) throws {
        throw RingStatsError.credentialStore("Undeletable test store.")
    }
}

private final class CoreInitiallyUnreadableCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var deletions = Set<String>()

    var deletedAccounts: Set<String> { lock.withLock { deletions } }

    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T? {
        throw RingStatsError.credentialStore("Unreadable test store.")
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {}

    func delete(account: String) throws {
        _ = lock.withLock { deletions.insert(account) }
    }
}

private final class CoreLegacyDeletionFailingStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var shouldFailLegacyTokenDeletion = false

    var failLegacyTokenDeletion: Bool {
        get { lock.withLock { shouldFailLegacyTokenDeletion } }
        set { lock.withLock { shouldFailLegacyTokenDeletion = newValue } }
    }

    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T? {
        guard let data = lock.withLock({ values[account] }) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        lock.withLock { values[account] = data }
    }

    func delete(account: String) throws {
        if account == "oauth-token", failLegacyTokenDeletion {
            throw RingStatsError.credentialStore("Simulated legacy alias deletion failure.")
        }
        lock.withLock { values[account] = nil }
    }
}

private final class CoreRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private let response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    init(response: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        self.response = response
    }

    var requests: [URLRequest] { lock.withLock { recordedRequests } }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CoreURLProtocol.self]
        CoreURLProtocol.install { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            self.lock.withLock { self.recordedRequests.append(request) }
            return try self.response(request)
        }
        return URLSession(configuration: configuration)
    }
}

private final class CoreURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static func install(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.withLock { self.handler = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
