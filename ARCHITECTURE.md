# Architecture

Plainwire uses one backend: `https://plainwi.re`. `AppModel` owns the state shown by SwiftUI. `PlainwireAPIClient` handles HTTP requests, and `PlainwireRealtimeClient` handles the WebSocket connection. The two clients are Swift actors.

## Sessions and sync

Login sets a `pw_session` cookie. The app restores it with `GET /api/me` and sends the session's CSRF token on changes. Passwords are not stored by the app.

`GET /api/sync` refreshes conversations, servers, and friends. The server supplies the cursor for later syncs. Opening a room fetches its messages; scrolling to the top loads older pages. The app keeps up to 12 recent rooms in memory.

Realtime events update messages, reactions, typing, and presence. After a disconnect, the socket reconnects, restores subscriptions, and syncs with the server. The server remains the source of truth.

## Chat and media

Messages use `LazyVStack`. Parsed Markdown, attachments, and timestamps are reused until message content changes. New messages scroll into view only when the reader is near the bottom. Loading older messages keeps the previous first row in place.

Uploads stream from file URLs. Attachment Markdown is separated from visible message text. `||attachment||` hides that attachment until the reader reveals it. Images and avatars use a bounded memory cache and decoded thumbnails. Video playback starts when tapped.

## Platforms and notifications

iPhone uses tabs; iPad and Mac use split views. The app targets iOS 18 and macOS 15. Newer SwiftUI effects are guarded by OS availability checks.

Local notifications are sent for incoming messages while the app is running. Permission is requested from Settings. iOS stops the WebSocket in the background and syncs on return. Background iPhone push needs an APNs registration and delivery service; voice calls need a media stack.
