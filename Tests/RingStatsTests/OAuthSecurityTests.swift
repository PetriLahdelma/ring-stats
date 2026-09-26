import Foundation
import Testing
@testable import RingStats

@Suite(.serialized)
struct OAuthSecurityTests {
    @Test func defaultNetworkSessionDoesNotPersistHealthOrOAuthResponses() {
        let configuration = NetworkSessionFactory.ephemeral().configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func callbackServerAcceptsOnlyExpectedLoopbackRequest() {
        let valid = "GET /oauth/callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost:43828\r\n\r\n"
        #expect(CallbackServer.validatedCallbackURL(from: valid, expectedState: "xyz")?.path == "/oauth/callback")

        let wrongHost = "GET /oauth/callback?code=abc&state=xyz HTTP/1.1\r\nHost: attacker.invalid\r\n\r\n"
        #expect(CallbackServer.validatedCallbackURL(from: wrongHost, expectedState: "xyz") == nil)

        let wrongPath = "GET /not-the-callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost:43828\r\n\r\n"
        #expect(CallbackServer.validatedCallbackURL(from: wrongPath, expectedState: "xyz") == nil)

        let wrongMethod = "POST /oauth/callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost:43828\r\n\r\n"
        #expect(CallbackServer.validatedCallbackURL(from: wrongMethod, expectedState: "xyz") == nil)

        let wrongState = "GET /oauth/callback?code=abc&state=wrong HTTP/1.1\r\nHost: localhost:43828\r\n\r\n"
        #expect(CallbackServer.validatedCallbackURL(from: wrongState, expectedState: "xyz") == nil)
    }

    @Test func authorizationCodeUsesOnlyDocumentedTokenEndpoint() async throws {
        let store = MemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client-id", clientSecret: "client-secret"),
            account: "client-credentials"
        )
        let recorder = RequestRecorder { request in
            #expect(request.url?.absoluteString == "https://api.ouraring.com/oauth/token")
            #expect(request.httpMethod == "POST")
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
            #expect(request.value(forHTTPHeaderField: "Cache-Control") == "no-store")
            return Self.response(
                for: request,
                status: 200,
                body: #"{"access_token":"access","refresh_token":"refresh","expires_in":3600}"#
            )
        }
        let client = OAuthClient(store: store, session: recorder.session)

        try await client.exchange(code: "authorization-code")

        #expect(recorder.requests.count == 1)
        let authorization = try store.load(
            StoredOAuthAuthorization.self,
            account: "oauth-authorization"
        )
        #expect(authorization?.token?.accessToken == "access")
    }

    @Test func disconnectRevokesTokenAndDeletesAllOAuthSecrets() async throws {
        let store = try Self.seededStore()
        let recorder = RequestRecorder { request in
            #expect(request.url?.scheme == "https")
            #expect(request.url?.host == "api.ouraring.com")
            #expect(request.url?.path == "/oauth/revoke")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.first(where: { $0.name == "access_token" })?.value == "access")
            return Self.response(for: request, status: 200, body: "")
        }
        let client = OAuthClient(store: store, session: recorder.session)

        try await client.disconnect()

        #expect(recorder.requests.count == 1)
        #expect(try store.load(StoredOAuthAuthorization.self, account: "oauth-authorization") == nil)
        #expect(try store.load(OAuthToken.self, account: "oauth-token") == nil)
        #expect(try store.load(ClientCredentials.self, account: "client-credentials") == nil)
        #expect(await !client.isConnected)
        #expect(await !client.isConfigured)
    }

    @Test func disconnectDeletesLocalSecretsEvenWhenRemoteRevocationFails() async throws {
        let store = try Self.seededStore()
        let recorder = RequestRecorder { request in
            Self.response(for: request, status: 503, body: "temporarily unavailable")
        }
        let client = OAuthClient(store: store, session: recorder.session)

        var revocationFailed = false
        do {
            try await client.disconnect()
        } catch {
            revocationFailed = true
        }

        #expect(revocationFailed)
        #expect(try store.load(StoredOAuthAuthorization.self, account: "oauth-authorization") == nil)
        #expect(try store.load(OAuthToken.self, account: "oauth-token") == nil)
        #expect(try store.load(ClientCredentials.self, account: "client-credentials") == nil)
        #expect(await !client.isConnected)
        #expect(await !client.isConfigured)
    }

    private static func seededStore() throws -> MemoryCredentialStore {
        let store = MemoryCredentialStore()
        try store.save(
            ClientCredentials(clientID: "client-id", clientSecret: "client-secret"),
            account: "client-credentials"
        )
        try store.save(
            OAuthToken(
                accessToken: "access",
                refreshToken: "refresh",
                expiresAt: Date().addingTimeInterval(3_600)
            ),
            account: "oauth-token"
        )
        return store
    }

    private static func response(
        for request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(body.utf8))
    }
}

private final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) throws -> T? {
        let data = lock.withLock { storage[account] }
        guard let data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func save<T: Encodable & Sendable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        lock.withLock { storage[account] = data }
    }

    func delete(account: String) throws {
        lock.withLock { storage[account] = nil }
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private let response: @Sendable (URLRequest) -> (HTTPURLResponse, Data)

    init(response: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        self.response = response
    }

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.install { [weak self] request in
            guard let self else {
                throw URLError(.cancelled)
            }
            self.lock.withLock { self.recordedRequests.append(request) }
            return self.response(request)
        }
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

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
