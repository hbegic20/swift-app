import Foundation

/// Where tapping a push should take the user. Read from the push's custom
/// keys, next to `aps`: `"type"` plus `"chatID"` or `"workoutID"`.
/// The push text itself is never turned into a message (rule 11).
public enum PushRoute: Equatable, Sendable {
    case messages(chatID: String?)
    case notifications(workoutID: String?)

    /// `nil` for an unknown or missing type: open the app, go nowhere special.
    public init?(userInfo: [AnyHashable: Any]) {
        switch userInfo["type"] as? String {
        case "message":
            self = .messages(chatID: userInfo["chatID"] as? String)
        case "notification":
            self = .notifications(workoutID: userInfo["workoutID"] as? String)
        default:
            return nil
        }
    }

    /// Short text for the event log.
    public var label: String {
        switch self {
        case .messages(let chatID): chatID.map { "messages (chat \($0))" } ?? "messages"
        case .notifications(let workoutID): workoutID.map { "notifications (workout \($0))" } ?? "notifications"
        }
    }
}
