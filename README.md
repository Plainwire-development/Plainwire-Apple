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

## Run on iPhone or iPad

Open `Plainwire.xcodeproj` in Xcode, select the `Plainwire` scheme, choose a simulator or device, and press Run. The app requires iOS or iPadOS 18 or later. A physical device needs your own Apple signing team in Xcode.

## What it does

Plainwire supports direct messages, channels, friends, reactions, replies, file uploads, spoiler attachments, inline video, and live presence. Images are cached and resized for the screen. On Mac and iPad, conversations use a wider split view; iPhone uses tabs.

Notifications work while the app is running. Background push on iPhone and voice calls still need server and media work.

## Development

Run `./scripts/verify.sh` for core tests and project checks. The SwiftUI app also needs an Xcode build; both Mac and iOS Simulator builds run in CI.

To publish a release, update the app version in Xcode and push a matching tag such as `v1.2.0`, or publish a release for that tag on GitHub. The release workflow builds a universal Mac app, checks both architectures, and uploads the ZIP, checksum, and installer.

The app code is in `App/`, the API and realtime client are in `Sources/PlainwireCore/`, and core tests are in `Tests/PlainwireCoreTests/`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the data flow and [QA.md](QA.md) for manual checks.
