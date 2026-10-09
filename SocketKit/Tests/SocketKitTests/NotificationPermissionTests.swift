import Testing
import UserNotifications
@testable import SocketKit

// The permission line on the demo screen shows what iOS really reports.
@Suite("Notification permission label")
struct NotificationPermissionTests {
    @Test func labels() {
        #expect(NotificationPermission.label(for: .notDetermined) == "not asked yet")
        #expect(NotificationPermission.label(for: .authorized) == "allowed")
        #expect(NotificationPermission.label(for: .denied) == "denied (change it in the Settings app)")
        #expect(NotificationPermission.label(for: .provisional) == "allowed quietly")
    }
}
