import Foundation
import Network

final class CallbackServer: @unchecked Sendable {
    private let expectedState: String
    private let queue = DispatchQueue(label: "local.ringstats.oauth-callback")
    private var listener: NWListener?
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var bufferedResult: Result<URL, any Error>?

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { ready in
            let shouldStart = lock.withLock { () -> Bool in
                guard listener == nil else { return false }
                readyContinuation = ready
                return true
            }
            guard shouldStart else {
                ready.resume()
                return
            }
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 43828)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.finishReady(.success(()))
                    case .failed(let error):
                        self?.finishReady(.failure(error))
                        self?.finish(.failure(error))
                    case .cancelled:
                        self?.finishReady(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] in self?.handle($0) }
                listener.start(queue: queue)
            } catch {
                finishReady(.failure(error))
                finish(.failure(error))
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let buffered = lock.withLock { () -> Result<URL, any Error>? in
                    if let bufferedResult {
                        self.bufferedResult = nil
                        return bufferedResult
                    }
                    self.continuation = continuation
                    return nil
                }
                if let buffered {
                    continuation.resume(with: buffered)
                }
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error { finish(.failure(error)); return }
            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let url = Self.validatedCallbackURL(
                    from: request,
                    expectedState: expectedState
                  ) else {
                sendResponse(
                    status: "400 Bad Request",
                    body: "Invalid callback request.",
                    over: connection
                )
                return
            }
            sendResponse(
                status: "200 OK",
                body: "Connected. You can close this window.",
                over: connection
            )
            finish(.success(url))
        }
    }

    static func validatedCallbackURL(from request: String, expectedState: String) -> URL? {
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3,
              requestParts[0] == "GET",
              let url = URL(string: "http://localhost:43828\(requestParts[1])"),
              url.path == "/oauth/callback",
              URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value == expectedState else { return nil }

        let host = lines.dropFirst().first { $0.lowercased().hasPrefix("host:") }?
            .dropFirst("host:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return ["localhost:43828", "127.0.0.1:43828"].contains(host) ? url : nil
    }

    private func sendResponse(status: String, body: String, over connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n\(body)"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    private func finishReady(_ result: Result<Void, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<Void, any Error>? in
            defer { readyContinuation = nil }
            return readyContinuation
        }
        pending?.resume(with: result)
    }

    private func finish(_ result: Result<URL, any Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<URL, any Error>? in
            if let continuation {
                self.continuation = nil
                return continuation
            }
            if bufferedResult == nil {
                bufferedResult = result
            }
            return nil
        }
        listener?.cancel()
        listener = nil
        pending?.resume(with: result)
    }
}
