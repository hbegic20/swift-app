import Foundation

/// A chat message pushed by the server.
public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let chatID: String
    public let senderID: String
    public let text: String
    public let createdAt: Date
    public let sequence: Int

    public init(id: String, chatID: String, senderID: String, text: String, createdAt: Date, sequence: Int) {
        self.id = id
        self.chatID = chatID
        self.senderID = senderID
        self.text = text
        self.createdAt = createdAt
        self.sequence = sequence
    }
}

/// An in-app notification pushed by the server.
public struct AppNotification: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let workoutID: String?
    public let createdAt: Date
    public let sequence: Int

    public init(id: String, title: String, body: String, workoutID: String?, createdAt: Date, sequence: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.workoutID = workoutID
        self.createdAt = createdAt
        self.sequence = sequence
    }
}

/// One event from the server, routed on its `type` field.
public enum Event: Equatable, Sendable {
    case message(ChatMessage)
    case notification(AppNotification)
    /// A type this app version does not know. Ignored, never an error (rule 9).
    case unknown(type: String, sequence: Int?)

    public var sequence: Int? {
        switch self {
        case .message(let message): message.sequence
        case .notification(let notification): notification.sequence
        case .unknown(_, let sequence): sequence
        }
    }
}

extension Event: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, sequence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "message":
            self = .message(try ChatMessage(from: decoder))
        case "notification":
            self = .notification(try AppNotification(from: decoder))
        default:
            // Keep the sequence if it is readable so catch-up can move past it.
            let sequence = try? container.decodeIfPresent(Int.self, forKey: .sequence)
            self = .unknown(type: type, sequence: sequence)
        }
    }
}

/// One page of `GET /events`.
public struct EventPage: Equatable, Sendable {
    public let events: [Event]
    public let hasMore: Bool
    /// Entries that could not be read and were skipped.
    public let skippedCount: Int

    public init(events: [Event], hasMore: Bool, skippedCount: Int = 0) {
        self.events = events
        self.hasMore = hasMore
        self.skippedCount = skippedCount
    }
}

public enum EventDecoder {
    /// Decodes one socket frame. Throws if the frame is unreadable;
    /// an unknown `type` is not an error and returns `.unknown`.
    public static func decode(_ data: Data) throws -> Event {
        try makeDecoder().decode(Event.self, from: data)
    }

    /// Decodes a catch-up page. One unreadable entry is skipped, not fatal.
    public static func decodePage(_ data: Data) throws -> EventPage {
        let raw = try makeDecoder().decode(RawPage.self, from: data)
        let events = raw.events.compactMap(\.event)
        return EventPage(
            events: events,
            hasMore: raw.hasMore,
            skippedCount: raw.events.count - events.count
        )
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct RawPage: Decodable {
        let events: [LenientEvent]
        let hasMore: Bool
    }

    /// Wraps one array entry so a bad entry does not fail the whole array.
    private struct LenientEvent: Decodable {
        let event: Event?

        init(from decoder: Decoder) throws {
            event = try? Event(from: decoder)
        }
    }
}
