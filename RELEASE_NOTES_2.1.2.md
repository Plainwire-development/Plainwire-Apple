# Plainwire Apple 2.1.2

The 2.1.1 drag crash report pointed to the SwiftUI GestureState updating callback. This patch replaces that path with native AppKit mouse handling on Mac and UIKit pan handling on iPhone/iPad. Movement uses stable window coordinates and one anchor per interaction, with animations disabled while manipulating the panel. The grip is larger; the menu also offers Center panel. Transient window dimensions and non-finite geometry are bounded before reaching the view or video stage.

Direct/group calls already active on the website now appear in the native app through account-wide call_presence snapshots. A panel shows that your call is active on another client and offers Move call here. The app only transfers after that action, joins the existing room without ringing it again, and preserves mute/deafen. Conversation rows mark ongoing calls, and their call action joins rather than restarts a room. Ending or disconnecting updates the displayed account state; another client taking over releases native media.

Permission or relay-loading failure before a join preserves the existing website session. Call rosters deduplicate participant IDs, repeated activation of the current call opens its panel, and disconnects release the camera-change lock.

Validation includes 49 core tests, repository/version checks, native WebRTC SDP/ICE and lifecycle smoke tests, and an optimized AppKit/SwiftUI pointer smoke test with repeated movement, resizing, cancellation, and actual call-panel mounting. Local macOS Debug/Release and iOS Simulator builds are checked before tagging; GitHub handles release packaging.

Live two-account website transfers and real touch/camera permissions still require device testing. The server only publishes account-wide presence for conversation calls; discovery of a voice channel occupied on another client needs server support. Native voice-channel calling is unchanged.
