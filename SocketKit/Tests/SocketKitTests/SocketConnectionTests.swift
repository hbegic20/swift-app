import Foundation
import Testing
@testable import SocketKit

@Suite("Connection loop")
@MainActor
struct SocketConnectionTests {
    func makeConnection(
        _ script: [FakeTransport.Step],
        catchUp: FakeCatchUp = FakeCatchUp(),
        sleepLimit: Int
    ) -> (SocketConnection, FakeTransport, FakeSleeper) {
        let transport = FakeTransport(script)
        let sleeper = FakeSleeper(limit: sleepLimit)
        let connection = SocketConnection(
            store: EventStore(),
            transport: transport,
            catchUpSource: catchUp,
            sleeper: sleeper,
            random: { 0.5 } // no jitter, so delays are exact
        )
        return (connection, transport, sleeper)
    }

    // Rule 7: fail, fail, connect, drop. Delays grow, then reset after a good connect.
    @Test func delaysGrowThenResetAfterSuccessfulConnect() async {
        let (connection, transport, sleeper) = makeConnection(
            [.fail, .fail, .connectThenDrop([]), .fail],
            sleepLimit: 4
        )
        await connection.run()
        #expect(sleeper.delays.current == [1, 2, 1, 2])
        #expect(transport.connectCount.current == 4)
    }

    // Rule 5: a socket that opens but never confirms is not a successful
    // connect, so the delay keeps growing.
    @Test func unconfirmedConnectionDoesNotResetDelay() async {
        let (connection, _, sleeper) = makeConnection(
            [.closeWithoutConfirm, .closeWithoutConfirm, .closeWithoutConfirm],
            sleepLimit: 3
        )
        await connection.run()
        #expect(sleeper.delays.current == [1, 2, 4])
    }

    @Test func unconfirmedConnectionDoesNotCatchUp() async {
        let catchUp = FakeCatchUp()
        let (connection, _, _) = makeConnection([.closeWithoutConfirm], catchUp: catchUp, sleepLimit: 1)
        await connection.run()
        #expect(catchUp.requestedAfter.current.isEmpty)
    }

    @Test func jitterUsesInjectedRandom() async {
        let sleeper = FakeSleeper(limit: 2)
        let connection = SocketConnection(
            store: EventStore(),
            transport: FakeTransport([.fail, .fail]),
            catchUpSource: FakeCatchUp(),
            sleeper: sleeper,
            random: { 1 }
        )
        await connection.run()
        let delays = sleeper.delays.current
        #expect(delays.count == 2)
        #expect(abs(delays[0] - 1.2) < 0.0001)
        #expect(abs(delays[1] - 2.4) < 0.0001)
    }

    // Rule 6: catch up before handling live events.
    @Test func catchesUpBeforeHandlingLiveFrames() async {
        let catchUp = FakeCatchUp([
            .success(EventPage(events: [Sample.message("m1", sequence: 1)], hasMore: false)),
        ])
        let (connection, _, _) = makeConnection(
            [.connectThenDrop([Sample.messageJSON("m2", sequence: 2)])],
            catchUp: catchUp,
            sleepLimit: 1
        )
        await connection.run()

        #expect(catchUp.requestedAfter.current == [nil])
        #expect(connection.store.messages.map(\.id) == ["m1", "m2"])
        // Log is newest first; the catch-up event must come before the live one.
        let eventKinds = connection.store.log.reversed().map(\.kind).filter { $0 == .catchUp || $0 == .live }
        #expect(eventKinds == [.catchUp, .live])
    }

    @Test func secondConnectCatchesUpFromLastSequence() async {
        let catchUp = FakeCatchUp([
            .success(EventPage(events: [], hasMore: false)),
            .success(EventPage(events: [Sample.message("m6", sequence: 6)], hasMore: false)),
        ])
        let (connection, _, _) = makeConnection(
            [
                .connectThenDrop([Sample.messageJSON("m5", sequence: 5)]),
                .connectThenDrop([]),
            ],
            catchUp: catchUp,
            sleepLimit: 2
        )
        await connection.run()
        #expect(catchUp.requestedAfter.current == [nil, 5])
        #expect(connection.store.messages.map(\.id) == ["m5", "m6"])
    }

    // Manual checklist: events added while disconnected appear once each, in order.
    @Test func eventSeenLiveAndInCatchUpIsStoredOnce() async {
        let catchUp = FakeCatchUp([
            .success(EventPage(events: [], hasMore: false)),
            .success(EventPage(events: [
                Sample.message("m1", sequence: 1),
                Sample.message("m2", sequence: 2),
                Sample.message("m3", sequence: 3),
            ], hasMore: false)),
        ])
        let (connection, _, _) = makeConnection(
            [
                .connectThenDrop([Sample.messageJSON("m1", sequence: 1)]),
                .connectThenDrop([Sample.messageJSON("m3", sequence: 3)]),
            ],
            catchUp: catchUp,
            sleepLimit: 2
        )
        await connection.run()
        #expect(connection.store.messages.map(\.id) == ["m1", "m2", "m3"])
    }

    @Test func catchUpFollowsHasMore() async throws {
        let catchUp = FakeCatchUp([
            .success(EventPage(events: [Sample.message("m1", sequence: 1)], hasMore: true)),
            .success(EventPage(events: [Sample.message("m2", sequence: 2)], hasMore: false)),
        ])
        let (connection, _, _) = makeConnection([], catchUp: catchUp, sleepLimit: 1)
        try await connection.catchUp()
        #expect(catchUp.requestedAfter.current == [nil, 1])
        #expect(connection.store.messages.map(\.id) == ["m1", "m2"])
    }

    @Test func catchUpStopsWhenServerKeepsSayingHasMoreWithoutProgress() async throws {
        let catchUp = FakeCatchUp([
            .success(EventPage(events: [], hasMore: true)),
            .success(EventPage(events: [], hasMore: true)),
        ])
        let (connection, _, _) = makeConnection([], catchUp: catchUp, sleepLimit: 1)
        try await connection.catchUp()
        #expect(catchUp.requestedAfter.current.count == 1)
    }

    // A failed catch-up is a failed connect: the socket closes and the delay grows.
    @Test func failedCatchUpRetriesAndDoesNotResetDelay() async {
        let catchUp = FakeCatchUp([.failure(FakeError()), .failure(FakeError())])
        let (connection, transport, sleeper) = makeConnection(
            [.connectThenHold([]), .connectThenHold([])],
            catchUp: catchUp,
            sleepLimit: 2
        )
        await connection.run()
        #expect(sleeper.delays.current == [1, 2])
        #expect(transport.terminatedCount.current == 2)
        #expect(connection.status != .live)
    }

    // Rule 9: unknown types and unreadable frames are skipped; the connection stays up.
    @Test func unknownAndUnreadableFramesDoNotBreakConnection() async {
        let (connection, transport, _) = makeConnection(
            [.connectThenDrop([
                #"{"type":"poll","sequence":1}"#,
                "garbage",
                Sample.notificationJSON("n2", sequence: 2),
            ])],
            sleepLimit: 1
        )
        await connection.run()

        #expect(transport.connectCount.current == 1)
        #expect(connection.store.notifications.map(\.id) == ["n2"])
        #expect(connection.store.unreadCount == 1)
        let kinds = connection.store.log.map(\.kind)
        #expect(kinds.contains(.unknown))
        #expect(kinds.contains(.unreadable))
    }

    @Test func duplicateLiveFrameIsLoggedAsDuplicate() async {
        let frame = Sample.messageJSON("m1", sequence: 1)
        let (connection, _, _) = makeConnection([.connectThenDrop([frame, frame])], sleepLimit: 1)
        await connection.run()
        #expect(connection.store.messages.count == 1)
        #expect(connection.store.log.first(where: { $0.kind == .duplicate }) != nil)
    }

    @Test func statusIsWaitingToRetryWithDelayAfterFailure() async {
        let (connection, _, _) = makeConnection([.fail], sleepLimit: 1)
        await connection.run()
        #expect(connection.status == .waitingToRetry(delay: 1))
    }

    // Rule 4: start when active, stop when backgrounded.
    @Test func startGoesLiveAndStopClosesSocket() async {
        let (connection, transport, _) = makeConnection([.connectThenHold([])], sleepLimit: 1)
        connection.start()
        let task = connection.runningTask

        await waitUntil { connection.status == .live }
        #expect(connection.status == .live)

        connection.stop()
        await task?.value
        #expect(connection.status == .disconnected)
        #expect(transport.terminatedCount.current == 1)
        #expect(connection.runningTask == nil)
    }

    @Test func startTwiceRunsOneLoop() async {
        let (connection, transport, _) = makeConnection([.connectThenHold([])], sleepLimit: 1)
        connection.start()
        connection.start()
        await waitUntil { connection.status == .live }
        #expect(transport.connectCount.current == 1)
        connection.stop()
    }

    @Test func canStartAgainAfterStop() async {
        let (connection, transport, _) = makeConnection(
            [.connectThenHold([]), .connectThenHold([])],
            sleepLimit: 1
        )
        connection.start()
        await waitUntil { connection.status == .live }
        let first = connection.runningTask
        connection.stop()
        await first?.value

        connection.start()
        await waitUntil { connection.status == .live }
        #expect(transport.connectCount.current == 2)
        connection.stop()
    }

    /// Lets the main-actor loop make progress without using the real clock.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() {
            await Task.yield()
        }
    }
}
