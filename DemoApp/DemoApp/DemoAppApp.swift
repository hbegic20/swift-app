import SwiftUI
import SocketKit

@main
struct DemoAppApp: App {
    // The simulator reaches the test server at localhost.
    // A real phone needs the Mac's network address instead.
    @State private var connection = SocketConnection(
        store: EventStore(),
        transport: URLSessionWebSocketTransport(url: URL(string: "ws://localhost:8080")!),
        catchUpSource: HTTPCatchUpSource(baseURL: URL(string: "http://localhost:8081")!)
    )
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(connection: connection)
        }
        // The socket lives only while the app is on screen (rule 4).
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: connection.start()
            case .background: connection.stop()
            default: break
            }
        }
    }
}
