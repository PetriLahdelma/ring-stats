import Foundation

package enum OAuthLoopback {
    package static let host = "127.0.0.1"
    package static let port: UInt16 = 43_828
    package static let path = "/oauth/callback"
    package static let origin = "http://\(host):\(port)"
    /// The redirect URI new connections register. Oura's developer portal
    /// accepts plain http only for `localhost`.
    package static let callbackURL = "http://localhost:\(port)\(path)"
    /// The numeric redirect URI registered by connections made before Oura
    /// required `localhost`. Credentials saved then keep using it.
    package static let legacyCallbackURL = "\(origin)\(path)"
    package static let acceptedHostHeaders = ["\(host):\(port)", "localhost:\(port)"]
}

package actor CallbackServer {
    private static let maximumHeaderBytes = 16_384

    private let expectedState: String
    private let queue = DispatchQueue(label: "local.ringstats.oauth-callback")
    private var sockets: [Int32] = []
    private var sources: [DispatchSourceRead] = []
    private let clients: CallbackClients
    private var callbackContinuation: CheckedContinuation<URL, any Error>?
    private var bufferedResult: Result<URL, any Error>?

    package init(expectedState: String, headerDeadline: DispatchTimeInterval = CallbackClients.headerDeadline) {
        self.expectedState = expectedState
        self.clients = CallbackClients(queue: queue, headerDeadline: headerDeadline)
    }

    /// Connections still sending headers. Tests read it.
    var openClientCount: Int { clients.count }

    /// Opens the callback listener on `127.0.0.1` and `::1`.
    ///
    /// Each address gets its own BSD socket, bound to that exact address with
    /// no `SO_REUSEPORT` and the IPv6 one set to IPv6 only. While they are
    /// open, no other process can bind either address and port, even with
    /// `SO_REUSEADDR` or `SO_REUSEPORT`, so nothing else can receive the
    /// authorization code (RFC 8252 section 8.3). A process on the wildcard
    /// address does not receive loopback connections either, because the
    /// exact-address socket wins. Network.framework's loopback listener left
    /// the IPv4 address open to such a bind, which is why this uses sockets.
    /// `SO_REUSEADDR` on these sockets only lets a retry rebind while earlier
    /// connections sit in TIME_WAIT.
    package func start() async throws {
        guard sources.isEmpty else { return }
        var opened: [Int32] = []
        do {
            opened.append(try Self.listeningSocket(ipv6: false))
            opened.append(try Self.listeningSocket(ipv6: true))
        } catch {
            opened.forEach { close($0) }
            completeCallback(with: .failure(error))
            throw error
        }
        sockets = opened
        for fd in opened {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            let clients = clients
            source.setEventHandler { [weak self] in
                guard let server = self else { return }
                while true {
                    let client = accept(fd, nil, nil)
                    guard client >= 0 else { break }
                    clients.admit(client) { request in
                        Task { await server.handleRequest(request, client: client) }
                    }
                }
            }
            source.resume()
            sources.append(source)
        }
    }

    package func waitForCallback() async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let bufferedResult {
                    self.bufferedResult = nil
                    continuation.resume(with: bufferedResult)
                } else {
                    callbackContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    package func cancel() {
        completeCallback(with: .failure(CancellationError()))
    }

    private nonisolated static func listeningSocket(ipv6: Bool) throws -> Int32 {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        func fail() -> POSIXError {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(fd)
            return error
        }
        var one: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, size) == 0,
              setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, size) == 0 else { throw fail() }
        if ipv6, setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &one, size) != 0 { throw fail() }
        let result: Int32
        if ipv6 {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = OAuthLoopback.port.bigEndian
            address.sin6_addr = in6addr_loopback
            result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        } else {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = OAuthLoopback.port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr(OAuthLoopback.host))
            result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard result == 0, listen(fd, 8) == 0 else { throw fail() }
        // Accept without blocking the dispatch queue; each event drains the
        // pending connections.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    /// Handles one complete request. Connections that send malformed,
    /// oversized, or no headers in time are closed by `CallbackClients` and
    /// never reach here, so a stray connection cannot end the flow.
    private func handleRequest(_ request: String, client: Int32) {
        guard let url = Self.validatedCallbackURL(
            from: request,
            expectedState: expectedState
        ) else {
            DiagnosticsLog.shared.record(.callbackRejected)
            Self.sendResponse(status: "400 Bad Request", body: "Invalid callback request.", to: client)
            return
        }
        DiagnosticsLog.shared.record(.callbackAccepted)
        Self.sendResponse(status: "200 OK", body: "Connected. You can close this window.", to: client)
        completeCallback(with: .success(url))
    }

    package nonisolated static func validatedCallbackURL(
        from request: String,
        expectedState: String
    ) -> URL? {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3,
              requestParts[0] == "GET",
              requestParts[2] == "HTTP/1.1",
              let url = URL(string: "\(OAuthLoopback.origin)\(requestParts[1])"),
              url.path == OAuthLoopback.path,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value == expectedState else { return nil }

        guard let host = lines.dropFirst().first(where: { $0.lowercased().hasPrefix("host:") })?
            .dropFirst("host:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return nil }
        return OAuthLoopback.acceptedHostHeaders.contains(host) ? url : nil
    }

    /// Writes the short response without blocking and closes the connection.
    /// The response is far smaller than a socket buffer, so one non-blocking
    /// write delivers it; a peer that is not reading simply loses it.
    private nonisolated static func sendResponse(status: String, body: String, to client: Int32) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n\(body)"
        let bytes = Array(response.utf8)
        _ = bytes.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        close(client)
    }

    /// Closes the listening sockets before reporting the result, so the port
    /// is free again by the time the caller continues.
    private func completeCallback(with result: Result<URL, any Error>) {
        if !sources.isEmpty {
            sources.forEach { $0.cancel() }
            // Wait out any accept already running on the queue, then drop
            // every connection still sending headers.
            let clients = clients
            queue.sync { clients.closeAll() }
            sources.removeAll()
            sockets.forEach { close($0) }
            sockets.removeAll()
        }
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(with: result)
        } else if bufferedResult == nil {
            bufferedResult = result
        }
    }
}

/// Reads request headers from accepted connections without blocking a thread.
///
/// Each connection gets a non-blocking read source on the server's serial
/// queue and an absolute deadline for its whole request, not a per-read
/// timeout, so a peer trickling bytes cannot hold it open. At most
/// `maximumClients` connections are open; admitting another drops the oldest,
/// so idle connections cannot keep the browser's callback out. Confined to the
/// server's queue.
package final class CallbackClients: @unchecked Sendable {
    static let maximumClients = 16
    package static let headerDeadline: DispatchTimeInterval = .seconds(10)
    private static let maximumHeaderBytes = 16_384

    private final class Client: @unchecked Sendable {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = Data()
        init(fd: Int32, source: DispatchSourceRead) {
            self.fd = fd
            self.source = source
        }
    }

    private let queue: DispatchQueue
    private let deadline: DispatchTimeInterval
    /// Open connections, oldest first.
    private var open: [Client] = []

    init(queue: DispatchQueue, headerDeadline: DispatchTimeInterval = CallbackClients.headerDeadline) {
        self.queue = queue
        self.deadline = headerDeadline
    }

    /// Number of connections still sending headers. Tests read it.
    var count: Int { queue.sync { open.count } }

    /// Starts reading `fd`. Calls `onRequest` with the headers once complete;
    /// the receiver then owns `fd`. Must be called on the server's queue.
    func admit(_ fd: Int32, onRequest: @escaping @Sendable (String) -> Void) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        // Accepted sockets inherit non-blocking mode from the listener; keep it.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        if open.count >= Self.maximumClients, let oldest = open.first {
            drop(oldest)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let client = Client(fd: fd, source: source)
        open.append(client)
        source.setEventHandler { [weak self, weak client] in
            guard let self, let client else { return }
            self.read(client, onRequest: onRequest)
        }
        source.resume()
        queue.asyncAfter(deadline: .now() + deadline) { [weak self, weak client] in
            guard let self, let client else { return }
            self.drop(client)
        }
    }

    /// Closes every connection still sending headers. Must be called on the
    /// server's queue.
    func closeAll() {
        open.forEach(drop)
    }

    private func read(_ client: Client, onRequest: @escaping @Sendable (String) -> Void) {
        var chunk = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(client.fd, &chunk, chunk.count)
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { return }
            guard count > 0 else {
                // Closed or failed before the headers were complete.
                drop(client)
                return
            }
            client.buffer.append(contentsOf: chunk[0..<count])
            guard client.buffer.count <= Self.maximumHeaderBytes else {
                drop(client)
                return
            }
            if let end = client.buffer.range(of: Data("\r\n\r\n".utf8)) {
                guard let request = String(data: client.buffer[..<end.upperBound], encoding: .utf8) else {
                    drop(client)
                    return
                }
                // Hand the connection over without closing it.
                release(client)
                onRequest(request)
                return
            }
        }
    }

    private func release(_ client: Client) {
        guard let index = open.firstIndex(where: { $0 === client }) else { return }
        open.remove(at: index)
        client.source.setEventHandler {}
        client.source.cancel()
    }

    private func drop(_ client: Client) {
        guard let index = open.firstIndex(where: { $0 === client }) else { return }
        open.remove(at: index)
        client.source.cancel()
        close(client.fd)
    }
}
