import Foundation
import Network
import Security
import Testing
@testable import RingStats
@testable import RingStatsCore
@testable import RingStatsOura

@Suite(.serialized)
struct InfrastructureSecurityTests {
    private struct TestSecret: Codable, Equatable, Sendable {
        let value: String
    }

    @Test func keychainRoundTripUsesPreferredStoreAndDeletesCleanly() throws {
        let service = "com.digitaltableteur.ringstats.tests.\(UUID().uuidString)"
        let account = "integration-secret"
        let store = KeychainCredentialStore(service: service)
        defer { try? store.delete(account: account) }

        try store.save(TestSecret(value: "first"), account: account)
        #expect(try store.load(TestSecret.self, account: account) == TestSecret(value: "first"))

        try store.save(TestSecret(value: "updated"), account: account)
        #expect(try store.load(TestSecret.self, account: account) == TestSecret(value: "updated"))

        try store.delete(account: account)
        #expect(try store.load(TestSecret.self, account: account) == nil)
    }

    @Test func keychainMigratesLegacyItemIntoDataProtectionKeychain() throws {
        let service = "com.digitaltableteur.ringstats.tests.\(UUID().uuidString)"
        let account = "legacy-secret"
        let store = KeychainCredentialStore(service: service)
        defer { try? store.delete(account: account) }

        let secret = TestSecret(value: "migrate-me")
        var query = Self.keychainQuery(
            service: service,
            account: account,
            useDataProtectionKeychain: false
        )
        query[kSecValueData as String] = try JSONEncoder().encode(secret)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainTestError.status(addStatus)
        }

        #expect(try store.load(TestSecret.self, account: account) == secret)
        try store.delete(account: account)
        #expect(try store.load(TestSecret.self, account: account) == nil)
    }

    @Test func keychainDecodeFailuresAreSurfaced() throws {
        let service = "com.digitaltableteur.ringstats.tests.\(UUID().uuidString)"
        let account = "corrupt-secret"
        let store = KeychainCredentialStore(service: service)
        defer { try? store.delete(account: account) }

        var query = Self.keychainQuery(
            service: service,
            account: account,
            useDataProtectionKeychain: false
        )
        query[kSecValueData as String] = Data("not-json".utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainTestError.status(addStatus) }

        #expect(throws: DecodingError.self) {
            _ = try store.load(TestSecret.self, account: account)
        }
    }

    @Test func compatibleKeychainReadRetriesPlaintextResidueCleanup() throws {
        let service = "com.digitaltableteur.ringstats.tests.\(UUID().uuidString)"
        let account = "cleanup-secret"
        let legacyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ring-stats-legacy-\(UUID().uuidString)", isDirectory: true)
        let legacyFile = legacyDirectory.appendingPathComponent("\(account).json")
        let store = KeychainCredentialStore(
            service: service,
            legacyDirectory: legacyDirectory
        )
        defer {
            try? store.delete(account: account)
            try? FileManager.default.removeItem(at: legacyDirectory)
        }

        let secret = TestSecret(value: "keychain-wins")
        let encoded = try JSONEncoder().encode(secret)
        var query = Self.keychainQuery(
            service: service,
            account: account,
            useDataProtectionKeychain: false
        )
        query[kSecValueData as String] = encoded
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainTestError.status(addStatus) }

        try FileManager.default.createDirectory(
            at: legacyDirectory,
            withIntermediateDirectories: true
        )
        try encoded.write(to: legacyFile, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: legacyFile.path))

        #expect(try store.load(TestSecret.self, account: account) == secret)
        #expect(!FileManager.default.fileExists(atPath: legacyFile.path))
    }

    @Test func networkSessionUsesExplicitFiniteTimeouts() {
        let configuration = NetworkSessionFactory.ephemeral().configuration
        #expect(configuration.timeoutIntervalForRequest == NetworkSessionFactory.requestTimeout)
        #expect(configuration.timeoutIntervalForResource == NetworkSessionFactory.resourceTimeout)
        #expect(configuration.timeoutIntervalForRequest == 30)
        #expect(configuration.timeoutIntervalForResource == 60)
    }

    @Test func callbackServerAcceptsFragmentedHeaders() async throws {
        let server = CallbackServer(expectedState: "fragment-state")
        try await server.start()
        let waiter = Task { try await server.waitForCallback() }

        let response = try await Self.sendRequestFragments([
            "GET /oauth/callback?code=abc&state=fragment-state HTTP/1.1\r\nHo",
            "st: 127.0.0.1:43828\r\nUser-Agent: Integration-Test\r\n",
            "\r\n",
        ])
        let callback = try await waiter.value

        #expect(callback.path == "/oauth/callback")
        #expect(URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value == "abc")
        #expect(response.contains("200 OK"))
    }

    @Test func callbackServerDuplicateStartSharesOneListener() async throws {
        let server = CallbackServer(expectedState: "duplicate-state")
        async let first: Void = server.start()
        async let second: Void = server.start()
        _ = try await (first, second)

        let waiter = Task { try await server.waitForCallback() }
        _ = try await Self.sendRequestFragments([
            "GET /oauth/callback?code=abc&state=duplicate-state HTTP/1.1\r\n",
            "Host: localhost:43828\r\n\r\n",
        ])
        #expect(try await waiter.value.path == "/oauth/callback")
    }

    @Test func strayAndInvalidConnectionsDoNotEndCallbackFlow() async throws {
        let server = CallbackServer(expectedState: "eventual-state")
        try await server.start()
        let waiter = Task { try await server.waitForCallback() }

        try await Self.openAndCancelConnection()
        let invalidResponse = try await Self.sendRequestFragments([
            "GET /oauth/callback?code=bad&state=wrong HTTP/1.1\r\n",
            "Host: localhost:43828\r\n\r\n",
        ])
        #expect(invalidResponse.contains("400 Bad Request"))

        let validResponse = try await Self.sendRequestFragments([
            "GET /oauth/callback?code=good&state=eventual-state HTTP/1.1\r\n",
            "Host: 127.0.0.1:43828\r\n\r\n",
        ])
        let callback = try await waiter.value

        #expect(validResponse.contains("200 OK"))
        #expect(callback.host == "127.0.0.1")
        #expect(URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value == "good")
    }

    /// A browser opening `http://localhost:43828` may connect over IPv6, so the
    /// callback must arrive over `::1` too.
    @Test func callbackArrivesOverIPv6LoopbackForLocalhost() async throws {
        let server = CallbackServer(expectedState: "ipv6-state")
        try await server.start()
        let waiter = Task { try await server.waitForCallback() }

        let response = try await Self.sendRequestFragments([
            "GET /oauth/callback?code=v6&state=ipv6-state HTTP/1.1\r\n",
            "Host: localhost:43828\r\n\r\n",
        ], host: "::1")
        let callback = try await waiter.value

        #expect(response.contains("200 OK"))
        #expect(URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value == "v6")
    }

    @Test func cancellingCallbackWaitStopsListenerAndUnblocksWaiter() async throws {
        let server = CallbackServer(expectedState: "cancel-state")
        try await server.start()
        let waiter = Task { try await server.waitForCallback() }
        waiter.cancel()

        do {
            _ = try await waiter.value
            Issue.record("Cancelled callback wait unexpectedly returned a URL")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, received \(error)")
        }

        await server.cancel()
    }

    private static func keychainQuery(
        service: String,
        account: String,
        useDataProtectionKeychain: Bool
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: useDataProtectionKeychain,
        ]
    }

    private static func sendRequestFragments(_ fragments: [String], host: String = "127.0.0.1") async throws -> String {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: 43_828)!,
            using: .tcp
        )
        let queue = DispatchQueue(label: "local.ringstats.tests.callback-client")
        try await withCheckedThrowingContinuation { continuation in
            let gate = OneShotGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resumeOnce { continuation.resume() }
                case .failed(let error):
                    gate.resumeOnce { continuation.resume(throwing: error) }
                case .cancelled:
                    gate.resumeOnce { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        for fragment in fragments {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                connection.send(
                    content: Data(fragment.utf8),
                    completion: .contentProcessed { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                )
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
                data,
                _,
                _,
                error in
                defer { connection.cancel() }
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: response)
                } else {
                    continuation.resume(throwing: CallbackTestError.missingResponse)
                }
            }
        }
    }

    private static func openAndCancelConnection() async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 43_828)!,
            using: .tcp
        )
        let queue = DispatchQueue(label: "local.ringstats.tests.stray-callback-client")
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            let gate = OneShotGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resumeOnce {
                        connection.cancel()
                        continuation.resume()
                    }
                case .failed(let error):
                    gate.resumeOnce { continuation.resume(throwing: error) }
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }
}

private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resumeOnce(_ body: () -> Void) {
        let shouldResume = lock.withLock {
            guard !resumed else { return false }
            resumed = true
            return true
        }
        if shouldResume { body() }
    }
}

private enum KeychainTestError: Error {
    case status(OSStatus)
}

private enum CallbackTestError: Error {
    case missingResponse
}
