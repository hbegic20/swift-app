import Foundation
import Observation

/// The single source of truth for screens (rule 3). Socket and HTTP both
/// write through `ingest(_:)`; the same id arriving twice is stored once.
@MainActor
@Observable
public final class EventStore {
    /// Sorted by the server's `sequence`, oldest first (rule 10).
    public private(set) var messages: [ChatMessage] = []
    /// Sorted by the server's `sequence`, oldest first (rule 10).
    public private(set) var notifications: [AppNotification] = []
    /// The highest `sequence` seen so far. Catch-up asks for everything after it.
    public private(set) var lastSequence: Int?
    /// Raw event log, newest first.
    public private(set) var log: [LogEntry] = []

    private var readNotificationIDs: Set<String> = []
    private var nextLogID = 0
    private let maxLogEntries: Int

    public init(maxLogEntries: Int = 200) {
        self.maxLogEntries = maxLogEntries
    }

    public var unreadCount: Int {
        notifications.count { !readNotificationIDs.contains($0.id) }
    }

    /// Text for the unread badge, or `nil` when there is nothing unread.
    public var unreadBadge: String? {
        unreadCount > 0 ? "\(unreadCount) unread" : nil
    }

    public func isRead(_ notification: AppNotification) -> Bool {
        readNotificationIDs.contains(notification.id)
    }

    public func markAllNotificationsRead() {
        readNotificationIDs.formUnion(notifications.map(\.id))
    }

    /// The one write path for events. Returns the events that were new.
    @discardableResult
    public func ingest(_ events: [Event]) -> [Event] {
        var inserted: [Event] = []
        var messagesChanged = false
        var notificationsChanged = false

        for event in events {
            switch event {
            case .message(let message):
                if !messages.contains(where: { $0.id == message.id }) {
                    messages.append(message)
                    messagesChanged = true
                    inserted.append(event)
                }
            case .notification(let notification):
                if !notifications.contains(where: { $0.id == notification.id }) {
                    notifications.append(notification)
                    notificationsChanged = true
                    inserted.append(event)
                }
            case .unknown:
                break
            }
            if let sequence = event.sequence, sequence > (lastSequence ?? Int.min) {
                lastSequence = sequence
            }
        }

        if messagesChanged { messages.sort { $0.sequence < $1.sequence } }
        if notificationsChanged { notifications.sort { $0.sequence < $1.sequence } }
        return inserted
    }

    public func appendLog(_ kind: LogEntry.Kind, _ text: String, date: Date = Date()) {
        log.insert(LogEntry(id: nextLogID, date: date, kind: kind, text: text), at: 0)
        nextLogID += 1
        if log.count > maxLogEntries {
            log.removeLast(log.count - maxLogEntries)
        }
    }
}

public struct LogEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// A new event from the live socket.
        case live
        /// A new event from HTTP catch-up.
        case catchUp
        /// An event that was already in the store.
        case duplicate
        /// An event with a type this app does not know.
        case unknown
        /// A frame that could not be read.
        case unreadable
        /// Connection status changes and errors.
        case status
    }

    public let id: Int
    public let date: Date
    public let kind: Kind
    public let text: String
}
