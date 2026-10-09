import Foundation
import Testing
@testable import SocketKit

@Suite("Event decoding")
struct EventDecodingTests {
    @Test func decodesMessageFromProtocolExample() throws {
        let json = #"{"type": "message", "id": "m1", "chatID": "42", "senderID": "coach", "text": "Great session!", "createdAt": "2026-10-08T09:00:00Z", "sequence": 7}"#
        let event = try EventDecoder.decode(Data(json.utf8))
        guard case .message(let message) = event else {
            Issue.record("expected a message, got \(event)")
            return
        }
        #expect(message.id == "m1")
        #expect(message.chatID == "42")
        #expect(message.senderID == "coach")
        #expect(message.text == "Great session!")
        #expect(message.sequence == 7)
        #expect(message.createdAt == ISO8601DateFormatter().date(from: "2026-10-08T09:00:00Z"))
    }

    @Test func decodesNotificationFromProtocolExample() throws {
        let json = #"{"type": "notification", "id": "n7", "title": "Class starts in 10 min", "body": "Leg day, studio 2", "workoutID": "legs-1", "createdAt": "2026-10-08T09:05:00Z", "sequence": 8}"#
        let event = try EventDecoder.decode(Data(json.utf8))
        guard case .notification(let notification) = event else {
            Issue.record("expected a notification, got \(event)")
            return
        }
        #expect(notification.id == "n7")
        #expect(notification.title == "Class starts in 10 min")
        #expect(notification.body == "Leg day, studio 2")
        #expect(notification.workoutID == "legs-1")
        #expect(notification.sequence == 8)
    }

    @Test func notificationWithoutWorkoutIDIsFine() throws {
        let json = #"{"type":"notification","id":"n1","title":"t","body":"b","createdAt":"2026-10-08T09:05:00Z","sequence":1}"#
        guard case .notification(let notification) = try EventDecoder.decode(Data(json.utf8)) else {
            Issue.record("expected a notification")
            return
        }
        #expect(notification.workoutID == nil)
    }

    // Rule 9: unknown event types are ignored, never an error.
    @Test func unknownTypeIsNotAnError() throws {
        let json = #"{"type":"workoutReminder","id":"x1","whatever":true,"sequence":9}"#
        #expect(try EventDecoder.decode(Data(json.utf8)) == .unknown(type: "workoutReminder", sequence: 9))
    }

    @Test func unknownTypeWithoutSequenceIsNotAnError() throws {
        let json = #"{"type":"future","sequence":"not a number"}"#
        #expect(try EventDecoder.decode(Data(json.utf8)) == .unknown(type: "future", sequence: nil))
    }

    @Test(arguments: [
        "not json",
        #"{"id":"m1"}"#,                                       // no type
        #"{"type":"message","id":"m1"}"#,                      // known type, missing fields
        #"{"type":"message","id":"m1","chatID":"42","senderID":"c","text":"t","createdAt":"yesterday","sequence":1}"#,
    ])
    func unreadableFrameThrows(json: String) {
        #expect(throws: (any Error).self) { try EventDecoder.decode(Data(json.utf8)) }
    }

    @Test func pageSkipsUnreadableEntriesAndKeepsTheRest() throws {
        let json = """
        {"events": [
            \(Sample.messageJSON("m1", sequence: 1)),
            {"type": "message", "id": "broken"},
            {"type": "poll", "sequence": 3},
            \(Sample.notificationJSON("n1", sequence: 4))
        ], "hasMore": true}
        """
        let page = try EventDecoder.decodePage(Data(json.utf8))
        #expect(page.events.map(\.sequence) == [1, 3, 4])
        #expect(page.events[1] == .unknown(type: "poll", sequence: 3))
        #expect(page.hasMore)
        #expect(page.skippedCount == 1)
    }

    @Test func eventsURLIncludesAfterOnlyWhenGiven() {
        let base = URL(string: "http://localhost:8080")!
        #expect(HTTPCatchUpSource.eventsURL(baseURL: base, after: nil).absoluteString == "http://localhost:8080/events")
        #expect(HTTPCatchUpSource.eventsURL(baseURL: base, after: 7).absoluteString == "http://localhost:8080/events?after=7")
    }
}
