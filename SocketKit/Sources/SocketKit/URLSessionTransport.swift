import Foundation

public enum TransportError: Error, LocalizedError {
    case pongTimeout
    case badHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .pongTimeout: "no pong from server"
        case .badHTTPStatus(let code): "HTTP status \(code)"
        }
    }
}

/// The real socket, built on `URLSessionWebSocketTask` (rule 2).
public struct URLSessionWebSocketTransport: WebSocketTransport {
    public let url: URL
    public let session: URLSession
    public let pingInterval: Duration
    public let pongTimeout: Duration

    public init(
        url: URL,
        session: URLSession = .shared,
        pingInterval: Duration = .seconds(25),
        pongTimeout: Duration = .seconds(10)
    ) {
        self.url = url
        self.session = session
        self.pingInterval = pingInterval
        self.pongTimeout = pongTimeout
    }

    public func connect() -> AsyncThrowingStream<TransportEvent, Error> {
        let task = session.webSocketTask(with: url)
        let pingInterval = pingInterval
        let pongTimeout = pongTimeout

        return AsyncThrowingStream { continuation in
            // resume() returns before the connection exists.
            task.resume()

            let worker = Task {
                do {
                    // Confirm before calling it connected (rule 5).
                    try await Self.ping(task, timeout: pongTimeout)
                    continuation.yield(.connected)

                    // Heartbeat (rule 8): if a ping fails, close the socket so
                    // receive() below throws and the reconnect logic takes over.
                    let heartbeat = Task {
                        while !Task.isCancelled {
                            try await Task.sleep(for: pingInterval)
                            do {
                                try await Self.ping(task, timeout: pongTimeout)
                            } catch {
                                task.cancel(with: .goingAway, reason: nil)
                                return
                            }
                        }
                    }
                    defer { heartbeat.cancel() }

                    while true {
                        switch try await task.receive() {
                        case .string(let text):
                            continuation.yield(.frame(Data(text.utf8)))
                        case .data(let data):
                            continuation.yield(.frame(data))
                        @unknown default:
                            break
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                worker.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    /// Sends a ping and waits for the pong, or gives up after `timeout`.
    private static func ping(_ task: URLSessionWebSocketTask, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    task.sendPing { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                // Cancelling the task makes the pending ping callback fire,
                // so the group above can finish.
                task.cancel(with: .goingAway, reason: nil)
                throw TransportError.pongTimeout
            }
            try await group.next()
            group.cancelAll()
        }
    }
}

/// The real catch-up client: `GET /events?after={sequence}`.
public struct HTTPCatchUpSource: CatchUpSource {
    public let baseURL: URL
    public let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func events(after sequence: Int?) async throws -> EventPage {
        let (data, response) = try await session.data(from: Self.eventsURL(baseURL: baseURL, after: sequence))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TransportError.badHTTPStatus(http.statusCode)
        }
        return try EventDecoder.decodePage(data)
    }

    static func eventsURL(baseURL: URL, after sequence: Int?) -> URL {
        let url = baseURL.appending(path: "events")
        guard let sequence else { return url }
        return url.appending(queryItems: [URLQueryItem(name: "after", value: String(sequence))])
    }
}
