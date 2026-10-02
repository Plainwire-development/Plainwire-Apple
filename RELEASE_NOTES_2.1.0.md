# Plainwire for Apple 2.1.0

This release makes everyday navigation and calling feel at home in the Swift app. It changes only the Apple client; the Plainwire backend and web client are unchanged. The marketing/client version is 2.1.0 and the bundle build number is 9.

## Settings and navigation

On Mac, open Settings with **⌘,** or **Plainwire → Settings**. Settings no longer take a sidebar slot. iPhone and iPad keep their touch settings entry. Native SwiftUI switches replace the custom button-based toggles, adopting system Liquid Glass on supported releases and retaining system accessibility, keyboard, and switch behavior on older releases.

Mac navigation focuses on Messages, Servers, Friends, and Activity. iPhone has five tabs, including You. Forums, Source Hub, developer integrations, and advanced server tools open from secondary menus in a sheet rather than a primary Workspace section.

## Native calling

Start a direct/group call from a conversation or with **⇧⌘K** on Mac. Select a server voice channel to join it. Incoming calls appear with Answer and Decline controls. The native call dock shows participants and provides microphone mute, deafen, camera video, reconnect, hang-up, and minimize controls while browsing the rest of the app.

Calls use the app's existing authenticated Swift WebSocket and the existing relay configuration endpoint. Native WebRTC 154.0.0 handles media, native AVFoundation handles permissions/camera capture, and Metal views render video. Calling loads no web page, JavaScript, or WebKit media component and requires no changes to Plainwire. The package version/revision and binary checksum are pinned; its license is bundled with the app.

Call teardown covers cancelled startup, permission failures, hang-up, sign-out, revoked access, and a session taken over by another client. SDP/ICE queues and lifecycle generations isolate late callbacks. Reconnection rejoins the current room and republishes mute/deafen state. Voice-note recording is disabled during a call to preserve microphone ownership. The Mac sandbox includes incoming/outgoing network entitlements for native UDP media; a local-network permission explanation covers direct peer connections.

## Validation and limits

- Core regression tests and project/version consistency checks: 43 tests passed.
- Native local calling smoke: invitation token handling, permission denial, cancelled startup, busy-call preservation, mute/deafen restoration, unrelated room errors, reconnect, access revocation, real native SDP/ICE connection, incoming-audio disabling, and transport teardown.
- Mac Debug and iOS Simulator builds; universal Mac Release packaging and bundled framework paths and signature checks.

The local smoke uses disabled capture tracks and no Plainwire account. Two-account calling against the live server, physical-device audio routing, camera capture/video interoperability, and older-system appearance remain manual checks in [QA.md](QA.md). Screen broadcasting, CallKit, incoming push while suspended, and background calling are not included. iPhone/iPad calls end when the app enters the background. Existing minimum requirements remain macOS 15 and iOS/iPadOS 18.
