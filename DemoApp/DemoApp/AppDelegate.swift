import SwiftUI
import UserNotifications
import SocketKit

/// Receives push events from iOS. Owns the connection so a push can trigger
/// a sync even when it launched the app.
@Observable
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // The simulator reaches the test server at localhost.
    // A real phone needs the Mac's network address instead.
    let connection = SocketConnection(
        store: EventStore(),
        transport: URLSessionWebSocketTransport(url: URL(string: "ws://localhost:8080")!),
        catchUpSource: HTTPCatchUpSource(baseURL: URL(string: "http://localhost:8081")!)
    )
    /// Where the last tapped push wants to go. The screen scrolls there.
    var openedRoute: PushRoute?
    /// What iOS reports, re-read each time the app becomes active.
    var permissionStatus: UNAuthorizationStatus = .notDetermined

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes, or a tap that launched the app is missed.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        await refreshPermission()
    }

    /// The user can change the permission in the Settings app at any time.
    func refreshPermission() async {
        permissionStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // A push arrived while the app is on screen: sync, and still show the banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await connection.syncAfterPush()
        return [.banner, .sound]
    }

    // The user tapped a push: go to the right place and sync (rule 11).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = PushRoute(userInfo: response.notification.request.content.userInfo)
        await MainActor.run {
            connection.store.appendLog(.status, "push tapped: \(route?.label ?? "no route")")
            openedRoute = route
        }
        await connection.syncAfterPush()
    }
}
