import Foundation
import Testing
@testable import RingStats

/// Parent for suites that install handlers on the process-wide HTTPStubProtocol.
/// Serializing them together keeps one suite's handler from answering another's
/// requests.
@Suite(.serialized) struct HTTPStubbedTests {}

/// Builds an HTTP response for the stubbed URL loading system.
func stubResponse(
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

final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Date

    init(_ value: Date) { storedValue = value }

    var value: Date {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

actor SnapshotStub: SnapshotFetching {
    private var results: [Result<HealthSnapshot, RingStatsError>]
    private let holdsFirstCall: Bool
    private(set) var requestedMetrics: [Set<Metric>] = []
    /// Opens when the first call arrives. Only meaningful with `holdsFirstCall`.
    nonisolated let started = Gate()
    /// Lets a held first call continue. Cancelling the caller also ends the hold.
    nonisolated let release = Gate()

    init(results: [Result<HealthSnapshot, RingStatsError>], holdsFirstCall: Bool = false) {
        self.results = results
        self.holdsFirstCall = holdsFirstCall
    }

    var callCount: Int { requestedMetrics.count }

    func fetchSnapshot(metrics: Set<Metric>, now: Date) async throws -> HealthSnapshot {
        requestedMetrics.append(metrics)
        if holdsFirstCall, requestedMetrics.count == 1 {
            started.open()
            await release.wait()
            try Task.checkCancellation()
        }
        guard !results.isEmpty else { throw RingStatsError.server("No stub result.") }
        return try results.removeFirst().get()
    }
}

actor AuthorizationProbe {
    private let holds: Bool
    private(set) var callCount = 0
    private(set) var wasCancelled = false
    nonisolated let started = Gate()
    nonisolated let release = Gate()

    /// With `holds`, each run waits for `release` or cancellation before finishing.
    init(holds: Bool = true) { self.holds = holds }

    func run(scopes: Set<OuraScope>) async throws {
        _ = scopes
        callCount += 1
        started.open()
        guard holds else { return }
        await release.wait()
        if Task.isCancelled {
            wasCancelled = true
            throw CancellationError()
        }
    }
}

final class LockedInt: @unchecked Sendable {
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

actor AuthStub: OAuthServicing {
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

actor AccessTokenStub: AccessTokenProviding {
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

final class TestCredentialStore: CredentialStoring, @unchecked Sendable {
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

struct FailingCredentialStore: CredentialStoring {
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

final class InitiallyUnreadableCredentialStore: CredentialStoring, @unchecked Sendable {
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

final class LegacyDeletionFailingStore: CredentialStoring, @unchecked Sendable {
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

final class HTTPStubRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []
    private let response: @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    init(response: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)) {
        self.response = response
    }

    var requests: [URLRequest] { lock.withLock { recordedRequests } }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPStubProtocol.self]
        HTTPStubProtocol.install { [weak self] request in
            guard let self else { throw URLError(.cancelled) }
            self.lock.withLock { self.recordedRequests.append(request) }
            return try self.response(request)
        }
        return URLSession(configuration: configuration)
    }
}

/// CFRunLoopPerformBlock and CFRunLoopWakeUp are safe to call from any thread.
private struct RunLoopReference: @unchecked Sendable {
    let runLoop: CFRunLoop

    init(_ runLoop: CFRunLoop) { self.runLoop = runLoop }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}

final class HTTPStubProtocol: URLProtocol, @unchecked Sendable {
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

    private let stateLock = NSLock()
    private var isStopped = false

    // Every custom URLProtocol in a process shares one loading thread. Handlers
    // run on a background queue so a test can hold one request without
    // freezing the others; results return on the loading thread's run loop.
    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let request = self.request
        let loadingThread = RunLoopReference(CFRunLoopGetCurrent())
        DispatchQueue.global().async { [self] in
            let result = Result { try handler(request) }
            loadingThread.perform { [self] in deliver(result) }
        }
    }

    private func deliver(_ result: Result<(HTTPURLResponse, Data), any Error>) {
        guard !stateLock.withLock({ isStopped }) else { return }
        switch result {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        stateLock.withLock { isStopped = true }
    }
}

/// A one-shot signal. Tests wait on it instead of sleeping for a guessed
/// duration. `wait()` returns once the gate opens or the waiting task is
/// cancelled, so a held operation still honours cancellation.
final class Gate: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func open() { continuation.finish() }

    func wait() async {
        for await _ in stream {}
    }
}

/// Yields until `condition` holds. The bound only turns a hang into a
/// failure; success never depends on how long anything takes.
@MainActor
func waitUntil(
    _ description: String = "condition",
    maxYields: Int = 100_000,
    _ condition: () async -> Bool
) async {
    for _ in 0..<maxYields {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(description).")
}

/// Waits for work that finishes on another thread, such as a URL loading
/// callback. It polls a condition rather than sleeping for a fixed interval.
func eventually(
    _ description: String = "condition",
    timeout: Duration = .seconds(5),
    _ condition: @Sendable () async throws -> Bool
) async rethrows {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if try await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for \(description).")
}

/// Blocks stubbed HTTP handlers, which run synchronously on URL loading
/// threads, until the test releases them.
final class HTTPHold: @unchecked Sendable {
    private let condition = NSCondition()
    private var isReleased = false
    private var enteredCount = 0
    private var activeCount = 0

    var entered: Int { condition.withLock { enteredCount } }
    var active: Int { condition.withLock { activeCount } }

    /// Call from a handler. Returns after `release()`.
    func hold() {
        condition.lock()
        enteredCount += 1
        activeCount += 1
        while !isReleased { condition.wait() }
        condition.unlock()
    }

    /// Call from a handler after `hold()` once its response is ready.
    func leave() {
        condition.withLock { activeCount -= 1 }
    }

    func release() {
        condition.withLock {
            isReleased = true
            condition.broadcast()
        }
    }
}
