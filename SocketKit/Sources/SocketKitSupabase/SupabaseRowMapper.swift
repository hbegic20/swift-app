import Foundation
import SocketKit

/// Turns rows of `public.events` into `Event`s.
///
/// A row keeps the type-specific fields in `payload`. The mapper flattens it
/// into the same JSON the test server sends, then reuses `EventDecoder`, so
/// unknown types (rule 9) and unreadable rows behave exactly the same for
/// both backends.
enum SupabaseRowMapper {
    enum MappingError: Error {
        case notAnObject
        case notAnArray
        case missingColumn(String)
    }

    /// One row, as delivered by Realtime or as one element of an HTTP result.
    static func event(fromRow data: Data) throws -> Event {
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MappingError.notAnObject
        }
        return try event(fromRow: row)
    }

    /// The result of `select * from events where sequence > … limit {limit}`.
    /// One unreadable row is skipped, not fatal.
    static func page(fromRows data: Data, limit: Int) throws -> EventPage {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw MappingError.notAnArray
        }
        let events = rows.compactMap { row in
            (row as? [String: Any]).flatMap { try? event(fromRow: $0) }
        }
        return EventPage(
            events: events,
            // PostgREST does not say whether more rows exist; a full page may.
            hasMore: rows.count >= limit,
            skippedCount: rows.count - events.count
        )
    }

    private static func event(fromRow row: [String: Any]) throws -> Event {
        guard let payload = row["payload"] as? [String: Any] else {
            throw MappingError.missingColumn("payload")
        }
        var flat = payload
        // The columns win over anything in the payload.
        flat["id"] = row["id"]
        flat["type"] = row["type"]
        flat["sequence"] = row["sequence"]
        flat["createdAt"] = row["created_at"]
        return try EventDecoder.decode(JSONSerialization.data(withJSONObject: flat))
    }
}
