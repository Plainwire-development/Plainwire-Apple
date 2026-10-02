# Architecture

Plainwire uses one backend: `https://plainwi.re`. `AppModel` owns the state shown by SwiftUI. `PlainwireAPIClient` handles HTTP requests, and `PlainwireRealtimeClient` handles the WebSocket connection. The two clients are Swift actors.

## Sessions and sync

Login sets a `pw_session` cookie. The app restores it with `GET /api/me` and sends the session's CSRF token on changes. Passwords are not stored by the app.

Secondary tools use an ephemeral `WKWebView` presented as a sheet. Before loading the web client, the app copies the active session cookie into WebKit's cookie store. Web sign-out removes the native session too. Closing the sheet refreshes the account and server state. The web store does not persist between app sessions. A retained `WorkspaceController` owns the WebKit view, dialogs, and downloads so subsequent tool presentations preserve their state. Sign-out cancels and clears it.

`GET /api/sync` refreshes conversations, servers, and friends. The server supplies the cursor for later syncs. Opening a room fetches its messages; the earlier-messages button loads older pages while preserving the first visible row. Reconnection refreshes the live tail and fills gaps with paginated requests. Context jumps use the bounded message-context endpoint and offer a return to the latest messages. The app keeps up to 12 recent rooms in memory.

Realtime events update messages, reactions, typing, and presence. After a disconnect, the socket reconnects, restores subscriptions, and syncs with the server. The server remains the source of truth.

The native model consumes connection states and events through one ordered stream. Presence uses only the current socket's snapshots and updates; saved profile status is never evidence that someone is connected. Sparse snapshots confirm omitted watched users are offline; new watches and disconnected sockets remain unknown. Profile sheets add temporary watches, and server resync restores watches/subscriptions. Hello and pong deadlines detect silent connections. Detail requests are coalesced separately so they cannot delay presence or typing events.

## Chat and media

Messages use `LazyVStack`. Drafts are keyed by room, saved per account with debounced writes, restored after relaunch, and removed on sign-out. Sends and uploads capture their original room. Session generations discard old asynchronous results; bounded deletion records keep overlapping fetches from restoring removed messages. Parsed Markdown, attachments, and timestamps are reused until message content changes. New messages scroll into view only when the reader is near the bottom. Loading older messages keeps the previous first row in place.

Uploads stream from file URLs. Attachment Markdown is separated from visible message text. `||attachment||` hides that attachment until the reader reveals it. Images and avatars use a bounded memory cache and thumbnails decoded in a utility task. Attachment extraction and code/spoiler parsing live in the portable core and have regression tests. Authenticated downloads are staged in a session-specific temporary folder for Quick Look and removed on sign-out. Video playback starts when tapped.

AVKit platform views provide video controls directly. A shared playback owner cancels preparation, removes observers, and releases media when rows disappear. Voice-note progress updates run only during playback. Images use delegate-owned disk downloads with transfer and dimension limits before decoding. API responses are not cached to disk, and API redirects must remain on the configured origin.

## Native calling

`CallController` owns a single call or voice-channel room, permissions, participant state, native audio/video tracks, camera capture, relay refresh, and teardown. `NativeCallPeer` owns one native WebRTC transport per remote participant. The app pins the WebRTC XCFramework package to 154.0.0. The existing authenticated Swift API client reads `GET /api/rtc-config`; the existing realtime socket sends the server’s `call_*` and `voice_*` commands. No web assets, JavaScript, WebKit media engine, separate web session, or backend changes are used for calls.

The higher user ID offers, matching the existing signaling protocol. Per-peer task queues serialize SDP and ICE; bounded candidate buffers hold ICE until its description is applied. Worker-thread delegates explicitly hop to MainActor. Room identity and lifecycle generations reject stale events and completions. Reconnection rebuilds transports and rejoins the current room; mute/deafen state is republished after joining. Sign-out, revoked access, superseded sessions, and hang-up stop capture and close transports. The floating native call panel overlays root navigation and can be dragged, resized, reset, or minimized without stopping media. Shared layout bounds keep it reachable after window resizing and rotation. Native AppKit/UIKit pointer handlers measure window-coordinate movement from a fixed interaction anchor, avoiding SwiftUI GestureState executor callbacks. Account-wide call_presence is tracked independently of locally owned media, so website conversation calls can be displayed and explicitly transferred with call_join. The Mac sandbox allows incoming and outgoing UDP for native ICE/media, following [Apple’s network entitlement guidance](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server). The app includes a local-network usage description for direct peer connections.

## Platforms and notifications

iPhone uses tabs; iPad and Mac use split views. The app targets iOS 18 and macOS 15. Newer SwiftUI effects are guarded by OS availability checks.

Local notifications are sent for incoming messages while the app is running. Permission is requested from Settings. iOS stops the WebSocket in the background and syncs on return. Background iPhone push needs an APNs registration and delivery service. Native calls end before iOS suspends the realtime connection. Continuing calls in the background and receiving calls while suspended require background audio, CallKit, and push integration.
