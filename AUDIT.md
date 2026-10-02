# Client audit — October 1, 2026

This audit covers the Swift Apple client in this checkout. It does not establish the security or correctness of the remote Plainwire backend.

## Findings and fixes

| Area | Evidence and change |
| --- | --- |
| Video crash | Both local October 1 crash reports terminate in `_AVKit_SwiftUI` during Swift metadata initialization. Replaced SwiftUI `VideoPlayer` with native `AVPlayerView` on Mac and `AVPlayerViewController` on iOS. |
| Playback lifecycle | Video and voice notes now share cancellable preparation, failure handling, and observer cleanup. Leaving a row releases the player; backgrounding pauses it. Buffers are bounded, and video cards retain their aspect ratio during loading. |
| False online indicators | Friends previously fell back to the saved profile status, and missing profile statuses decoded as online. Presence now comes exclusively from the current socket. Authoritative snapshots replace old entries; offline users lose their platform badges. Unknown presence is labeled separately. |
| Silent disconnects | Added deadlines for the initial hello and WebSocket pongs. Dead connections reconnect and invalidate presence and typing state. Connection states and events reach the UI through one ordered stream. |
| Delayed realtime updates | Detail requests no longer block the socket event consumer. Repeated detail events are coalesced and obsolete work is cancelled. |
| Session races | Old API results cannot restore authentication after sign-out. Account, moderation, friendship, profile, and invite operations discard old session results/errors. Old loading tasks cannot clear another session's loading flags. Sign-out clears delivered notifications too. |
| Revoked access | Revoked rooms reject queued messages and stale fetches. Room revisions prevent a pre-revocation request from restoring content after a later reopen. Removed conversation details and histories are purged during sync. |
| API redirect policy | Authenticated API requests reject redirects outside their origin, including scheme and port changes. Public media may redirect to HTTPS CDNs. Plaintext attachment requests to unrelated local services are rejected. |
| Image/download resource limits | Images download to disk rather than an unbounded memory buffer. Delegate-managed transfers enforce byte limits while downloading, including responses without a content length. Image metadata is checked before thumbnail decoding; images above 64 million pixels or 20,000 pixels per side are rejected. Thumbnail dimensions and cache costs are bounded. |
| Private cached content | API responses no longer use the disk cache. Session preview files, WebKit temporary downloads, memory image caches, and notifications are cleared on sign-out. Temporary files are cleaned up on failed staging. |
| Web workspace | Session-cookie rotations are copied back to native requests. Navigation/download decisions and capture permissions check the trusted origin. External subframes cannot open browsers automatically; overlapping JavaScript dialogs complete their earlier callbacks. |
| Message/UI behavior | Message lists deduplicate before building presentation dictionaries, preserve incoming realtime edits during initial loads, and bound inactive/live tails to 1,000 messages while retaining history being read. Timestamp grouping avoids integer subtraction overflow. Overlong sends/edits and attachment controls in unavailable rooms are disabled. Friends show text presence labels, and profile banners use the thumbnail cache. |
| Filenames | Preview/download names reject traversal, control characters, dot-directory names, and oversized Unicode filenames while preserving a useful extension. |

## Verification

- Portable core regression tests, Swift syntax, project references, and property lists: `./scripts/verify.sh`.
- Universal Mac Release and iOS Simulator Debug builds with Swift warnings treated as errors.
- Local Mac playback smoke: generates an MP4, mounts the actual native controls five times, plays it, checks teardown, cancels preparation, and checks missing-file recovery.
- Local HTTP transfer smoke: checks small downloads, rejection of known and unknown oversized responses during transfer, and an in-flight session restore across sign-out. This test caught that Foundation's async download convenience method bypassed the required progress callbacks; the implementation now uses delegate-owned tasks.

See [QA.md](QA.md) for repeatable smoke commands and remaining device/account checks. Two-account backend presence transitions, authenticated remote media, fullscreen behavior on real devices, and two-account native calls still need manual testing. See the 2.1 release notes for native calling verification. The client displays authoritative server presence; a stale status supplied by the server requires a backend fix.
