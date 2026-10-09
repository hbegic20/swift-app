import Foundation
import Testing
@testable import SocketKit

@Suite("Event store")
@MainActor
struct EventStoreTests {
    // Rule 3: the same item arriving twice is stored once.
    @Test func sameIDTwiceIsStoredOnce() {
        let store = EventStore()
        let first = store.ingest([Sample.message("m1", sequence: 1)])
        let second = store.ingest([Sample.message("m1", sequence: 1)])
        #expect(first.count == 1)
        #expect(second.isEmpty)
        #expect(store.messages.map(\.id) == ["m1"])
    }

    @Test func duplicateNotificationDoesNotRaiseUnreadCount() {
        let store = EventStore()
        store.ingest([Sample.notification("n1", sequence: 1)])
        store.ingest([Sample.notification("n1", sequence: 1)])
        #expect(store.notifications.count == 1)
        #expect(store.unreadCount == 1)
    }

    // Rule 10: order comes from the server's sequence, not the phone clock.
    @Test func sortsBySequenceNotByDate() {
        let store = EventStore()
        let early = Date(timeIntervalSince1970: 0)
        let late = Date(timeIntervalSince1970: 1_000_000)
        store.ingest([
            Sample.message("c", sequence: 3, createdAt: early),
            Sample.message("a", sequence: 1, createdAt: late),
        ])
        store.ingest([Sample.message("b", sequence: 2, createdAt: early)])
        #expect(store.messages.map(\.id) == ["a", "b", "c"])
    }

    @Test func unreadCountAndMarkAllRead() {
        let store = EventStore()
        store.ingest([Sample.notification("n1", sequence: 1), Sample.notification("n2", sequence: 2)])
        #expect(store.unreadCount == 2)

        store.markAllNotificationsRead()
        #expect(store.unreadCount == 0)

        store.ingest([Sample.notification("n3", sequence: 3)])
        #expect(store.unreadCount == 1)
        #expect(store.isRead(store.notifications[0]))
        #expect(!store.isRead(store.notifications[2]))
    }

    @Test func badgeIsHiddenWhenNothingIsUnread() {
        let store = EventStore()
        #expect(store.unreadBadge == nil)
        store.ingest([Sample.notification("n1", sequence: 1), Sample.notification("n2", sequence: 2)])
        #expect(store.unreadBadge == "2 unread")
        store.markAllNotificationsRead()
        #expect(store.unreadBadge == nil)
    }

    @Test func messagesDoNotAffectUnreadCount() {
        let store = EventStore()
        store.ingest([Sample.message("m1", sequence: 1)])
        #expect(store.unreadCount == 0)
    }

    @Test func lastSequenceTracksHighestAcrossAllTypes() {
        let store = EventStore()
        #expect(store.lastSequence == nil)
        store.ingest([Sample.message("m1", sequence: 5), Sample.notification("n1", sequence: 3)])
        #expect(store.lastSequence == 5)
        // Unknown events still move the shared counter, so catch-up skips past them.
        store.ingest([.unknown(type: "poll", sequence: 9)])
        #expect(store.lastSequence == 9)
        store.ingest([.unknown(type: "poll", sequence: nil)])
        #expect(store.lastSequence == 9)
    }

    @Test func unknownEventsAreNotStored() {
        let store = EventStore()
        let inserted = store.ingest([.unknown(type: "poll", sequence: 1)])
        #expect(inserted.isEmpty)
        #expect(store.messages.isEmpty)
        #expect(store.notifications.isEmpty)
    }

    @Test func logIsNewestFirstAndCapped() {
        let store = EventStore(maxLogEntries: 3)
        for i in 1...5 { store.appendLog(.status, "entry \(i)") }
        #expect(store.log.map(\.text) == ["entry 5", "entry 4", "entry 3"])
    }
}
