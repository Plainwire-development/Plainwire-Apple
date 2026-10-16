# Plainwire for Apple 2.3.1

This release rebuilds the Mac navigation layout to fix lists that grew beyond the window, hid their first rows, and made scrolling back to the top unreliable.

## Window and scrolling fixes

- Mac navigation uses a stable native split layout sized to the actual window. Sidebars and conversation lists scroll independently inside their visible panes.
- The app identity, account footer, conversation search, and filters stay in place while lists scroll. The sidebar can be hidden or restored from the toolbar or Option-Command-S.
- Window resizing and switching between Messages, Servers, Forums, Friends, and Activity keep content inside the window and clear of the title bar.

## Interface overhaul

- Conversations use a lighter list with clear selection and hover states. Names have their own line, with compact dates and draft/mute information below the preview.
- The sidebar uses a consistent semantic background and simpler icons, with readable account information and clear separation from the scrolling list.
- Shared buttons draw continuous rounded corners consistently across supported OS versions, with disabled, pressed, keyboard-focus, and increased-contrast states.
- Conversation and channel empty states use smaller artwork and actions that adapt to the available width.

## Verification

Regression checks populate 75 conversations and a long sidebar in a titled, resizable Mac window. They check native view bounds, wheel scrolling in both directions, returning to the first row, resizing, and navigation changes. Existing core, forum sync, host isolation, media, calling, and iOS build checks remain part of release verification.

Release automation now skips duplicate packaging after all five install assets have been published for a tag.

Requires macOS 15 or later. The Mac download contains the universal Apple Silicon/Intel app, installer, updater, swap helper, and SHA-256 checksums. The source also targets iOS/iPadOS 18 or later.
