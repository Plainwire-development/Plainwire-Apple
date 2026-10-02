# Changelog

## 2.1.1

- Fixed friends incorrectly showing “Presence unavailable” when omitted from the server’s sparse snapshot. Offline status now requires a completed live watch snapshot; disconnected and newly watched users remain unknown until refreshed.
- Added legacy online-list snapshots, live profile watches, self presence updates, and presence/subscription recovery after a server realtime resync.
- Replaced the fixed call dock with a floating panel: drag its top handle, resize its lower-right corner, minimize it, or reset it from the panel menu. Video tiles follow the panel width and controls remain available while content scrolls.
- Preserved unanswered invitations when another caller rings, ignored stale invitation tokens, cancelled startup and timers on disconnect, and cleared old signals on reconnect.
- Bumped bundle, About, client user-agent, and build versions together. Added presence, panel-boundary, and calling lifecycle regression checks.

## 2.1.0

- Removed the Mac settings sidebar entry. Use ⌘, or the app menu; iPhone and iPad keep touch access.
- Replaced custom settings switches with native SwiftUI switches for system Liquid Glass on supported releases and standard controls on older systems.
- Added native WebRTC direct/group calling and server voice channels with incoming answer/decline, mute, deafen, camera video, native Metal rendering, reconnect, and hang-up controls. Calls stay in a compact dock while navigating the app.
- Calls use the existing Swift API/realtime connection and native media capture, with no web calling dependency or backend changes. iOS ends calls on backgrounding.
- Moved Workspace out of primary navigation and into a secondary tools sheet for features without native screens.
- Updated the bundle, build, About, and client user-agent versions together; added release consistency checks and native calling regression/smoke coverage.

## 2.0.3

- Scrolling over an inline video on Mac now scrolls the chat. Hold Option (⌥) while scrolling to seek through the video.
- Added “Option-scroll to seek videos” in You → Chat. The shortcut is enabled by default and can be disabled; the setting persists across launches.
- Added playback smoke checks for scroll forwarding, modifier seeking, toggling, and preserving paused playback.

## 2.0.2

- Fixed the Mac video crash by embedding native AVKit player controls. Added cancellable media loading, playback errors, and cleanup when leaving a chat.
- Fixed false online indicators, stale presence snapshots, silent socket disconnects, and detail requests delaying realtime updates.
- Hardened session transitions, revoked-room handling, API redirects, filenames, and cleanup of private content on sign-out.
- Added enforced download limits, image dimension checks, bounded live message caches, and reduced idle voice-note updates.
- Improved presence labels, video loading cards, profile banners, and message composer validation. See [the client audit](AUDIT.md) for findings and verification.

## 2.0.1

- Fixed sync failing when an empty conversation's `last_message_id` is the string `"null"`. The backend can serialize SQL null atoms this way; optional numeric fields now accept it as absent while required IDs and malformed numbers remain checked.
- Added regression coverage for the exact conversation index failure, optional message timestamps and references, and uncategorized channels.

## 2.0.0

- Fixed null response fields, command acknowledgements without data, password errors, and unsafe numeric ID conversion.
- Added native message search and context navigation, forwarding, pins, activity, group creation and moderation, message requests, voice notes, attachment previews, and channel slow mode.
- Improved room drafts, reconnect catch-up, unread acknowledgements, session cleanup, and navigation between messages and servers.
- Added spoiler-safe text and code rendering, member panels, hover actions, adaptive sheets, and background thumbnail decoding.
- Retained the authenticated web workspace across sections and added navigation, dialogs, download handling, and failure recovery.
- See [2.0 release notes](RELEASE_NOTES_2.0.0.md) for coverage and remaining Apple-platform validation.

## 1.2.1

- Reorganized server settings into focused pages with a wider Mac layout.
- Fixed invite responses that encode channel IDs as strings, and simplified data error messages.
- Added a member panel for group chats with live presence indicators and profile access.
- Added `@username` suggestions, mention highlights, and native mention notifications.
- Added a system Apple logo presence badge when Mac app activity is confirmed.

## 1.2.0

- Added native profile editing and member profile viewing.
- Added account security, recovery email, active sessions, and account lifecycle controls.
- Added server creation and joining, server appearance, per-server profiles, channels, categories, and invites.
- Added the authenticated Workspace tab for advanced web features, including voice channel access.
- Added an atomic Mac updater that verifies release downloads before swapping app bundles.

- Switched the client to `plainwi.re`.
- Added multiple file selection, spoiler attachments, and inline playback for MP4/MOV/M4V video.
- Cached and resized images and avatars, and added date dividers in chat.
- Improved notifications: channel names, muted conversations, spoiler-safe previews, duplicate suppression, and unread badges.
- Fixed Mac and iOS Simulator build errors.
- Added a Mac installer, universal release packaging, and a tag-driven GitHub release workflow.
- Simplified the project checks and documentation.

## 1.1.0

- Added replies, edits, deletes, reactions, friend requests, presence, typing, uploads, and local notifications.
- Added iPhone, iPad, and Mac layouts with light and dark mode.
- Improved scrolling and kept recent room histories in memory.

## 1.0.0

- First SwiftUI client for Plainwire messages, friends, and servers.
