# Gym app: WebSocket demo

A small iOS demo app for testing how a WebSocket should be integrated into a
Swift app. It covers two features: messaging and in-app notifications. It is
a test bench, not the production gym app.

This repository starts empty. Everything is built from this file.

## Who you are working with

The developer comes from web development and is new to Swift and Xcode.
Explain Swift-specific things in one or two plain sentences when they come
up, and give exact steps for anything that has to be done in the Xcode UI.

## Target layout

| Folder | What it is |
|---|---|
| `SocketKit/` | Local Swift package with all the logic and its unit tests |
| `DemoApp/` | The SwiftUI demo app, kept thin |
| `TestServer/` | Local WebSocket and HTTP server for testing |
| `TestPayloads/` | Sample push notifications (`.apns`) for the simulator |

## Architecture rules

These decisions are already made. Follow them, and say so before deviating.

1. **One socket for everything.** Messaging and notifications share a single
   WebSocket. Every event carries a `type` field and the app routes on it.
2. **Use the built-in WebSocket.** `URLSessionWebSocketTask`, no third-party
   library.
3. **The local store is the source of truth.** Screens read only from the
   store. Socket and HTTP both write into it through one function, and the
   same item arriving twice is stored once (match by `id`).
4. **The socket lives only while the app is on screen.** Start it when the
   scene becomes active, cancel it when the app goes to the background. iOS
   cuts background connections anyway.
5. **Confirm the connection before calling it connected.** `resume()` returns
   before the connection exists. Send a ping and wait for the pong first.
   Otherwise a dead server looks like a successful connect and the retry
   delay never grows.
6. **Catch up before going live.** After every successful connect, fetch what
   was missed over HTTP, then handle live events. Anything sent while the app
   was disconnected is otherwise lost.
7. **Reconnect with growing delays.** 1s, 2s, 4s, up to 30s, with about 20
   percent random jitter. Reset the delay after a successful connect.
8. **Heartbeat.** Ping every 25 seconds. If a ping fails, close the socket so
   the reconnect logic takes over.
9. **Unknown event types are ignored, never an error.** Old app versions must
   survive a newer server. One unreadable event is skipped, not treated as a
   broken connection.
10. **Order comes from the server.** Sort by the server's `sequence`, not by
    the phone clock.
11. **Push is for when the app is closed, and it is only a hint.** On a push,
    sync from the server. Never build a message out of the push text.
12. **Logic lives in the package, the app target stays thin.** Anything with
    an `if` in it belongs in `SocketKit` with a unit test.

## Designing for tests

The logic must be testable without a network, a simulator, or real waiting.

- Put the socket behind a protocol whose `connect()` returns a stream of
  events. Tests use a fake that follows a script: fail, fail, connect, drop.
- Put waiting behind a protocol too, so tests record the requested delays
  instead of sleeping.
- Pass the random number for jitter as a parameter, so tests get fixed
  results.
- No test may depend on the real clock or the real network.

## Event protocol

Server to app, over the socket, one JSON object per frame:

```json
{"type": "message", "id": "m1", "chatID": "42", "senderID": "coach", "text": "Great session!", "createdAt": "2026-10-08T09:00:00Z", "sequence": 7}
{"type": "notification", "id": "n7", "title": "Class starts in 10 min", "body": "Leg day, studio 2", "workoutID": "legs-1", "createdAt": "2026-10-08T09:05:00Z", "sequence": 8}
```

HTTP, used for catching up:

- `GET /events?after={sequence}` returns
  `{"events": [...], "hasMore": false}` with the same objects as above, oldest
  first. Without `after` it returns everything.

Dates are ISO 8601 without fractional seconds. One shared `sequence` counter
covers both event types, so a single number says how far the app is caught up.

## Build order

Do these in order. Finish and verify each one before starting the next.

1. **Check the tools.** Confirm full Xcode is installed and selected
   (`xcodebuild -version` prints a version). If it reports only Command Line
   Tools, stop and help the developer fix that first.
2. **Create `SocketKit`.** Event decoding, reconnect policy, the connection
   loop, and the store with an unread count for notifications. Unit tests for
   each rule above that can be tested without a network.
3. **Build the test server.** Requirements:
   - Accepts WebSocket connections and serves `GET /events`.
   - Keeps events in memory with sequence numbers, so catch-up works.
   - Terminal commands while running: send a message, send a notification,
     send an event with an unknown type, drop all connections, list clients.
   - No extra installs if possible. Try a Swift executable using the Network
     framework first. If that grows past roughly 200 lines or gets fragile,
     stop and ask the developer before bringing in Node or any dependency.
4. **Create the app project.** Do not write `project.pbxproj` by hand. Ask the
   developer to create it in Xcode (File, New, Project, iOS App, SwiftUI) into
   `DemoApp/`, then add the local `SocketKit` package to it. Give exact
   click-by-click steps.
5. **Build the demo screen.** One screen with:
   - Connection status: connecting, live, or waiting to retry with the delay.
   - Message list.
   - Notification list with an unread badge.
   - A raw event log showing every event as it arrives, newest first.
6. **Add push handling.** Ask for notification permission from a button, not
   on launch. Create sample `.apns` files in `TestPayloads/` and check that
   tapping a push opens the right place and triggers a sync.
7. **Run the manual checklist below** together with the developer.

## Commands

```
# Package tests
cd SocketKit && swift test

# Which simulators exist (names differ per Xcode version)
xcrun simctl list devices available

# Build the app for a simulator
xcodebuild -project DemoApp/DemoApp.xcodeproj -scheme DemoApp \
  -destination 'platform=iOS Simulator,name=<simulator name>' build

# Send a sample push to the running simulator
xcrun simctl push booted <bundle id> TestPayloads/message.apns
```

## Working rules

- Build after every change. Do not say something works until the build passed
  and the relevant tests ran. If something could not be checked, say that.
- For a logic bug found by hand, first write a unit test that fails because
  of it, then fix it.
- Ask before adding any third-party dependency.
- The simulator reaches the test server at `localhost`. A real phone needs
  the Mac's network address instead.
- Production code uses `wss://` and `https://` only. If the plain `ws://`
  connection to the local test server is blocked, allow local networking only
  (`NSAllowsLocalNetworking`). Never use `NSAllowsArbitraryLoads`.
- Never commit secrets: no `.p8` push keys, no access tokens.
- Commit in small steps with clear messages. Do not push unless asked.

## Manual checklist

The demo is done when all of these behave as described.

| Do this | Expect |
|---|---|
| Start the server, launch the app | Status goes to live |
| Send a message from the server terminal | It appears in the app at once |
| Send a notification from the server terminal | It appears and the unread badge goes up |
| Drop connections from the server | Status shows retrying, then live again by itself |
| Stop the server for a minute | The retry delay grows: 1s, 2s, 4s and so on |
| Start the server again | The app reconnects without being touched |
| Stop the server, add two events to it, start it | Both appear after reconnect, in order, once each |
| Put the app in the background, then return | Socket closes, then reconnects and catches up |
| Send an event with an unknown `type` | Logged as unknown, nothing breaks |
| Drag a sample `.apns` file onto the simulator, tap the banner | The app opens and syncs |

## Out of scope

- Sending real pushes through Apple's servers. That needs a physical phone, a
  paid Apple Developer account and a push key.
- Sending messages from the app, read receipts, typing indicators.
- A production backend, login, and App Store release.