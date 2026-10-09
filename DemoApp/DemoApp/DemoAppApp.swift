import SwiftUI
import SocketKit

@main
struct DemoAppApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(appDelegate: appDelegate)
        }
        // The socket lives only while the app is on screen (rule 4).
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: appDelegate.connection.start()
            case .background: appDelegate.connection.stop()
            default: break
            }
        }
    }
}
