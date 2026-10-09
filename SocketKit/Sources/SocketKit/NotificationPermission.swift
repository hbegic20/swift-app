import UserNotifications

/// Text for the permission line on the demo screen, from what iOS reports.
public enum NotificationPermission {
    public static func label(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "not asked yet"
        case .authorized: "allowed"
        case .denied: "denied (change it in the Settings app)"
        case .provisional: "allowed quietly"
        case .ephemeral: "allowed for this session"
        @unknown default: "unknown"
        }
    }
}
