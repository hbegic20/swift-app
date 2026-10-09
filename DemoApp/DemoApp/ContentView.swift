import SwiftUI
import SocketKit

struct ContentView: View {
    let appDelegate: AppDelegate
    private var connection: SocketConnection { appDelegate.connection }
    private var store: EventStore { connection.store }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section("Connection") {
                        Text(connection.status.label)
                            .font(.headline)
                    }

                    Section("Push") {
                        // Ask from a button, never on launch.
                        Button("Enable notifications") {
                            Task { await appDelegate.requestPermission() }
                        }
                        Text("Permission: \(NotificationPermission.label(for: appDelegate.permissionStatus))")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Section("Messages (\(store.messages.count))") {
                        ForEach(store.messages.reversed()) { message in
                            VStack(alignment: .leading) {
                                Text(message.senderID).font(.caption).foregroundStyle(.secondary)
                                Text(message.text)
                            }
                        }
                    }
                    .id("messages")

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
                            if let badge = store.unreadBadge {
                                Text(badge)
                                    .padding(.horizontal, 6)
                                    .background(.red, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Button("Mark read") { store.markAllNotificationsRead() }
                        }
                    }
                    .id("notifications")

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
                // A tapped push says where to go (rule 11).
                .onChange(of: appDelegate.openedRoute) { _, route in
                    switch route {
                    case .messages: withAnimation { proxy.scrollTo("messages", anchor: .top) }
                    case .notifications: withAnimation { proxy.scrollTo("notifications", anchor: .top) }
                    case nil: break
                    }
                    appDelegate.openedRoute = nil
                }
            }
            .navigationTitle("Socket demo")
        }
    }
}
