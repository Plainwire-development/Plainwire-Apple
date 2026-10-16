# Plainwire for Apple 2.3.2

This patch fixes the extra translucent bar that covered server and chat headers on Mac, with a focused pass on spacing and controls.

- Use one native split view for the sidebar, browser, and chat so macOS draws a single window title bar.
- Give connection notices and attachment progress their own space instead of covering page headers.
- Keep in-page bar backgrounds inside their bounds, including message history, requests, forum replies, and server settings.
- Make server and chat header buttons more compact, leave more room for names, align member headers, and remove a duplicate chat divider.
- Extend native layout checks with populated conversations, wrapped messages, members, notices, and title-bar drawing bounds. Retain independent scrolling and resizing checks.

Version 2.3.2, build 16. The release workflow verifies the core tests, native smoke checks, and iOS build before publishing the universal Intel/Apple Silicon Mac archive and update helpers.
