import Foundation
@testable import SocketKit

struct FakeError: Error {}

/// A small lock-protected box so fakes can be `Sendable`.
final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value { withValue { $0 } }
}

/// A socket that follows a script, one step per `connect()` call.
final class FakeTransport: WebSocketTransport {
    enum Step {
        /// The connection fails before it is confirmed.
        case fail
        /// The socket opens and closes again without ever getting a pong.
        case closeWithoutConfirm
        /// Confirmed, then delivers frames, then drops with an error.
        case connectThenDrop([String])
        /// Confirmed, then delivers frames, then stays open until cancelled.
        case connectThenHold([String])
    }

    private let script: Locked<[Step]>
    let connectCount = Locked(0)
    let terminatedCount = Locked(0)

    init(_ script: [Step]) {
        self.script = Locked(script)
    }

    func connect() -> AsyncThrowingStream<TransportEvent, Error> {
        connectCount.withValue { $0 += 1 }
        // Once the script runs out, every further attempt fails.
        let step = script.withValue { $0.isEmpty ? .fail : $0.removeFirst() }
        let (stream, continuation) = AsyncThrowingStream<TransportEvent, Error>.makeStream()
        let terminated = terminatedCount
        continuation.onTermination = { _ in terminated.withValue { $0 += 1 } }

        switch step {
        case .fail:
            continuation.finish(throwing: FakeError())
        case .closeWithoutConfirm:
            continuation.finish()
        case .connectThenDrop(let frames):
            continuation.yield(.connected)
            for frame in frames { continuation.yield(.frame(Data(frame.utf8))) }
            continuation.finish(throwing: FakeError())
        case .connectThenHold(let frames):
            continuation.yield(.connected)
            for frame in frames { continuation.yield(.frame(Data(frame.utf8))) }
        }
        return stream
    }
}

/// Records requested delays instead of sleeping. Throws once `limit` sleeps
/// have been requested, which ends the connection loop in tests.
final class FakeSleeper: Sleeper {
    let delays = Locked<[TimeInterval]>([])
    let limit: Int

    init(limit: Int) { self.limit = limit }

    func sleep(seconds: TimeInterval) async throws {
        let count = delays.withValue { delays in
            delays.append(seconds)
            return delays.count
        }
        if count >= limit { throw CancellationError() }
    }
}

/// Serves catch-up pages from a list of results, one per call.
final class FakeCatchUp: CatchUpSource {
    private let responses: Locked<[Result<EventPage, Error>]>
    let requestedAfter = Locked<[Int?]>([])

    init(_ responses: [Result<EventPage, Error>] = []) {
        self.responses = Locked(responses)
    }

    func events(after sequence: Int?) async throws -> EventPage {
        requestedAfter.withValue { $0.append(sequence) }
        // Once the list runs out, report "nothing new".
        let next = responses.withValue { $0.isEmpty ? .success(EventPage(events: [], hasMore: false)) : $0.removeFirst() }
        return try next.get()
    }
}

// MARK: - Sample data

enum Sample {
    static let date = Date(timeIntervalSince1970: 1_791_450_000)

    static func message(_ id: String, sequence: Int, createdAt: Date = date) -> Event {
        .message(ChatMessage(id: id, chatID: "42", senderID: "coach", text: "hi \(id)", createdAt: createdAt, sequence: sequence))
    }

    static func notification(_ id: String, sequence: Int) -> Event {
        .notification(AppNotification(id: id, title: "t \(id)", body: "b", workoutID: nil, createdAt: date, sequence: sequence))
    }

    static func messageJSON(_ id: String, sequence: Int) -> String {
        #"{"type":"message","id":"\#(id)","chatID":"42","senderID":"coach","text":"hi","createdAt":"2026-10-08T09:00:00Z","sequence":\#(sequence)}"#
    }

    static func notificationJSON(_ id: String, sequence: Int) -> String {
        #"{"type":"notification","id":"\#(id)","title":"Class","body":"Legs","workoutID":"legs-1","createdAt":"2026-10-08T09:05:00Z","sequence":\#(sequence)}"#
    }
}
