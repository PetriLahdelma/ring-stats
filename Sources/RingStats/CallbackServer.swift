import Foundation
import Network

enum OAuthLoopback {
    static let host = "127.0.0.1"
    static let port: UInt16 = 43_828
    static let path = "/oauth/callback"
    static let origin = "http://\(host):\(port)"
    static let callbackURL = "\(origin)\(path)"
    static let acceptedHostHeaders = ["\(host):\(port)", "localhost:\(port)"]
}

actor CallbackServer {
    private static let maximumHeaderBytes = 16_384

    private let expectedState: String
    private let queue = DispatchQueue(label: "local.ringstats.oauth-callback")
    private var listener: NWListener?
    private var listenerIsReady = false
    private var readyContinuations: [CheckedContinuation<Void, any Error>] = []
    private var callbackContinuation: CheckedContinuation<URL, any Error>?
    private var bufferedResult: Result<URL, any Error>?
    private var pendingResultAfterListenerShutdown: Result<URL, any Error>?

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws {
        if listenerIsReady { return }

        try await withCheckedThrowingContinuation { ready in
            readyContinuations.append(ready)
            guard listener == nil else { return }

            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(
                    host: NWEndpoint.Host(OAuthLoopback.host),
                    port: NWEndpoint.Port(rawValue: OAuthLoopback.port)!
                )
                let newListener = try NWListener(using: parameters)
                listener = newListener
                newListener.stateUpdateHandler = { [weak self] state in
                    Task { await self?.handleListenerState(state) }
                }
                newListener.newConnectionHandler = { [weak self] connection in
                    Task { await self?.handle(connection) }
                }
                newListener.start(queue: queue)
            } catch {
                completeReady(with: .failure(error))
                completeCallback(with: .failure(error))
            }
        }
    }

    func waitForCallback() async throws -> URL {
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

    func cancel() {
        completeReady(with: .failure(CancellationError()))
        completeCallback(with: .failure(CancellationError()))
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            listenerIsReady = true
            completeReady(with: .success(()))
        case .failed(let error):
            completeReady(with: .failure(error))
            completeCallback(with: .failure(error))
        case .cancelled:
            listenerIsReady = false
            listener = nil
            completeReady(with: .failure(CancellationError()))
            if let pendingResultAfterListenerShutdown {
                self.pendingResultAfterListenerShutdown = nil
                deliverCallback(pendingResultAfterListenerShutdown)
            }
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        Self.receiveHeaders(over: connection) { [weak self] result in
            Task { await self?.handleRequest(result, over: connection) }
        }
    }

    private func handleRequest(
        _ result: Result<String, any Error>,
        over connection: NWConnection
    ) {
        switch result {
        case .failure:
            // Browsers, health checks, and local processes can open or reset a
            // loopback connection while OAuth is pending. A single malformed
            // connection must not terminate the authorization flow.
            connection.cancel()
        case .success(let request):
            guard let url = Self.validatedCallbackURL(
                from: request,
                expectedState: expectedState
            ) else {
                DiagnosticsLog.shared.record(.callbackRejected)
                sendResponse(
                    status: "400 Bad Request",
                    body: "Invalid callback request.",
                    over: connection
                )
                return
            }
            DiagnosticsLog.shared.record(.callbackAccepted)
            sendResponse(
                status: "200 OK",
                body: "Connected. You can close this window.",
                over: connection
            )
            completeCallback(with: .success(url))
        }
    }

    nonisolated private static func receiveHeaders(
        over connection: NWConnection,
        accumulated: Data = Data(),
        completion: @escaping @Sendable (Result<String, any Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) {
            data,
            _,
            isComplete,
            error in
            if let error {
                completion(.failure(error))
                return
            }

            var buffer = accumulated
            if let data { buffer.append(data) }
            if buffer.count > maximumHeaderBytes {
                completion(.failure(CallbackServerError.headersTooLarge))
                return
            }

            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer[..<headerEnd.upperBound]
                guard let request = String(data: headerData, encoding: .utf8) else {
                    completion(.failure(CallbackServerError.invalidEncoding))
                    return
                }
                completion(.success(request))
                return
            }

            guard !isComplete else {
                completion(.failure(CallbackServerError.incompleteHeaders))
                return
            }
            receiveHeaders(over: connection, accumulated: buffer, completion: completion)
        }
    }

    nonisolated static func validatedCallbackURL(
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

    private func sendResponse(status: String, body: String, over connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n\(body)"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private func completeReady(with result: Result<Void, any Error>) {
        let pending = readyContinuations
        readyContinuations.removeAll()
        pending.forEach { $0.resume(with: result) }
    }

    private func completeCallback(with result: Result<URL, any Error>) {
        listenerIsReady = false
        if let listener {
            if pendingResultAfterListenerShutdown == nil {
                pendingResultAfterListenerShutdown = result
            }
            listener.cancel()
            return
        }

        deliverCallback(result)
    }

    private func deliverCallback(_ result: Result<URL, any Error>) {
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

    var errorDescription: String? {
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
