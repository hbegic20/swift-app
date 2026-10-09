import SwiftUI
import SocketKit

struct ContentView: View {
    let connection: SocketConnection
    private var store: EventStore { connection.store }

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Text(connection.status.label)
                        .font(.headline)
                }

                Section("Messages (\(store.messages.count))") {
                    ForEach(store.messages.reversed()) { message in
                        VStack(alignment: .leading) {
                            Text(message.senderID).font(.caption).foregroundStyle(.secondary)
                            Text(message.text)
                        }
                    }
                }

                Section {
                    ForEach(store.notifications.reversed()) { notification in
                        VStack(alignment: .leading) {
                            Text(notification.title)
                                .fontWeight(store.isRead(notification) ? .regular : .bold)
                            Text(notification.body).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text("Notifications")
                        Text("\(store.unreadCount) unread")
                            .padding(.horizontal, 6)
                            .background(.red, in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Mark read") { store.markAllNotificationsRead() }
                    }
                }

                Section("Event log (newest first)") {
                    ForEach(store.log) { entry in
                        VStack(alignment: .leading) {
                            Text("\(entry.date.formatted(date: .omitted, time: .standard))  \(entry.kind.rawValue)")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(entry.text).font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Socket demo")
        }
    }
}
