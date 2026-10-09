import Foundation
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

extension HTTPStubbedTests {
    /// Health endpoint fetching, snapshot assembly, and failure classification.
    @Suite struct OuraAPITests {
        @Test func hiddenMetricsDoNotProduceNetworkRequests() async throws {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { request in
                switch request.url?.lastPathComponent {
                case "daily_readiness":
                    return stubResponse(request, 200, #"{"data":[{"day":"2026-09-26","score":72}]}"#)
                case "ring_battery_level":
                    return stubResponse(request, 200, #"{"data":[{"level":90}]}"#)
                default:
                    return stubResponse(request, 500, "unexpected endpoint")
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
            let recorder = HTTPStubRecorder { request in
                switch request.url?.lastPathComponent {
                case "daily_readiness":
                    return stubResponse(request, 200, #"{"data":[{"day":"2026-09-26","score":72}]}"#)
                case "daily_activity":
                    return stubResponse(request, 503, #"{"detail":"maintenance"}"#)
                case "ring_battery_level":
                    return stubResponse(request, 200, #"{"data":[]}"#)
                default:
                    return stubResponse(request, 500, "unexpected")
                }
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            let snapshot = try await api.fetchSnapshot(metrics: [.readiness, .activity], now: Date())

            #expect(snapshot.readings[.readiness]?.score == 72)
            #expect(snapshot.readings[.activity]?.detail == "Unavailable")
            #expect(snapshot.readings[.activity]?.availability == .unavailable)
            #expect(snapshot.failedMetrics.keys.contains(.activity))
            #expect(!snapshot.failedMetrics.keys.contains(.readiness))
            #expect(snapshot.batteryFailure == nil)
        }

        @Test func batteryPermissionFailureIsClassifiedAsPermission() async throws {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { request in
                if request.url?.lastPathComponent == "ring_battery_level" {
                    return stubResponse(request, 403, #"{"detail":"scope"}"#)
                }
                return stubResponse(request, 200, #"{"data":[{"day":"2026-09-26","score":72}]}"#)
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            let snapshot = try await api.fetchSnapshot(metrics: [.readiness], now: Date())

            #expect(snapshot.batteryFailure == .insufficientScope)
            #expect(snapshot.batteryNeedsPermission)
            #expect(!snapshot.hasTransientFailures)
        }

        @Test func emptyEndpointIsNoDataRatherThanFailure() async throws {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { request in
                switch request.url?.lastPathComponent {
                case "daily_readiness":
                    return stubResponse(request, 200, #"{"data":[{"day":"2026-09-26","score":72}]}"#)
                case "daily_sleep":
                    return stubResponse(request, 200, #"{"data":[]}"#)
                case "ring_battery_level":
                    return stubResponse(request, 503, "")
                default:
                    return stubResponse(request, 500, "unexpected")
                }
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            let snapshot = try await api.fetchSnapshot(metrics: [.readiness, .sleep], now: Date())

            #expect(snapshot.readings[.sleep]?.availability == .noData)
            #expect(snapshot.readings[.sleep]?.detail == "Not published")
            #expect(snapshot.failedMetrics.isEmpty)
            #expect(snapshot.batteryFailure != nil)
        }

        @Test func malformedPayloadIsReportedWhenNoUsableDataExists() async {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { request in
                stubResponse(request, 200, #"{"unexpected":true}"#)
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            await #expect(throws: RingStatsError.malformedData) {
                try await api.fetchSnapshot(metrics: [.readiness], now: Date())
            }
        }

        @Test func cancelledHealthRequestPropagatesCancellation() async {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { _ in throw URLError(.cancelled) }
            let api = OuraAPI(auth: auth, session: recorder.session)

            await #expect(throws: CancellationError.self) {
                try await api.fetchSnapshot(metrics: [.readiness], now: Date())
            }
        }

        @Test func unauthorizedResponseRefreshesTokenOnceAndRetries() async throws {
            let auth = AccessTokenStub(tokens: ["expired", "fresh"])
            let recorder = HTTPStubRecorder { request in
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired" {
                    return stubResponse(request, 401, #"{"detail":"expired"}"#)
                }
                switch request.url?.lastPathComponent {
                case "daily_sleep":
                    return stubResponse(request, 200, #"{"data":[{"day":"2026-09-26","score":84}]}"#)
                default:
                    return stubResponse(request, 200, #"{"data":[]}"#)
                }
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            let snapshot = try await api.fetchSnapshot(metrics: [.sleep], now: Date())

            #expect(snapshot.readings[.sleep]?.score == 84)
            #expect(await auth.forceRefreshes == 1)
        }

        @Test func secondUnauthorizedResponseInvalidatesRefreshedTokenDurably() async throws {
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            try store.save(
                OAuthToken(accessToken: "old", refreshToken: "refresh", expiresAt: .distantFuture),
                account: "oauth-token"
            )
            let recorder = HTTPStubRecorder { request in
                if request.url?.path == "/oauth/token" {
                    return stubResponse(
                        request,
                        200,
                        #"{"access_token":"fresh","refresh_token":"next","expires_in":3600}"#
                    )
                }
                return stubResponse(request, 401, #"{"detail":"unauthorized"}"#)
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
            let recorder = HTTPStubRecorder { request in
                if request.url?.lastPathComponent == "daily_stress" {
                    return stubResponse(request, 403, #"{"detail":"scope"}"#)
                }
                return stubResponse(request, 200, #"{"data":[{"level":80}]}"#)
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            let snapshot = try await api.fetchSnapshot(metrics: [.stress], now: Date())

            #expect(snapshot.battery?.level == 80)
            #expect(snapshot.readings[.stress]?.detail == "Needs access")
            #expect(snapshot.batteryFailure == nil)
            #expect(snapshot.readings[.stress]?.availability == .permissionRequired)
        }

        @Test func rateLimitIncludesRetryAfter() async {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { request in
                stubResponse(request, 429, #"{"detail":"slow down"}"#, headers: ["Retry-After": "45"])
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
            let recorder = HTTPStubRecorder { request in
                switch request.url?.lastPathComponent {
                case "daily_readiness":
                    return stubResponse(request, 200, #"{"data":[{"day":"2026-09-25","score":72}]}"#)
                case "heartrate":
                    return stubResponse(
                        request,
                        200,
                        #"{"data":[{"timestamp":"2026-09-26T09:00:00Z","bpm":70,"source":"awake"},{"timestamp":"2026-09-26T10:00:00Z","bpm":80,"source":"awake"}]}"#
                    )
                case "daily_stress":
                    return stubResponse(
                        request,
                        200,
                        #"{"data":[{"day":"2026-09-25","day_summary":"restored","stress_high":600},{"day":"2026-09-26"}]}"#
                    )
                case "ring_battery_level":
                    return stubResponse(
                        request,
                        200,
                        #"{"data":[{"level":40,"timestamp":"2026-09-26T08:00:00Z"},{"level":90,"timestamp":"2026-09-26T11:00:00Z"}]}"#
                    )
                default:
                    return stubResponse(request, 500, "unexpected")
                }
            }
            let api = OuraAPI(auth: auth, session: recorder.session)
            let now = ISO8601DateFormatter().date(from: "2026-09-26T12:00:00Z")!

            let snapshot = try await api.fetchSnapshot(
                metrics: [.readiness, .heartRate, .stress],
                now: now
            )

            #expect(snapshot.readings[.readiness]?.sourceDay == "2026-09-25")
            #expect(snapshot.readings[.readiness]?.detail == "Good")
            #expect(snapshot.readings[.heartRate]?.value == "80")
            #expect(snapshot.readings[.heartRate]?.observedAt == ISO8601DateFormatter().date(from: "2026-09-26T10:00:00Z"))
            #expect(snapshot.readings[.stress]?.sourceDay == "2026-09-25")
            #expect(snapshot.battery?.level == 90)
        }

        @Test func resilienceIgnoresNewestRecordWithoutLevel() async throws {
            let auth = AccessTokenStub(tokens: ["access"])
            let recorder = HTTPStubRecorder { request in
                switch request.url?.lastPathComponent {
                case "daily_resilience":
                    return stubResponse(
                        request,
                        200,
                        #"{"data":[{"day":"2026-09-25","level":"solid"},{"day":"2026-09-26","level":null}]}"#
                    )
                case "ring_battery_level":
                    return stubResponse(request, 200, #"{"data":[]}"#)
                default:
                    return stubResponse(request, 500, "unexpected")
                }
            }
            let api = OuraAPI(auth: auth, session: recorder.session)

            let snapshot = try await api.fetchSnapshot(metrics: [.resilience], now: Date())

            #expect(snapshot.readings[.resilience]?.value == "Solid")
            #expect(snapshot.readings[.resilience]?.sourceDay == "2026-09-25")
        }
    }
}
