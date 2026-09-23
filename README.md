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

Plainwire supports direct messages, channels, friends, reactions, replies, file uploads, spoiler attachments, inline video, and live presence. You can view other members' profiles, edit your own profile and images, manage account credentials and sessions, and create, join, and customize servers. Server controls include appearance, your server profile, channels, categories, members, and invite links. Images are cached and resized for the screen. On Mac and iPad, conversations use a wider split view; iPhone uses tabs.

The Workspace tab opens the complete Plainwire web client inside the app with your active session. It provides advanced features that do not yet have native screens, including developer tools and the web calling interface. Microphone and camera access are requested when those web features need them; live media also depends on WebKit and device permissions. Native call controls are not implemented. Notifications work while the app is running; background push on iPhone still needs APNs delivery.

## Development

Run `./scripts/verify.sh` for core tests and project checks. The SwiftUI app also needs an Xcode build; both Mac and iOS Simulator builds run in CI.

To publish a release, update the app version in Xcode and push a matching tag such as `1.2.0` or `v1.2.0`. Creating a tag on GitHub works too. The release workflow builds a universal Mac app, checks both architectures, and uploads the ZIP, checksum, and installer. It also checks the newest version tag when the workflow itself changes, so an earlier tag can be picked up.

The app code is in `App/`, the API and realtime client are in `Sources/PlainwireCore/`, and core tests are in `Tests/PlainwireCoreTests/`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the data flow and [QA.md](QA.md) for manual checks.
