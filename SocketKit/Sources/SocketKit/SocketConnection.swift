import Foundation
import Observation

public enum ConnectionStatus: Equatable, Sendable {
    /// Not running (app in background, or never started).
    case disconnected
    /// Opening the socket, confirming it, and catching up.
    case connecting
    /// Confirmed, caught up, and handling live events.
    case live
    /// Waiting before the next attempt.
    case waitingToRetry(delay: TimeInterval)
}

/// The connection loop: connect, confirm, catch up, go live, and retry with
/// growing delays when anything fails.
@MainActor
@Observable
public final class SocketConnection {
    public private(set) var status: ConnectionStatus = .disconnected

    @ObservationIgnored public let store: EventStore
    @ObservationIgnored private let transport: WebSocketTransport
    @ObservationIgnored private let catchUpSource: CatchUpSource
    @ObservationIgnored private let policy: ReconnectPolicy
    @ObservationIgnored private let sleeper: Sleeper
    @ObservationIgnored private let random: () -> Double
    @ObservationIgnored private(set) var runningTask: Task<Void, Never>?

    public init(
        store: EventStore,
        transport: WebSocketTransport,
        catchUpSource: CatchUpSource,
        policy: ReconnectPolicy = .standard,
        sleeper: Sleeper = TaskSleeper(),
        random: @escaping () -> Double = { Double.random(in: 0...1) }
    ) {
        self.store = store
        self.transport = transport
        self.catchUpSource = catchUpSource
        self.policy = policy
        self.sleeper = sleeper
        self.random = random
    }

    /// Call when the scene becomes active (rule 4). Does nothing if already running.
    public func start() {
        guard runningTask == nil else { return }
        runningTask = Task { await run() }
    }

    /// Call when the app goes to the background (rule 4).
    public func stop() {
        guard let task = runningTask else { return }
        runningTask = nil
        task.cancel()
        status = .disconnected
        store.appendLog(.status, "stopped")
    }

    /// Fetches everything after `store.lastSequence` over HTTP, page by page.
    /// Also used when a push arrives (rule 11).
    public func catchUp() async throws {
        while true {
            let before = store.lastSequence
            let page = try await catchUpSource.events(after: before)
            for event in page.events {
                record(event, source: .catchUp)
            }
            if page.skippedCount > 0 {
                store.appendLog(.unreadable, "catch-up skipped \(page.skippedCount) unreadable event(s)")
            }
            // Stop if the server says so, or if the page did not move us forward
            // (protects against a server that keeps saying hasMore).
            guard page.hasMore, store.lastSequence != before else { return }
        }
    }

    /// The loop itself. Runs until the task is cancelled or the sleeper throws.
    func run() async {
        var attempt = 0
        while !Task.isCancelled {
            setStatus(.connecting)
            do {
                for try await transportEvent in transport.connect() {
                    switch transportEvent {
                    case .connected:
                        // Frames that arrive during catch-up wait in the stream
                        // and are handled after it (rule 6).
                        try await catchUp()
                        attempt = 0
                        setStatus(.live)
                    case .frame(let data):
                        handleFrame(data)
                    }
                }
                if !Task.isCancelled {
                    store.appendLog(.status, "connection closed")
                }
            } catch {
                if !Task.isCancelled {
                    store.appendLog(.status, "connection failed: \(error.localizedDescription)")
                }
            }
            if Task.isCancelled { return }

            let delay = policy.delay(forAttempt: attempt, random: random())
            attempt += 1
            setStatus(.waitingToRetry(delay: delay))
            do {
                try await sleeper.sleep(seconds: delay)
            } catch {
                return
            }
        }
    }

    func handleFrame(_ data: Data) {
        let event: Event
        do {
            event = try EventDecoder.decode(data)
        } catch {
            // One bad frame is skipped, the connection stays up (rule 9).
            store.appendLog(.unreadable, String(decoding: data, as: UTF8.self))
            return
        }
        record(event, source: .live)
    }

    private func record(_ event: Event, source: LogEntry.Kind) {
        let inserted = store.ingest([event])
        let kind: LogEntry.Kind
        if case .unknown = event {
            kind = .unknown
        } else if inserted.isEmpty {
            kind = .duplicate
        } else {
            kind = source
        }
        store.appendLog(kind, Self.describe(event))
    }

    /// Ignores updates from a loop that was already stopped, so a stale loop
    /// cannot overwrite the status of a new one.
    private func setStatus(_ newStatus: ConnectionStatus) {
        guard !Task.isCancelled, status != newStatus else { return }
        status = newStatus
        store.appendLog(.status, Self.describe(newStatus))
    }

    static func describe(_ event: Event) -> String {
        switch event {
        case .message(let m):
            "#\(m.sequence) message \(m.id) from \(m.senderID): \(m.text)"
        case .notification(let n):
            "#\(n.sequence) notification \(n.id): \(n.title)"
        case .unknown(let type, let sequence):
            "#\(sequence.map(String.init) ?? "?") unknown type \"\(type)\" ignored"
        }
    }

    static func describe(_ status: ConnectionStatus) -> String {
        switch status {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .live: "live"
        case .waitingToRetry(let delay): String(format: "retrying in %.1fs", delay)
        }
    }
}
