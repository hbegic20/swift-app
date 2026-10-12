# Gym app: WebSocket demo

A small iOS test bench for one WebSocket that carries two features: messaging
and in-app notifications. It is not the production gym app.

All commands below run from the repository root unless a `cd` is shown.

## What's in here

| Folder | What it is |
|---|---|
| `SocketKit/` | Swift package with all the logic (socket, reconnect, store, push routing) and its unit tests |
| `DemoApp/` | The SwiftUI demo app. It only creates the connection and shows the store |
| `TestServer/` | Local server: WebSocket on port 8080, HTTP catch-up on port 8081 |
| `TestPayloads/` | Sample push notifications (`.apns`) for the simulator |
| `scripts/run-app.sh` | Builds, installs and launches the app in the simulator |

No third-party libraries are used.

## How it works

[WebSockets: Web vs Swift](https://claude.ai/code/artifact/01a1d92e-5828-450a-a354-c441630f212d)
explains the main differences from a web WebSocket and walks through this
app's code: connect, reconnect, heartbeat, catch-up, decoding, the store and
the app wiring.

## Requirements

- macOS with full Xcode installed (tested with Xcode 27). Check it with:

  ```sh
  xcodebuild -version
  ```

  If it says only Command Line Tools are installed, point it at Xcode:

  ```sh
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```

- An iOS simulator. List the ones you have:

  ```sh
  xcrun simctl list devices available
  ```

## Quick start

Use two terminals.

**Terminal 1: start the test server** (keep it open, you type commands into it)

```sh
cd TestServer && swift run
```

**Terminal 2: build and run the app**

```sh
scripts/run-app.sh
```

The status at the top of the app should go to **live**. Type `m hello` in
terminal 1 and the message appears in the app.

The script uses the `iPhone 18 Pro` simulator. To use another one:

```sh
SIMULATOR="iPhone 17" scripts/run-app.sh
```

Press `Ctrl+C` to stop watching the app's output. The app keeps running.

## Test server commands

Type these into the terminal where the server runs:

| Command | What it does |
|---|---|
| `m [text]` | Send a message (default text: "Great session!") |
| `n [title]` | Send a notification (default title: "Class starts in 10 min") |
| `u` | Send an event with an unknown type (`workoutPoll`) |
| `drop` | Drop all connections. The server keeps listening |
| `offline` | Stop listening and drop everyone. You can still add events with `m` and `n` |
| `online` | Start listening again |
| `clients` | List connected clients |
| `events` | List stored events |
| `help` | Show the command list |
| `quit` | Stop the server (or press `Ctrl+C`) |

Events are kept in memory only. Restarting the server starts again from zero.

Check the HTTP catch-up endpoint directly:

```sh
curl 'http://localhost:8081/events'
curl 'http://localhost:8081/events?after=3'
```

## Unit tests

```sh
cd SocketKit && swift test
```

The tests use no network and no real waiting, so they finish in well under a
second.

## Build without running

```sh
xcodebuild -project DemoApp/DemoApp.xcodeproj -scheme DemoApp \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -derivedDataPath .build/DemoApp -quiet build
```

Or open `DemoApp/DemoApp.xcodeproj` in Xcode and press `Cmd+R`.

## Push notifications (simulator)

1. In the app, tap **Enable notifications** and then **Allow**. The
   permission line should say "allowed".
2. Send a sample push:

   ```sh
   xcrun simctl push "iPhone 18 Pro" none.DemoApp TestPayloads/message.apns
   xcrun simctl push "iPhone 18 Pro" none.DemoApp TestPayloads/notification.apns
   xcrun simctl push "iPhone 18 Pro" none.DemoApp TestPayloads/unknown.apns
   ```

   You can also drag an `.apns` file onto the simulator window.

| Payload | App open | App in background, banner tapped |
|---|---|---|
| `message.apns` | Banner shows, app syncs | App opens, scrolls to Messages, syncs |
| `notification.apns` | Banner shows, app syncs | App opens, scrolls to Notifications, syncs |
| `unknown.apns` | Banner shows, app syncs | App opens, logs "no route", syncs |

A push is only a hint. The app always fetches the content from the server and
never builds a message from the push text. Press `Cmd+Shift+H` in the
simulator to go to the Home screen.

Use the simulator's name instead of `booted` when more than one simulator is
running.

## VS Code tasks

`Cmd+Shift+P`, then **Tasks: Run Task**:

| Task | Same as |
|---|---|
| Start test server | `cd TestServer && swift run` |
| Run app in simulator | `scripts/run-app.sh` |
| Build app | the `xcodebuild` command above |
| Test SocketKit | `cd SocketKit && swift test` |

## Running on a real iPhone

The simulator reaches the server at `localhost`. A real phone cannot. Change
the two URLs in `DemoApp/DemoApp/AppDelegate.swift` to your Mac's network
address, for example `ws://192.168.1.20:8080` and `http://192.168.1.20:8081`.
Find the address with:

```sh
ipconfig getifaddr en0
```

The phone and the Mac must be on the same Wi-Fi.

## Troubleshooting

| Problem | Fix |
|---|---|
| App stays on "retrying" | The server is not running. Start it with `cd TestServer && swift run` |
| Server says the port is in use | Another server copy is running. Find it with `lsof -iTCP:8080 -sTCP:LISTEN`, then stop it with `Ctrl+C` in its terminal |
| `Unable to find application named 'Simulator'` | Xcode 27 replaced Simulator.app with DeviceHub. `scripts/run-app.sh` already handles this. Pull the latest version |
| Push fails with "Source is not authorized" | Notification permission is not granted. Tap **Enable notifications** in the app first |
| Push goes to the wrong simulator | Use the simulator name instead of `booted` |
| Simulator name not found | Run `xcrun simctl list devices available` and pass a name that exists via `SIMULATOR="..."` |

## Manual checklist

The full checklist the demo must pass is in `CLAUDE.md` under
"Manual checklist". It covers going live, live events, reconnecting with
growing delays, catch-up after an outage, background and return, unknown
event types, and push.
