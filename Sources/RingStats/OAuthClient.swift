import AppKit
import Foundation

actor OAuthClient {
    static let callbackURL = "http://localhost:43828/oauth/callback"
    static let authorizationURL = URL(string: "https://cloud.ouraring.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://api.ouraring.com/oauth/token")!
    static let revocationURL = URL(string: "https://api.ouraring.com/oauth/revoke")!

    private let store: any CredentialStoring
    private let session: URLSession
    private var token: OAuthToken?
    private var credentials: ClientCredentials?

    init(
        store: any CredentialStoring = KeychainCredentialStore(),
        session: URLSession = NetworkSessionFactory.ephemeral()
    ) {
        self.store = store
        self.session = session
        self.token = try? store.load(OAuthToken.self, account: "oauth-token")
        self.credentials = try? store.load(ClientCredentials.self, account: "client-credentials")
    }

    var isConfigured: Bool { credentials != nil }
    var isConnected: Bool { token != nil }

    func configure(_ credentials: ClientCredentials) throws {
        try store.save(credentials, account: "client-credentials")
        self.credentials = credentials
    }

    /// Revokes the current authorization while retaining the developer
    /// application's client credentials for an immediate OAuth reauthorization.
    func clearAuthorization() async throws {
        try await removeAuthorization(deleteCredentials: false)
    }

    /// Revokes remote access and removes every locally saved OAuth secret.
    func disconnect() async throws {
        try await removeAuthorization(deleteCredentials: true)
    }

    func authorizationRequest(state: String) throws -> URL {
        guard let credentials else { throw RingStatsError.notConfigured }
        var components = URLComponents(url: Self.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.callbackURL),
            URLQueryItem(name: "scope", value: "daily heartrate stress ring_configuration"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw RingStatsError.invalidResponse }
        return url
    }

    func exchange(code: String) async throws {
        guard let credentials else { throw RingStatsError.notConfigured }
        let response = try await tokenRequest(parameters: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.callbackURL,
        ], credentials: credentials)
        let newToken = response.token()
        try store.save(newToken, account: "oauth-token")
        token = newToken
    }

    func accessToken() async throws -> String {
        guard var current = token else { throw RingStatsError.notConnected }
        if current.needsRefresh {
            guard let credentials else { throw RingStatsError.notConfigured }
            let response = try await tokenRequest(parameters: [
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
            ], credentials: credentials)
            current = response.token()
            try store.save(current, account: "oauth-token")
            token = current
        }
        return current.accessToken
    }

    private func tokenRequest(parameters: [String: String], credentials: ClientCredentials) async throws -> TokenResponse {
        let result = try await request(Self.tokenURL, parameters: parameters, credentials: credentials)
        guard (200..<300).contains(result.status) else { throw RingStatsError.server(result.message) }
        return try JSONDecoder().decode(TokenResponse.self, from: result.data)
    }

    private func removeAuthorization(deleteCredentials: Bool) async throws {
        var revocationError: (any Error)?
        if let accessToken = token?.accessToken {
            do {
                try await revoke(accessToken: accessToken)
            } catch {
                revocationError = error
            }
        }

        token = nil
        if deleteCredentials { credentials = nil }

        var storageError: (any Error)?
        do {
            try store.delete(account: "oauth-token")
        } catch {
            storageError = error
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

    private func revoke(accessToken: String) async throws {
        var components = URLComponents(url: Self.revocationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "access_token", value: accessToken)]
        guard let url = components.url else { throw RingStatsError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RingStatsError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Oura token revocation failed."
            throw RingStatsError.server(message)
        }
    }

    private func request(_ url: URL, parameters: [String: String], credentials: ClientCredentials) async throws -> (data: Data, status: Int, message: String) {
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
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RingStatsError.invalidResponse }
        let message = String(data: data, encoding: .utf8) ?? "Oura authentication failed."
        return (data, http.statusCode, message)
    }
}

private extension String {
    var percentEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
