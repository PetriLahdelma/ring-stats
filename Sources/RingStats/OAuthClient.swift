import AppKit
import Foundation

protocol AccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
    func invalidateAuthorization() async throws
}

protocol OAuthServicing: AccessTokenProviding {
    var startupError: RingStatsError? { get async }
    var isConfigured: Bool { get async }
    var isConnected: Bool { get async }
    func configure(_ credentials: ClientCredentials) async throws
    func disconnect() async throws
    func authorizationRequest(state: String, scopes: Set<OuraScope>) async throws -> URL
    func exchange(code: String) async throws
}

struct StoredOAuthAuthorization: Codable, Sendable, Equatable {
    var token: OAuthToken?
    var pendingRevocationAccessTokens: Set<String>

    static let empty = StoredOAuthAuthorization(
        token: nil,
        pendingRevocationAccessTokens: []
    )
}

actor OAuthClient: OAuthServicing {
    private enum GrantContext: Equatable {
        case authorizationCode
        case refreshToken
    }

    static let callbackURL = OAuthLoopback.callbackURL
    static let authorizationURL = URL(string: "https://cloud.ouraring.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://api.ouraring.com/oauth/token")!
    static let revocationURL = URL(string: "https://api.ouraring.com/oauth/revoke")!

    private let store: any CredentialStoring
    private let session: URLSession
    private var authorization: StoredOAuthAuthorization
    private var credentials: ClientCredentials?
    private var loadError: RingStatsError?
    private var refreshTask: Task<OAuthToken, any Error>?
    private var revocationRetryTask: Task<Void, Never>?
    private var revocationRetryRequested = false

    init(
        store: any CredentialStoring = KeychainCredentialStore(),
        session: URLSession = NetworkSessionFactory.ephemeral()
    ) {
        self.store = store
        self.session = session
        do {
            self.credentials = try store.load(ClientCredentials.self, account: "client-credentials")
            if let stored = try store.load(
                StoredOAuthAuthorization.self,
                account: "oauth-authorization"
            ) {
                self.authorization = stored
                // The atomic item is authoritative, including when it is an
                // empty tombstone. Retry removal of legacy aliases without ever
                // importing them over this state.
                try? store.delete(account: "oauth-token")
                try? store.delete(account: "pending-revocation-access-token")
            } else {
                let migrated = StoredOAuthAuthorization(
                    token: try store.load(OAuthToken.self, account: "oauth-token"),
                    pendingRevocationAccessTokens: try store.load(
                        Set<String>.self,
                        account: "pending-revocation-access-token"
                    ) ?? []
                )
                self.authorization = migrated
                if migrated.token != nil || !migrated.pendingRevocationAccessTokens.isEmpty {
                    try store.save(migrated, account: "oauth-authorization")
                    try? store.delete(account: "oauth-token")
                    try? store.delete(account: "pending-revocation-access-token")
                }
            }
            self.loadError = nil
        } catch {
            self.authorization = .empty
            self.credentials = nil
            self.loadError = .credentialStore(
                "Saved credentials could not be read securely. \(error.localizedDescription)"
            )
        }
    }

    var startupError: RingStatsError? { loadError }
    var isConfigured: Bool { credentials != nil || loadError != nil }
    var isConnected: Bool { authorization.token != nil }

    func configure(_ credentials: ClientCredentials) throws {
        try ensureStoreLoaded()
        try store.save(credentials, account: "client-credentials")
        self.credentials = credentials
    }

    /// Revokes remote access and removes every locally saved OAuth secret.
    func disconnect() async throws {
        try await removeAuthorization(deleteCredentials: true)
        loadError = nil
    }

    func authorizationRequest(
        state: String,
        scopes: Set<OuraScope> = OuraScope.required(for: Set(Metric.defaultVisible))
    ) throws -> URL {
        try ensureStoreLoaded()
        guard let credentials else { throw RingStatsError.notConfigured }
        var components = URLComponents(url: Self.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL),
            URLQueryItem(name: "scope", value: scopes.map(\.rawValue).sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw RingStatsError.invalidResponse }
        return url
    }

    func exchange(code: String) async throws {
        try ensureStoreLoaded()
        try Task.checkCancellation()
        guard let credentials else { throw RingStatsError.notConfigured }
        let previousAccessToken = authorization.token?.accessToken
        let response = try await tokenRequest(
            parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.callbackURL,
            ],
            credentials: credentials,
            context: .authorizationCode
        )
        try Task.checkCancellation()
        let newToken = response.token()
        var updatedAuthorization = authorization
        updatedAuthorization.token = newToken
        if let previousAccessToken, previousAccessToken != newToken.accessToken {
            updatedAuthorization.pendingRevocationAccessTokens.insert(previousAccessToken)
        }
        // Commit the replacement token and every cleanup obligation in one
        // Keychain item so a partial write cannot orphan the previous token.
        try persistAuthorization(updatedAuthorization)
        schedulePendingRevocationRetry()
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        try ensureStoreLoaded()
        schedulePendingRevocationRetry()
        guard var current = authorization.token else { throw RingStatsError.notConnected }
        if current.needsRefresh || forceRefresh {
            guard let credentials else { throw RingStatsError.notConfigured }
            if let refreshTask {
                current = try await refreshTask.value
                var updatedAuthorization = authorization
                updatedAuthorization.token = current
                try persistAuthorization(updatedAuthorization)
                return current.accessToken
            }
            let refreshToken = current.refreshToken
            let task = Task { [self] in
                let response = try await tokenRequest(
                    parameters: [
                        "grant_type": "refresh_token",
                        "refresh_token": refreshToken,
                    ],
                    credentials: credentials,
                    context: .refreshToken
                )
                return response.token()
            }
            refreshTask = task
            do {
                current = try await task.value
                var updatedAuthorization = authorization
                updatedAuthorization.token = current
                try persistAuthorization(updatedAuthorization)
                refreshTask = nil
            } catch {
                refreshTask = nil
                if error as? RingStatsError == .authenticationRequired {
                    var updatedAuthorization = authorization
                    updatedAuthorization.token = nil
                    do {
                        try persistAuthorization(updatedAuthorization)
                    } catch {
                        throw RingStatsError.credentialStore(
                            "The expired authorization could not be removed securely. \(error.localizedDescription)"
                        )
                    }
                }
                throw error
            }
        }
        return current.accessToken
    }

    func invalidateAuthorization() throws {
        refreshTask?.cancel()
        refreshTask = nil
        var updatedAuthorization = authorization
        updatedAuthorization.token = nil
        do {
            try persistAuthorization(updatedAuthorization)
        } catch {
            throw RingStatsError.credentialStore(
                "The invalid authorization could not be removed securely. \(error.localizedDescription)"
            )
        }
    }

    private func tokenRequest(
        parameters: [String: String],
        credentials: ClientCredentials,
        context: GrantContext
    ) async throws -> TokenResponse {
        let result = try await request(Self.tokenURL, parameters: parameters, credentials: credentials)
        guard (200..<300).contains(result.status) else {
            if result.status == 400 || result.status == 401 {
                let oauthCode = try? JSONDecoder().decode(
                    OAuthErrorResponse.self,
                    from: result.data
                ).error
                switch oauthCode {
                case "invalid_client", "unauthorized_client":
                    throw RingStatsError.invalidClientCredentials
                case "invalid_scope":
                    throw RingStatsError.invalidRequestedScope
                case "invalid_grant":
                    throw context == .refreshToken
                        ? RingStatsError.authenticationRequired
                        : RingStatsError.authorizationRestartRequired
                default:
                    throw context == .refreshToken
                        ? RingStatsError.authenticationRequired
                        : RingStatsError.authorizationRestartRequired
                }
            }
            if result.status == 429 {
                throw RingStatsError.rateLimited(retryAfter: nil)
            }
            throw RingStatsError.server("Oura authentication failed (HTTP \(result.status)).")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: result.data)
        } catch {
            throw RingStatsError.malformedData
        }
    }

    private func ensureStoreLoaded() throws {
        if let loadError { throw loadError }
    }

    private func persistAuthorization(_ updated: StoredOAuthAuthorization) throws {
        // Persist the empty state as a non-secret tombstone. Removing it could
        // let an undeletable legacy alias resurrect an invalidated token after
        // restart.
        try store.save(updated, account: "oauth-authorization")
        authorization = updated
    }

    private func removeAuthorization(deleteCredentials: Bool) async throws {
        let pendingRetry = revocationRetryTask
        pendingRetry?.cancel()
        await pendingRetry?.value
        revocationRetryTask = nil
        revocationRetryRequested = false

        var revocationError: (any Error)?
        let accessTokens = authorization.pendingRevocationAccessTokens.union(
            authorization.token.map { [$0.accessToken] } ?? []
        )
        for accessToken in accessTokens {
            do {
                try await revoke(accessToken: accessToken)
            } catch {
                revocationError = revocationError ?? error
            }
        }

        var storageError: (any Error)?
        do {
            try persistAuthorization(.empty)
        } catch {
            storageError = error
        }
        if deleteCredentials { credentials = nil }

        do {
            try store.delete(account: "oauth-token")
            try store.delete(account: "pending-revocation-access-token")
        } catch {
            storageError = storageError ?? error
        }
        if deleteCredentials {
            do {
                try store.delete(account: "client-credentials")
            } catch {
                storageError = storageError ?? error
            }
        }

        if let storageError { throw storageError }
        if let revocationError { throw revocationError }
    }

    private func retryPendingRevocations() async {
        guard !authorization.pendingRevocationAccessTokens.isEmpty else { return }
        let tokensToAttempt = authorization.pendingRevocationAccessTokens.sorted()
        for accessToken in tokensToAttempt {
            do {
                try await revoke(accessToken: accessToken)
                var updatedAuthorization = authorization
                updatedAuthorization.pendingRevocationAccessTokens.remove(accessToken)
                try persistAuthorization(updatedAuthorization)
            } catch {
                // Keep this token queued while allowing other pending tokens to
                // be retried independently.
            }
        }
    }

    private func schedulePendingRevocationRetry() {
        guard !authorization.pendingRevocationAccessTokens.isEmpty else { return }
        if revocationRetryTask != nil {
            revocationRetryRequested = true
            return
        }
        revocationRetryTask = Task { [weak self] in
            guard let self else { return }
            await self.retryPendingRevocations()
            await self.clearFinishedRevocationRetry()
        }
    }

    private func clearFinishedRevocationRetry() {
        revocationRetryTask = nil
        guard revocationRetryRequested else { return }
        revocationRetryRequested = false
        schedulePendingRevocationRetry()
    }

    private func revoke(accessToken: String) async throws {
        var components = URLComponents(url: Self.revocationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "access_token", value: accessToken)]
        guard let url = components.url else { throw RingStatsError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw RingStatsError.timedOut
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw RingStatsError.transport("Could not reach Oura. Check your internet connection and try again.")
        }
        guard let http = response as? HTTPURLResponse else { throw RingStatsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw RingStatsError.server("Oura token revocation failed (HTTP \(http.statusCode)).")
        }
    }

    private func request(
        _ url: URL,
        parameters: [String: String],
        credentials: ClientCredentials
    ) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = parameters
        fields["client_id"] = credentials.clientID
        fields["client_secret"] = credentials.clientSecret
        request.httpBody = fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key.percentEncoded)=\(value.percentEncoded)"
        }.joined(separator: "&").data(using: .utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw RingStatsError.timedOut
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw RingStatsError.transport("Could not reach Oura. Check your internet connection and try again.")
        }
        guard let http = response as? HTTPURLResponse else { throw RingStatsError.invalidResponse }
        return (data, http.statusCode)
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
}

private extension String {
    var percentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
