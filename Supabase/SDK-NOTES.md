# supabase-swift Realtime: observed behavior

Spike against the local project, supabase-swift 2.55.3, 2026-10-12.
A throwaway command-line tool subscribed to inserts on `events` while
`send.sh` sent events and dropped, stopped and restarted the server.
These findings decide how `SupabaseTransport` is written.

| # | Observed | What the transport does about it |
|---|---|---|
| 1 | `subscribeWithError()` returns once the server confirms the join: client `Connecting → Connected`, channel `subscribing → subscribed`, about 0.8s on a healthy server | `subscribed` is the confirmed connect: yield `.connected` (rule 5) |
| 2 | When the socket drops, the **channel stays `subscribed`**. Only the client status changes to `Disconnected` | Watch `realtimeV2.statusChange`; leaving `Connected` ends the stream |
| 3 | The SDK then reconnects by itself with its own backoff (7s base, doubling). Gaps of 85s and 87s were seen, longer than our 30s cap | After a drop, call `removeChannel` + `disconnect()` so our loop and `ReconnectPolicy` decide when to retry (rule 7) |
| 4 | After `removeChannel` + `disconnect()`, the SDK stays quiet, even when the server restarts | Confirms #3 works |
| 5 | A new channel on the same client after `disconnect()` subscribes normally | Each `connect()` creates a fresh channel |
| 6 | While the server is unreachable, `subscribeWithError()` **hung for 94s**, then threw `CancellationError` | Wrap it in our own timeout (10s, like `pongTimeout`) |
| 7 | Inserts made while not subscribed are **never delivered**, not even after the SDK rejoins | Catch up over HTTP after every `subscribed` (rule 6) |
| 7b | Right after Realtime itself (re)starts, the first subscription succeeds but an insert made ~3s later was **lost**: Realtime was still creating its replication slot. Once warm, inserts arrived | Nothing in the app can see this. A later reconnect's catch-up fetches it. Production Realtime restarts rarely, but it is a reason the store must never assume the live stream is complete |
| 8 | An insert arrives as `record: [String: AnyJSON]`: `sequence` number, `id`, `type`, `user_id`, `payload` object, `created_at` like `2026-10-12T14:14:13.5358+00:00` | Map to our `Event` by merging `payload` with `id`, `type`, `sequence`, `createdAt`; dates have a variable number of fractional digits |

Not verified: how fast the SDK notices a silently dead socket (for
example Wi-Fi gone, no TCP close). Its heartbeat runs every 25s with a
10s timeout, so detection should take up to about 35s; the heartbeat
failing shows up as #2 and is handled the same way.
