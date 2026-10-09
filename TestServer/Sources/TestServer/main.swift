// Local WebSocket + HTTP server for the demo app. No dependencies.
//   swift run TestServer
// WebSocket on ws://localhost:8080, catch-up on http://localhost:8081/events
import Foundation
import Network

let webSocketPort: NWEndpoint.Port = 8080
let httpPort: NWEndpoint.Port = 8081
let pageSize = 50

/// All state lives on `queue`, which is why this is safe to mark Sendable.
final class Server: @unchecked Sendable {
    private let queue = DispatchQueue(label: "server")
    private var events: [[String: Any]] = []
    private var sequence = 0
    private var clients: [ObjectIdentifier: (connection: NWConnection, since: Date)] = [:]
    private var listeners: [NWListener] = []
    private let iso = ISO8601DateFormatter() // no fractional seconds by default

    // MARK: Commands

    func online() {
        queue.async { [self] in
            guard listeners.isEmpty else { return print("already online") }
            do {
                let ws = NWProtocolWebSocket.Options()
                ws.autoReplyPing = true // the app's ping must get a pong
                let wsParameters = NWParameters.tcp
                wsParameters.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
                listeners = [
                    try listen(wsParameters, on: webSocketPort, name: "WebSocket", accept: acceptWebSocket),
                    try listen(.tcp, on: httpPort, name: "HTTP", accept: acceptHTTP),
                ]
            } catch {
                print("could not start: \(error)")
            }
        }
    }

    func offline() {
        queue.async { [self] in
            listeners.forEach { $0.cancel() }
            listeners = []
            dropAll()
            print("offline. Events you add now are stored and served after `online`.")
        }
    }

    func publish(_ type: String, _ fields: [String: String]) {
        queue.async { [self] in
            sequence += 1
            var event: [String: Any] = fields
            event["type"] = type
            event["id"] = "\(type.prefix(1))\(sequence)"
            event["createdAt"] = iso.string(from: Date())
            event["sequence"] = sequence
            events.append(event)
            let data = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            for client in clients.values { send(data, to: client.connection) }
            print("#\(sequence) \(type) sent to \(clients.count) client(s)")
        }
    }

    func dropAll() {
        queue.async { [self] in
            let count = clients.count
            clients.values.forEach { $0.connection.cancel() }
            clients = [:]
            print("dropped \(count) connection(s)")
        }
    }

    func listClients() {
        queue.async { [self] in
            if clients.isEmpty { return print("no clients") }
            for client in clients.values {
                let seconds = Int(Date().timeIntervalSince(client.since))
                print("  \(client.connection.endpoint)  connected \(seconds)s")
            }
        }
    }

    func listEvents() {
        queue.async { [self] in
            if events.isEmpty { return print("no events") }
            for event in events {
                print("  #\(event["sequence"]!) \(event["type"]!) \(event["id"]!)")
            }
        }
    }

    // MARK: Listeners

    private func listen(
        _ parameters: NWParameters, on port: NWEndpoint.Port, name: String,
        accept: @escaping @Sendable (NWConnection) -> Void
    ) throws -> NWListener {
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = accept
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: print("\(name) listening on port \(port)")
            case .failed(let error): print("\(name) listener failed: \(error)")
            default: break
            }
        }
        listener.start(queue: queue)
        return listener
    }

    // MARK: WebSocket

    private func acceptWebSocket(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                clients[id] = (connection, Date())
                print("+ client \(connection.endpoint) (\(clients.count) total)")
            case .failed, .cancelled:
                if clients.removeValue(forKey: id) != nil {
                    print("- client \(connection.endpoint) (\(clients.count) total)")
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection)
    }

    /// Keeps a receive pending so pings get answered and closes are noticed.
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [self] data, context, _, error in
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            if error != nil || metadata?.opcode == .close {
                connection.cancel()
                return
            }
            if let data, !data.isEmpty, metadata?.opcode == .text {
                print("client says: \(String(decoding: data, as: UTF8.self))")
            }
            receive(on: connection)
        }
    }

    private func send(_ data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "event", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    // MARK: HTTP

    /// Minimal HTTP/1.1: assumes the GET request arrives in one read, which
    /// holds for small requests on a local network.
    private func acceptHTTP(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, _, _ in
            let requestLine = String(decoding: data ?? Data(), as: UTF8.self)
                .components(separatedBy: "\r\n").first ?? ""
            let (status, body) = route(requestLine)
            print("HTTP \(requestLine) -> \(status)")
            let head = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func route(_ requestLine: String) -> (String, Data) {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let url = URLComponents(string: String(parts[1])), url.path == "/events"
        else { return ("404 Not Found", Data(#"{"error":"not found"}"#.utf8)) }

        let afterValue = url.queryItems?.first(where: { $0.name == "after" })?.value
        let after: Int
        if let afterValue {
            guard let parsed = Int(afterValue) else { return ("400 Bad Request", Data(#"{"error":"bad after"}"#.utf8)) }
            after = parsed
        } else {
            after = Int.min
        }

        let newer = events.filter { ($0["sequence"] as! Int) > after }
        let page: [String: Any] = ["events": Array(newer.prefix(pageSize)), "hasMore": newer.count > pageSize]
        return ("200 OK", try! JSONSerialization.data(withJSONObject: page, options: [.sortedKeys]))
    }
}

// MARK: Terminal

let help = """
commands:
  m [text]      send a message
  n [title]     send a notification
  u             send an event with an unknown type
  drop          drop all connections (server keeps listening)
  clients       list connected clients
  offline       stop listening and drop everyone (events can still be added)
  online        start listening again
  events        list stored events
  help, quit
"""

let server = Server()
server.online()
print(help)

while let line = readLine() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    let command = trimmed.prefix { $0 != " " }
    let argument = trimmed.dropFirst(command.count).trimmingCharacters(in: .whitespaces)

    switch command {
    case "m":
        server.publish("message", [
            "chatID": "42", "senderID": "coach",
            "text": argument.isEmpty ? "Great session!" : argument,
        ])
    case "n":
        server.publish("notification", [
            "title": argument.isEmpty ? "Class starts in 10 min" : argument,
            "body": "Leg day, studio 2", "workoutID": "legs-1",
        ])
    case "u": server.publish("workoutPoll", ["question": "Rate today's class"])
    case "drop": server.dropAll()
    case "clients": server.listClients()
    case "offline": server.offline()
    case "online": server.online()
    case "events": server.listEvents()
    case "help": print(help)
    case "quit", "exit": exit(0)
    case "": break
    default: print("unknown command, type help")
    }
}
