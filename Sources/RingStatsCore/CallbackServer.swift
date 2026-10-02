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
    /// How long a connection may take to send its request headers.
    private static let readTimeout = timeval(tv_sec: 10, tv_usec: 0)

    private let expectedState: String
    private let queue = DispatchQueue(label: "local.ringstats.oauth-callback")
    private var sockets: [Int32] = []
    private var sources: [DispatchSourceRead] = []
    private var callbackContinuation: CheckedContinuation<URL, any Error>?
    private var bufferedResult: Result<URL, any Error>?

    package init(expectedState: String) {
        self.expectedState = expectedState
    }

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
            source.setEventHandler { [weak self] in
                guard let server = self else { return }
                while true {
                    let client = accept(fd, nil, nil)
                    guard client >= 0 else { break }
                    Self.readHeaders(from: client) { result in
                        Task { await server.handleRequest(result, client: client) }
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

    private func handleRequest(_ result: Result<String, any Error>, client: Int32) {
        switch result {
        case .failure:
            // Browsers, health checks, and local processes can open or reset a
            // loopback connection while OAuth is pending. A single malformed
            // connection must not terminate the authorization flow.
            close(client)
        case .success(let request):
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
    }

    /// Reads up to the end of the request headers on a background queue, so a
    /// slow or silent connection cannot hold up other connections.
    private nonisolated static func readHeaders(
        from client: Int32,
        completion: @escaping @Sendable (Result<String, any Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Accepted sockets inherit non-blocking mode; read them blocking,
            // with a timeout.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var timeout = readTimeout
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var one: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 4_096)
            while true {
                let count = read(client, &chunk, chunk.count)
                guard count > 0 else {
                    completion(.failure(CallbackServerError.incompleteHeaders))
                    return
                }
                buffer.append(contentsOf: chunk[0..<count])
                if buffer.count > maximumHeaderBytes {
                    completion(.failure(CallbackServerError.headersTooLarge))
                    return
                }
                if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    guard let request = String(data: buffer[..<headerEnd.upperBound], encoding: .utf8) else {
                        completion(.failure(CallbackServerError.invalidEncoding))
                        return
                    }
                    completion(.success(request))
                    return
                }
            }
        }
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

    private nonisolated static func sendResponse(status: String, body: String, to client: Int32) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n\(body)"
        DispatchQueue.global(qos: .userInitiated).async {
            let bytes = Array(response.utf8)
            var sent = 0
            while sent < bytes.count {
                let count = bytes[sent...].withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                guard count > 0 else { break }
                sent += count
            }
            close(client)
        }
    }

    /// Closes the listening sockets before reporting the result, so the port
    /// is free again by the time the caller continues.
    private func completeCallback(with result: Result<URL, any Error>) {
        if !sources.isEmpty {
            sources.forEach { $0.cancel() }
            // Wait out any accept already running on the queue before closing.
            queue.sync {}
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

private enum CallbackServerError: LocalizedError {
    case headersTooLarge
    case incompleteHeaders
    case invalidEncoding

    package var errorDescription: String? {
        switch self {
        case .headersTooLarge:
            "The OAuth callback headers exceeded the allowed size."
        case .incompleteHeaders:
            "The OAuth callback ended before its headers were complete."
        case .invalidEncoding:
            "The OAuth callback headers were not valid UTF-8."
        }
    }
}
