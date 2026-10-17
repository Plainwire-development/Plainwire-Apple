# Plainwire for Apple 2.3.3

Fix a Mac crash when closing More Tools / Source Hub or switching between searchable pages. SwiftUI could insert its search item into the window toolbar twice, causing an AppKit exception.

- Keep Mac forum, discussion, people, GIF, and forwarding searches in rounded page headers. Search remains visible below the title bar and supports Command-F, clearing, and keyboard input.
- Preserve native search presentation on iPhone and iPad.
- Add an optimized regression check using a real SwiftUI app window. Exercise rapid page changes, repeated workspace dismissal, forum navigation, and search keyboard focus with the app's macOS 15 deployment target.
- Run native UI checks on both macOS 26 and macOS 27 in CI, in addition to release verification.

Version 2.3.3, build 17. The release workflow checks core tests, native UI behavior, and the iOS build before publishing the universal Intel/Apple Silicon Mac archive and update helpers.
