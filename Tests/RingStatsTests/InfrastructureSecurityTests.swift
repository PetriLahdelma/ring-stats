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

    /// While authorization waits, no other socket may take the callback port
    /// on either loopback address, even with the reuse options a hostile
    /// process would set. Network.framework's loopback listener failed this
    /// for 127.0.0.1.
    @Test(arguments: [false, true])
    func listenerHoldsBothLoopbackAddressesExclusively(ipv6: Bool) async throws {
        let server = CallbackServer(expectedState: "exclusive-state")
        try await server.start()
        defer { Task { await server.cancel() } }
        for (reuseAddress, reusePort) in [(false, false), (true, false), (false, true), (true, true)] {
            let result = Self.competingBind(ipv6: ipv6, reuseAddress: reuseAddress, reusePort: reusePort)
            #expect(result == EADDRINUSE, "\(ipv6 ? "::1" : "127.0.0.1") reuseaddr=\(reuseAddress) reuseport=\(reusePort) bound")
        }
        await server.cancel()
    }

    /// If another process already holds the callback port on either loopback
    /// address, authorization must not start.
    @Test(arguments: [false, true])
    func startFailsWhenEitherLoopbackAddressIsTaken(ipv6: Bool) async throws {
        let holder = try #require(Self.listeningSocket(ipv6: ipv6))
        defer { close(holder) }
        let server = CallbackServer(expectedState: "taken-state")
        await #expect(throws: (any Error).self) { try await server.start() }
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

    /// Tries to bind the callback port the way another process would and
    /// returns 0 on success or the errno.
    private static func competingBind(ipv6: Bool, reuseAddress: Bool, reusePort: Bool) -> Int32 {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, IPPROTO_TCP)
        defer { close(fd) }
        var one: Int32 = 1
        if reuseAddress { setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size)) }
        if reusePort { setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, socklen_t(MemoryLayout<Int32>.size)) }
        return bindLoopback(fd, ipv6: ipv6) == 0 ? 0 : errno
    }

    private static func listeningSocket(ipv6: Bool) -> Int32? {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, IPPROTO_TCP)
        // Earlier tests leave the port in TIME_WAIT.
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        guard bindLoopback(fd, ipv6: ipv6) == 0, listen(fd, 1) == 0 else { close(fd); return nil }
        return fd
    }

    private static func bindLoopback(_ fd: Int32, ipv6: Bool) -> Int32 {
        if ipv6 {
            var one: Int32 = 1
            setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = OAuthLoopback.port.bigEndian
            address.sin6_addr = in6addr_loopback
            return withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = OAuthLoopback.port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
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
