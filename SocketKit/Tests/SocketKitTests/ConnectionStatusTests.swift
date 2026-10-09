import Testing
@testable import SocketKit

// The text the demo screen shows for each status.
@Suite("Connection status label")
struct ConnectionStatusTests {
    @Test func labels() {
        #expect(ConnectionStatus.disconnected.label == "disconnected")
        #expect(ConnectionStatus.connecting.label == "connecting")
        #expect(ConnectionStatus.live.label == "live")
        #expect(ConnectionStatus.waitingToRetry(delay: 4.2).label == "retrying in 4.2s")
    }
}
