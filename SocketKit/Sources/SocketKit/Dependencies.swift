import Foundation

/// What a socket connection reports while it is open.
public enum TransportEvent: Equatable, Sendable {
    /// The connection is confirmed (a ping got its pong). Only now is it "connected" (rule 5).
    case connected
    /// One frame from the server.
    case frame(Data)
}

/// The socket, behind a protocol so tests can follow a script.
public protocol WebSocketTransport: Sendable {
    /// Opens a connection. The stream yields `.connected` once confirmed, then
    /// frames. It finishes (normally or with an error) when the connection is
    /// gone. Ending the iteration closes the connection.
    func connect() -> AsyncThrowingStream<TransportEvent, Error>
}

/// HTTP catch-up, behind a protocol so tests need no network.
public protocol CatchUpSource: Sendable {
    /// `GET /events?after={sequence}`. `nil` means everything.
    func events(after sequence: Int?) async throws -> EventPage
}

/// Waiting, behind a protocol so tests record delays instead of sleeping.
public protocol Sleeper: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
