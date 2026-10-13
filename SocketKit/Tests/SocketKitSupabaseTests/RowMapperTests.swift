import Foundation
import Testing
import SocketKit
@testable import SocketKitSupabase

/// A row of `public.events` as Supabase sends it, over Realtime and over HTTP.
private func row(
    sequence: Any = 7,
    id: String = "m1",
    type: String = "message",
    payload: String = #"{"chatID": "42", "senderID": "coach", "text": "Great session!"}"#,
    createdAt: String = "2026-10-12T14:14:13.5358+00:00"
) -> String {
    let sequenceJSON = sequence is String ? "\"\(sequence)\"" : "\(sequence)"
    return """
    {"sequence": \(sequenceJSON), "id": "\(id)", "user_id": "c85b6242-67f1-49f9-aa45-69973aa509ca",
     "type": "\(type)", "payload": \(payload), "created_at": "\(createdAt)"}
    """
}

@Suite("Supabase row mapping")
struct RowMapperTests {
    @Test func messageRowBecomesMessage() throws {
        let event = try SupabaseRowMapper.event(fromRow: Data(row().utf8))
        guard case .message(let message) = event else {
            Issue.record("expected a message, got \(event)")
            return
        }
        #expect(message.id == "m1")
        #expect(message.chatID == "42")
        #expect(message.senderID == "coach")
        #expect(message.text == "Great session!")
        #expect(message.sequence == 7)
        let whole = ISO8601DateFormatter().date(from: "2026-10-12T14:14:13Z")!
        #expect(abs(message.createdAt.timeIntervalSince(whole) - 0.5358) < 0.000_001)
    }

    @Test func notificationRowBecomesNotification() throws {
        let json = row(id: "n1", type: "notification",
                       payload: #"{"title": "Yoga at 6", "body": "Leg day, studio 2", "workoutID": "legs-1"}"#)
        guard case .notification(let notification) = try SupabaseRowMapper.event(fromRow: Data(json.utf8)) else {
            Issue.record("expected a notification")
            return
        }
        #expect(notification.id == "n1")
        #expect(notification.title == "Yoga at 6")
        #expect(notification.workoutID == "legs-1")
        #expect(notification.sequence == 7)
    }

    // Rule 9: a type this app does not know is ignored, not an error.
    @Test func unknownTypeRowIsUnknownWithItsSequence() throws {
        let json = row(id: "p1", type: "workoutPoll", payload: #"{"question": "Rate today's class"}"#)
        #expect(try SupabaseRowMapper.event(fromRow: Data(json.utf8)) == .unknown(type: "workoutPoll", sequence: 7))
    }

    // The columns are the truth: a payload key cannot change id, type or order.
    @Test func payloadCannotOverrideColumns() throws {
        let json = row(payload: #"{"chatID": "42", "senderID": "coach", "text": "hi", "id": "fake", "type": "notification", "sequence": 999, "createdAt": "2000-01-01T00:00:00Z"}"#)
        guard case .message(let message) = try SupabaseRowMapper.event(fromRow: Data(json.utf8)) else {
            Issue.record("expected a message")
            return
        }
        #expect(message.id == "m1")
        #expect(message.sequence == 7)
        #expect(message.createdAt > ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!)
    }

    @Test(arguments: [
        "not json",
        "[]",                                                                   // not one row
        row(payload: #"{"chatID": "42"}"#),                                     // message without text
        row(payload: #""just text""#),                                          // payload not an object
        #"{"sequence": 1, "id": "m1", "type": "message", "created_at": "2026-10-12T14:14:13Z"}"#, // no payload
        row(createdAt: "yesterday"),
    ])
    func unreadableRowThrows(json: String) {
        #expect(throws: (any Error).self) { try SupabaseRowMapper.event(fromRow: Data(json.utf8)) }
    }

    @Test func pageSkipsUnreadableRowsAndKeepsTheRest() throws {
        let json = "[" + [
            row(sequence: 1, id: "m1"),
            row(sequence: 2, id: "broken", payload: "{}"),
            row(sequence: 3, id: "p1", type: "workoutPoll", payload: "{}"),
            row(sequence: 4, id: "m2"),
        ].joined(separator: ",") + "]"
        let page = try SupabaseRowMapper.page(fromRows: Data(json.utf8), limit: 100)
        #expect(page.events.map(\.sequence) == [1, 3, 4])
        #expect(page.skippedCount == 1)
        #expect(page.hasMore == false)
    }

    // PostgREST has no hasMore: a full page means there may be more.
    @Test func fullPageHasMore() throws {
        let json = "[" + row(sequence: 1, id: "m1") + "," + row(sequence: 2, id: "m2") + "]"
        #expect(try SupabaseRowMapper.page(fromRows: Data(json.utf8), limit: 2).hasMore)
        #expect(try SupabaseRowMapper.page(fromRows: Data(json.utf8), limit: 3).hasMore == false)
    }

    @Test func emptyPage() throws {
        let page = try SupabaseRowMapper.page(fromRows: Data("[]".utf8), limit: 100)
        #expect(page.events.isEmpty)
        #expect(page.hasMore == false)
    }

    @Test(arguments: ["not json", #"{"events": []}"#])
    func pageThatIsNotAnArrayThrows(json: String) {
        #expect(throws: (any Error).self) { try SupabaseRowMapper.page(fromRows: Data(json.utf8), limit: 100) }
    }
}
