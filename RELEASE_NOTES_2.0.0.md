# Plainwire for Apple 2.0.0

The 2.0 update expands the native Apple client and improves compatibility with the Plainwire backend and reference frontend.

## Compatibility and reliability

- Empty and blocked conversations decode correctly when the server returns a null message preview. Optional profile, server, member, channel, and message metadata can be absent or null without breaking the whole screen. IDs remain checked and decimal string IDs decode without losing precision.
- Successful command responses work with or without a data payload, including invite revocation, notification actions, and group changes. Failed requests still report failure. Incorrect passwords are distinct from expired sessions.
- Response errors identify the endpoint and field. Authentication reads bypass cached responses. Temporary startup failures offer recovery without discarding the saved session; a failed sync panel no longer blocks a valid login.
- Sign-out clears room histories, loading flags, sync cursors, drafts, presence, image caches, attachment previews, and the embedded workspace. Session generations prevent older room requests from repopulating a new session.
- Reconnection refreshes the active room and catches up gaps longer than one message page. Realtime deletions cannot be resurrected by an overlapping fetch. Typing and subscription requests are reduced.
- Drafts belong to rooms. Sends and attachment uploads retain their destination when you switch rooms; failed sends preserve both the outgoing text and newer typing. Drafts are saved per account, restored after relaunch, and removed on sign-out.

## Native features

- Search all accessible messages, load further results, jump to context, and return to the live conversation.
- Forward messages to conversations or server channels. View channel pins and manage pins with the appropriate server permission.
- Create direct and group conversations, add members, rename groups, appoint moderators, remove members, close conversations, and leave groups.
- Browse unread conversations and message requests; accept or decline requests.
- Activity inbox with mentions, reactions, friend requests, mark-read, clear, and navigation actions.
- Record voice notes, attach them to a room's draft, and play received notes inline. Native attachment downloads use the active session and open in Quick Look.
- Code blocks with copy controls, hidden text spoilers, forwarding attribution, bot labels, role colors, and pin markers. Images inside a spoiler remain hidden; attachment syntax inside code remains literal.
- Server member panels and channel slow-mode settings. Friend search updates as you type, with friendship removal, blocking, and unblocking controls.

## Mac and interface

- New conversation and search commands, unread sidebar badges, hover actions, clear empty/loading/retry states, and errors visible inside sheets.
- Room restoration when switching between Messages and Servers. Wider native member panels animate when shown or hidden. Composer transitions and app animations respect reduced motion settings.
- Thumbnail decoding runs away from the main actor, with bounded image caching and reused message formatting.
- Native sheets adapt to smaller iPhone screens. A single main Mac window keeps the retained workspace and native selection consistent.

## Reference frontend coverage

The authenticated Workspace runs the deployed Plainwire frontend. Forums and Source Hub have sidebar entry points; live calls, GIF/sticker tools, developer applications, plugins, webhooks, custom server roles, audit logs, and other advanced tools remain available there. They are not all separate native screens.

The workspace stays alive when switching to native sections, routes without reloading for normal navigation, opens external links in the system browser, supports JavaScript confirmations and prompts, and handles uploads and downloads. Camera and microphone permissions are requested by WebKit when used.

## Validation and release status

The Linux checks cover the Swift core, backend-shaped response fixtures, HTTP command behavior, Markdown/attachment parsing, Swift syntax, and project/plist references. The application model is also type-checked with platform service stubs. These checks do not compile or execute SwiftUI, WebKit, AVFoundation, or Quick Look on Apple platforms.

Before publishing 2.0, run `./scripts/verify.sh`, build macOS Debug and Release in Xcode, build the iOS Simulator target, and complete the 2.0 checks in [QA.md](QA.md) with two accounts. Voice notes, live calling, file dialogs, notification delivery, and visual/scroll performance need real Apple-device testing. iPhone background notifications still require an APNs backend; local notifications operate while the app runs.
