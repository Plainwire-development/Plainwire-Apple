# Plainwire for Apple

Plainwire is a chat app for Mac, iPhone, and iPad. This is its SwiftUI client. It connects to the same account and messages as [plainwi.re](https://plainwi.re).

## Install on Mac

You need macOS 15 or later. Once a GitHub Release is published, install the latest Mac build with:

```sh
curl -fsSL https://github.com/Plainwire-development/Plainwire-Apple/releases/latest/download/install-macos.sh | bash
```

The installer downloads the universal Mac build, checks its SHA-256 hash, installs it in `~/Applications`, and opens it. To build from this checkout instead, install Xcode 26.6 or later and run:

```sh
./scripts/install-macos.sh
```

If you already have a `Plainwire.app` bundle, install it without Xcode:

```sh
./scripts/install-macos.sh --app /path/to/Plainwire.app
```

The installer removes the `com.apple.quarantine` attribute from the **installed Plainwire app only**. This lets an unsigned local build open without Gatekeeper's downloaded-app prompt. Install only a build you trust.

The [releases page](https://github.com/Plainwire-development/Plainwire-Apple/releases) also has the Mac ZIP and its checksum if you prefer a manual download.

## Update on Mac

To update an installed copy to the latest release, run:

```sh
curl -fsSL https://github.com/Plainwire-development/Plainwire-Apple/releases/latest/download/update-macos.sh | bash
```

The updater skips versions already installed, verifies the archive and swap helper against the release SHA-256 list, checks the app signature and version, then swaps the staged app with the installed one in a single filesystem operation. If verification or the swap fails, the installed app stays in place. It closes and reopens Plainwire when needed. Add `--no-open` with `bash -s -- --no-open` to leave it closed, or run `./scripts/update-macos.sh --release 1.2.0` from this checkout to select a release.

## Run on iPhone or iPad

Open `Plainwire.xcodeproj` in Xcode, select the `Plainwire` scheme, choose a simulator or device, and press Run. The app requires iOS or iPadOS 18 or later. A physical device needs your own Apple signing team in Xcode.

## What it does

This checkout is version **2.1.0**. On Mac, open Settings with **⌘,** or Plainwire → Settings; settings no longer occupy the sidebar. iPhone and iPad retain the You entry. Settings use native SwiftUI switches, which adopt Liquid Glass on supported systems and the standard appearance on older systems. Option (⌥)-scroll seeks inline videos when enabled in Settings → Chat. See [the changelog](CHANGELOG.md) and [2.1 release notes](RELEASE_NOTES_2.1.0.md).

Plainwire supports direct and group messages, channels, friends, reactions, replies, forwarding, pins, message search, message requests, an activity inbox, file uploads, attachment previews, voice-note recording and playback, spoiler text and attachments, inline video, and live presence. Room drafts survive navigation and relaunch and are cleared when you sign out. You can view other members' profiles, edit your own profile and images, manage account credentials and sessions, and create, join, and customize servers. Group controls include names, members, moderators, and leaving or closing a conversation. Server controls include appearance, your server profile, channels, slow mode, categories, members, and invite links. Images are cached and resized for the screen. On Mac and iPad, conversations use a wider split view; iPhone uses tabs.

Direct and group calls and server voice channels run in the Swift app using native WebRTC. Start a call from a conversation, answer the incoming call card, or select a server voice channel. The call dock provides microphone, deafen, camera, hang-up, and minimize controls while you browse chats. Call signaling uses the existing authenticated Swift realtime client; microphone and camera permission are requested by the native app. Calls do not load a web page or use Workspace. On iPhone and iPad, calls end when the app enters the background; background calling and incoming push require further platform integration.

Forums, Source Hub, developer apps, and remaining advanced server features are secondary tools opened in an authenticated web sheet. On Mac, find them under the sidebar’s More tools menu; on iPhone and iPad, use You → More tools. Notifications work while the app is running; background push on iPhone still needs APNs delivery.

## Development

Run `./scripts/verify.sh` for core tests and project checks. Run `./scripts/verify-calling.sh` on Mac to exercise native call lifecycle and a local WebRTC connection. The SwiftUI app also needs an Xcode build; both Mac and iOS Simulator builds run in CI.

To publish a release, update the app version in Xcode and push a matching tag such as `1.2.0` or `v1.2.0`. Creating a tag on GitHub works too. The release workflow builds a universal Mac app, checks both architectures, and uploads the ZIP, checksum, and installer. It also checks the newest version tag when the workflow itself changes, so an earlier tag can be picked up.

The app pins [WebRTC 154.0.0](https://github.com/stasel/WebRTC/tree/154.0.0) as an Xcode Swift package dependency; Xcode verifies the binary artifact checksum. The WebRTC license is included in the app bundle.

The app code is in `App/`, the API and realtime client are in `Sources/PlainwireCore/`, and core tests are in `Tests/PlainwireCoreTests/`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the data flow and [QA.md](QA.md) for manual checks.
