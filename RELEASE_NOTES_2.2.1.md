# Plainwire for Apple 2.2.1

This patch improves small-window layouts, profile image loading, and visual consistency on Mac, iPhone, and iPad.

## Interface fixes

- Profile, account, group, server, and channel editors use native scrolling forms on Mac. Sheets have useful starting sizes and can be resized.
- Long profile text, member names, message previews, and timestamps keep their spacing. Message editing scrolls when its content exceeds the available height.
- The sidebar and account footer share one material. Account avatars retain their intended size and clipping, and the username stays visible below the account menu.
- Composer, chat, call, and sheet controls use consistent rounded borders. The chat header gives the conversation title more room.
- The separate Mac Settings window follows the account's light, dark, or system appearance preference. Existing Reduce Motion and Reduce Transparency support is preserved.

## Media performance

- DM rows, headers, and messages share decoded small avatars. Different display sizes share one download and can reuse the downloaded source for profile views.
- Cached images appear during the first layout, avoiding a placeholder flash when opening a DM.
- GIF cache accounting follows downsampled frame sizes, allowing more small animated avatars to stay in memory. Both image caches clear on sign-out or a host change.
- First-time GIF downloads still depend on the image size and the server connection.

## Verification

Core regression tests, Mac and iOS Simulator builds, and optimized native smoke checks cover GIF playback, cache budgets, one transfer for concurrent image sizes, host isolation, keyboard controls, and scrolling through long profiles and 40-member settings sheets at narrow sizes.

The Mac release includes the universal Apple Silicon/Intel app, installer, updater, swap helper, and SHA-256 checksums. macOS 15 or later is required; iPhone and iPad require iOS/iPadOS 18 or later.
