import Foundation
import Testing
@testable import SocketKit

// Rule 11: a push is only a hint. It says where to go, then the app syncs.
@Suite("Push")
@MainActor
struct PushTests {
    @Test func messagePushOpensMessages() {
        let route = PushRoute(userInfo: ["type": "message", "chatID": "42", "aps": ["alert": "x"]])
        #expect(route == .messages(chatID: "42"))
    }

    @Test func notificationPushOpensNotifications() {
        #expect(PushRoute(userInfo: ["type": "notification", "workoutID": "legs-1"]) == .notifications(workoutID: "legs-1"))
        #expect(PushRoute(userInfo: ["type": "notification"]) == .notifications(workoutID: nil))
    }

    @Test func unknownOrMissingTypeHasNoRoute() {
        #expect(PushRoute(userInfo: ["type": "workoutPoll"]) == nil)
        #expect(PushRoute(userInfo: [:]) == nil)
        #expect(PushRoute(userInfo: ["type": 5]) == nil)
    }

    @Test func labels() {
        #expect(PushRoute.messages(chatID: "42").label == "messages (chat 42)")
        #expect(PushRoute.messages(chatID: nil).label == "messages")
        #expect(PushRoute.notifications(workoutID: "legs-1").label == "notifications (workout legs-1)")
        #expect(PushRoute.notifications(workoutID: nil).label == "notifications")
    }

    @Test func pushSyncFetchesFromServerNotFromPushText() async {
        let catchUp = FakeCatchUp([.success(EventPage(events: [Sample.message("m1", sequence: 1)], hasMore: false))])
        let connection = SocketConnection(store: EventStore(), transport: FakeTransport([]), catchUpSource: catchUp)
        await connection.syncAfterPush()
        #expect(connection.store.messages.map(\.id) == ["m1"])
        #expect(catchUp.requestedAfter.current == [nil])
    }

    @Test func failedPushSyncIsLoggedNotThrown() async {
        let catchUp = FakeCatchUp([.failure(FakeError())])
        let connection = SocketConnection(store: EventStore(), transport: FakeTransport([]), catchUpSource: catchUp)
        await connection.syncAfterPush()
        #expect(connection.store.log.first?.text.hasPrefix("push sync failed") == true)
    }
}
