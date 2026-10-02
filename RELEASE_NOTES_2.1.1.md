# Plainwire Apple 2.1.1

Friends now show Offline when the live server snapshot omits them, matching the web client. Presence remains unavailable during a disconnect or before a new watch has received its snapshot. Profile sheets watch their displayed person, the native client publishes its selected status, and realtime resync restores presence watches and room subscriptions. Older online-list snapshots are supported too.

Calls now use a floating panel over navigation. Drag the top handle to move it and the lower-right handle to resize it. The panel stays inside the available window when resized or rotated. Its menu offers small/large sizes and resets position and size; minimizing preserves audio and access to mute and hang-up. Video tiles adapt to its width, and the scrollable participant/error area keeps call controls visible.

A second incoming call no longer replaces an unanswered invitation. Stale invitation tokens cannot dismiss the current invitation. Disconnects cancel pending call startup and deadlines, reconnects discard buffered signaling, and old peer errors cannot update a replacement call.

Live two-account presence/calling, camera permissions, and touch/VoiceOver interaction still require device testing. Background iOS calling remains outside this release’s scope.

Validation: 46 core tests, Swift syntax and repository/version checks, macOS universal Debug and iOS Simulator Debug builds, and native local WebRTC SDP/ICE calling smoke tests passed using Xcode 27. The release workflow performs its Xcode 26.6 builds and universal packaging.
