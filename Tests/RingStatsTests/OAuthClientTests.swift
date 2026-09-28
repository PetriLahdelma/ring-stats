import Foundation
import Testing
@testable import RingStats

extension HTTPStubbedTests {
    /// Token exchange, refresh, revocation, and credential persistence.
    @Suite struct OAuthClientTests {
        @Test func failedReauthorizationExchangeKeepsExistingToken() async throws {
            let store = TestCredentialStore()
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
            let recorder = HTTPStubRecorder { request in
                stubResponse(request, 400, #"{"error":"invalid_grant"}"#)
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
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            let recorder = HTTPStubRecorder { request in
                stubResponse(
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
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            let recorder = HTTPStubRecorder { _ in throw URLError(.cancelled) }
            let client = OAuthClient(store: store, session: recorder.session)

            await #expect(throws: CancellationError.self) {
                try await client.exchange(code: "temporary-code")
            }
        }

        @Test func tokenExchangeClassifiesInvalidClientWithoutExposingDescription() async throws {
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "wrong", clientSecret: "wrong"),
                account: "client-credentials"
            )
            let recorder = HTTPStubRecorder { request in
                stubResponse(
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
            let store = TestCredentialStore()
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
            let hold = HTTPHold()
            let recorder = HTTPStubRecorder { request in
                hold.hold()
                defer { hold.leave() }
                return stubResponse(
                    request,
                    200,
                    #"{"access_token":"fresh","refresh_token":"next","expires_in":3600}"#
                )
            }
            let client = OAuthClient(store: store, session: recorder.session)

            // The first refresh is held open on the wire while the second caller
            // arrives, so the second must join it rather than start its own.
            let first = Task { try await client.accessToken(forceRefresh: false) }
            await eventually("first refresh to reach the token endpoint") { hold.entered == 1 }
            let second = Task { try await client.accessToken(forceRefresh: false) }
            await eventually("second caller to join the in-flight refresh") {
                await client.refreshWaiterCount == 1
            }
            hold.release()
            let values = try await [first.value, second.value]

            #expect(values == ["fresh", "fresh"])
            #expect(recorder.requests.count == 1)
        }

        @Test func rejectedTokenRefreshDurablyExpiresAuthorizationButKeepsCredentials() async throws {
            let store = TestCredentialStore()
            let credentials = ClientCredentials(clientID: "client", clientSecret: "secret")
            try store.save(credentials, account: "client-credentials")
            try store.save(
                OAuthToken(accessToken: "expired", refreshToken: "invalid", expiresAt: .distantPast),
                account: "oauth-token"
            )
            let recorder = HTTPStubRecorder { request in
                stubResponse(request, 400, #"{"error":"invalid_grant"}"#)
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
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            try store.save(
                OAuthToken(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture),
                account: "oauth-token"
            )
            let revocations = LockedInt()
            let recorder = HTTPStubRecorder { request in
                if request.url?.path == "/oauth/token" {
                    return stubResponse(
                        request,
                        200,
                        #"{"access_token":"new","refresh_token":"new-refresh","expires_in":3600}"#
                    )
                }
                let attempt = revocations.increment()
                return stubResponse(request, attempt == 1 ? 503 : 200, "")
            }
            let client = OAuthClient(store: store, session: recorder.session)

            try await client.exchange(code: "valid")
            #expect(try await client.accessToken(forceRefresh: false) == "new")
            try await eventually("queued revocation to be retried") {
                try revocations.value == 2 && store.load(
                    StoredOAuthAuthorization.self,
                    account: "oauth-authorization"
                )?.pendingRevocationAccessTokens.isEmpty == true
            }
            await client.waitForRevocationRetries()

            #expect(revocations.value == 2)
        }

        @Test func multipleFailedRevocationsRemainQueuedUntilEachSucceeds() async throws {
            let store = TestCredentialStore()
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
            let recorder = HTTPStubRecorder { request in
                if request.url?.path == "/oauth/token" {
                    let index = exchanges.increment()
                    return stubResponse(
                        request,
                        200,
                        """
                        {"access_token":"new-\(index)","refresh_token":"refresh-\(index)","expires_in":3600}
                        """
                    )
                }
                let attempt = revocations.increment()
                return stubResponse(request, attempt <= 3 ? 503 : 200, "")
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

            // Each token access retries queued revocations in the background.
            try await eventually("every queued revocation to succeed") {
                #expect(try await client.accessToken(forceRefresh: false) == "new-2")
                return try store.load(
                    StoredOAuthAuthorization.self,
                    account: "oauth-authorization"
                )?.pendingRevocationAccessTokens.isEmpty == true
            }
            #expect(
                try store.load(
                    StoredOAuthAuthorization.self,
                    account: "oauth-authorization"
                )?.pendingRevocationAccessTokens.isEmpty == true
            )

            await client.waitForRevocationRetries()
            let revokedTokens: Set<String> = Set(recorder.requests.compactMap { request -> String? in
                guard request.url?.path == "/oauth/revoke" else { return nil }
                return URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "access_token" })?.value
            })
            #expect(revokedTokens == ["old", "new-1"])
        }

        @Test func inFlightRevocationRetryDoesNotDropNewlyQueuedToken() async throws {
            let hold = HTTPHold()
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            try store.save(
                OAuthToken(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantFuture),
                account: "oauth-token"
            )
            let exchanges = LockedInt()
            let recorder = HTTPStubRecorder { request in
                if request.url?.path == "/oauth/token" {
                    let index = exchanges.increment()
                    return stubResponse(
                        request,
                        200,
                        """
                        {"access_token":"new-\(index)","refresh_token":"refresh-\(index)","expires_in":3600}
                        """
                    )
                }
                hold.hold()
                defer { hold.leave() }
                return stubResponse(request, 503, "")
            }
            let client = OAuthClient(store: store, session: recorder.session)

            // Keep the first revocation retry in flight while a second exchange
            // queues another token, then let every revocation fail.
            try await client.exchange(code: "first")
            await eventually("revocation retry to start") { hold.entered >= 1 }
            try await client.exchange(code: "second")
            hold.release()
            await client.waitForRevocationRetries()

            #expect(
                try store.load(
                    StoredOAuthAuthorization.self,
                    account: "oauth-authorization"
                )?.pendingRevocationAccessTokens == ["old", "new-1"]
            )
        }

        @Test func authorizationUsesNumericLoopbackCallback() async throws {
            let store = TestCredentialStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            let recorder = HTTPStubRecorder { request in
                stubResponse(request, 500, "unused")
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
            let recorder = HTTPStubRecorder { request in stubResponse(request, 500, "unused") }
            let client = OAuthClient(
                store: FailingCredentialStore(),
                session: recorder.session
            )

            #expect(await client.startupError != nil)
            await #expect(throws: RingStatsError.self) {
                try await client.accessToken(forceRefresh: false)
            }
        }

        @Test func disconnectCanClearUnreadableSavedCredentials() async throws {
            let store = InitiallyUnreadableCredentialStore()
            let recorder = HTTPStubRecorder { request in stubResponse(request, 500, "unused") }
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
            let store = LegacyDeletionFailingStore()
            try store.save(
                ClientCredentials(clientID: "client", clientSecret: "secret"),
                account: "client-credentials"
            )
            try store.save(
                OAuthToken(accessToken: "legacy", refreshToken: "refresh", expiresAt: .distantFuture),
                account: "oauth-token"
            )
            store.failLegacyTokenDeletion = true
            let recorder = HTTPStubRecorder { request in stubResponse(request, 200, "") }
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
    }
}
