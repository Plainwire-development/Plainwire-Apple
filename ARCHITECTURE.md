# Architecture

Plainwire uses one backend: `https://plainwi.re`. `AppModel` owns the state shown by SwiftUI. `PlainwireAPIClient` handles HTTP requests, and `PlainwireRealtimeClient` handles the WebSocket connection. The two clients are Swift actors.

## Sessions and sync

Login sets a `pw_session` cookie. The app restores it with `GET /api/me` and sends the session's CSRF token on changes. Passwords are not stored by the app.

The Workspace tab uses an ephemeral `WKWebView`. Before loading the web client, the app copies the active session cookie into WebKit's cookie store. Web sign-out removes the native session too. Returning to native tabs refreshes the account and server state. The web store does not persist between app sessions. A retained `WorkspaceController` owns the WebKit view, dialogs, and downloads so switching native sections preserves the web workspace. Sign-out cancels and clears it.

`GET /api/sync` refreshes conversations, servers, and friends. The server supplies the cursor for later syncs. Opening a room fetches its messages; the earlier-messages button loads older pages while preserving the first visible row. Reconnection refreshes the live tail and fills gaps with paginated requests. Context jumps use the bounded message-context endpoint and offer a return to the latest messages. The app keeps up to 12 recent rooms in memory.

Realtime events update messages, reactions, typing, and presence. After a disconnect, the socket reconnects, restores subscriptions, and syncs with the server. The server remains the source of truth.

## Chat and media

Messages use `LazyVStack`. Drafts are keyed by room, saved per account with debounced writes, restored after relaunch, and removed on sign-out. Sends and uploads capture their original room. Session generations discard old asynchronous results; bounded deletion records keep overlapping fetches from restoring removed messages. Parsed Markdown, attachments, and timestamps are reused until message content changes. New messages scroll into view only when the reader is near the bottom. Loading older messages keeps the previous first row in place.

Uploads stream from file URLs. Attachment Markdown is separated from visible message text. `||attachment||` hides that attachment until the reader reveals it. Images and avatars use a bounded memory cache and thumbnails decoded in a utility task. Attachment extraction and code/spoiler parsing live in the portable core and have regression tests. Authenticated downloads are staged in a session-specific temporary folder for Quick Look and removed on sign-out. Video playback starts when tapped.

## Platforms and notifications

iPhone uses tabs; iPad and Mac use split views. The app targets iOS 18 and macOS 15. Newer SwiftUI effects are guarded by OS availability checks.

Local notifications are sent for incoming messages while the app is running. Permission is requested from Settings. iOS stops the WebSocket in the background and syncs on return. Background iPhone push needs an APNs registration and delivery service. Live calls are available through the embedded web client; native call controls need separate implementation.
