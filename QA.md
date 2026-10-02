# Manual checks

Run `./scripts/verify.sh` and build the Mac and iOS Simulator targets before a release. The checks below need a running Plainwire server and two accounts.

## Local audit smoke tests

These Mac checks need no account. The playback test mounts controls in an invisible window and generates its own sample video:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -swift-version 6 -parse-as-library Sources/PlainwireCore/APIError.swift \
  App/Views/Chat/MediaPlayback.swift Tests/Manual/MediaPlaybackSmoke.swift \
  -o /tmp/plainwire-media-smoke
/tmp/plainwire-media-smoke
python3 Tests/Manual/TransferSmoke.py
```

The transfer test starts a temporary localhost HTTP server, compiles a temporary executable, checks byte limits with and without Content-Length, and checks that sign-out invalidates an in-flight session restore.

For the presence fix, disconnect the second account and verify that Friends, profile sheets, and member panels agree. Disable networking on the observing client and verify it displays unavailable presence after the socket deadline. Reconnect and confirm a fresh snapshot restores the correct state. Close or revoke a room during a slow fetch and verify that its content does not reappear.

## Mac install

- Run `./scripts/install-macos.sh` from a clean checkout. Confirm `~/Applications/Plainwire.app` opens.
- After publishing a release, run the README's curl command on a Mac without the checkout. Confirm it downloads, verifies, and opens the latest app. Run it again to check upgrades.
- Install a downloaded bundle with `--app`, then upgrade it with another bundle. Confirm the app opens and only the installed Plainwire bundle has its quarantine attribute removed.
- Run the README updater against an installed older version. Confirm it verifies the release, quits the running app, swaps it, and reopens the new version. Run it again and confirm it skips the download.
- Try an invalid release tag and a corrupt archive in a test destination. Confirm the existing app is intact and launches afterward.
- Resize the window and use the sidebar and keyboard shortcuts. Open Settings with ⌘, and from the app menu at the minimum window size; confirm there is no settings button in the Mac sidebar.

## Account and chat

- Sign in, restart, and confirm the session restores. Sign out and confirm private images are no longer shown.
- Open a direct message and a channel. Send, reply, edit, delete, and react from both accounts.
- Scroll up while a new message arrives. Confirm the view stays put and the new-message button appears.
- Load older messages and confirm the current row keeps its position.
- Check long messages and dates in light and dark mode, at large text sizes, and with VoiceOver.
- Open a group chat and check the member panel at wide and narrow window sizes. Confirm profile links and presence dots update when a second account connects, disconnects, or changes status.
- Type `@` in a group chat and a server channel. Pick a member, send the message, and confirm the recipient receives a mention notification and sees the message highlighted.
- Open a member profile from Friends and from a message author. Check the avatar, banner, bio, status, and message action.
- Edit your profile name, bio, status, avatar, banner, and theme. Restart and confirm the theme and account values persist.
- Change the username, email, and password. Review active sessions, sign out other sessions, and verify the current device remains signed in.

## Servers and workspace

- Create a server, edit its name, description, welcome message, icon, banner, and accent. Create a category and text channel; edit a channel name and topic.
- Set your nickname, avatar, and bio for one server. Confirm the global profile stays separate.
- Create and share an invite. Join from another account by pasting the code or link, then revoke it and confirm it can no longer be used.
- Open server settings on Mac and iPhone. Visit each section, edit appearance and profile, and verify invite lists load when `channel_id` is a string.
- Open Workspace after signing in. Confirm it opens without a second login. Change a setting there, return to a native tab, and confirm it refreshes. Sign out in Workspace and confirm the native app signs out.
- Check native microphone/camera/local-network permission denial and recovery on real Mac and iOS devices.

## Attachments

- Attach several files at once. Try an image, PDF, and MP4/MOV video.
- On Mac, scroll over a playing or paused video and its controls. Confirm the chat scrolls without seeking. Hold Option (⌥) while scrolling and confirm the video seeks. Turn off “Option-scroll to seek videos” in You → Chat and confirm Option-scroll also scrolls the chat. Toggle it with a video open, restart to check persistence, and check trackpad momentum and full-screen playback.
- Send an attachment as a spoiler. Confirm its image or video does not load until revealed and that it can be hidden again.
- Open a room with many repeated avatars and images. Scroll away and back; they should appear from cache without a visible reload.
- Try an unavailable image and a large upload. Confirm the error is readable and the rest of chat still works.

## Notifications and connection

- Enable notifications from Settings. Check previews on and off, sound on and off, and a muted direct message.
- With the app open to another room, receive a message. Confirm one notification appears with the right room name; tapping it opens that room.
- With the active room visible, confirm a new message does not produce an extra banner.
- Disconnect the network, reconnect, and confirm messages and presence catch up without duplicates.
- On iPhone, background and reopen the app. Confirm it reconnects and syncs.


## 2.0 release checks

- Use an account with an empty conversation and a blocked conversation. Confirm no decoding banner appears and the rest of sync loads.
- Revoke an invite, clear activity, accept a message request, add a group member, and change a group role. Confirm successful acknowledgements do not report an unreadable response.
- Enter an incorrect current password in account settings. Confirm it reports the credential error without signing out. Check an actually expired session separately.
- Switch between Messages and Servers repeatedly, including while server details are loading. Confirm each section restores its own room and the final selection stays selected.
- Draft different text in two rooms, restart, and confirm both restore. Start an upload in one, switch to the other, and confirm the resulting attachment belongs to the original draft. Fail a send, type new text while it is pending, and confirm both pieces survive.
- Sign out and sign in as another account after opening rooms. Confirm histories reload, pagination works, old drafts disappear, and old attachment previews and loading flags do not return.
- Disconnect one account while the other sends more than 50 messages. Reconnect and check ordering, edits, deletions, reactions, and unread counts. Receive several messages while at the bottom, then while scrolled up, then with the Mac window inactive.
- Search messages, load another page, open a very old result, follow a reply, and return to latest. Confirm a context jump does not mark the whole conversation read or unexpectedly jump to new arrivals.
- Forward to a direct message and to a channel in a server you have not opened yet. Pin/unpin with a moderator account and view pins from a member account.
- Create a group, add a member, rename it, appoint/remove a moderator, remove a member, close a conversation, and leave a group. Exercise backend permission denials too.
- View Activity, mark it read, clear it, and follow direct/channel and forum links. Check sidebar badges and notifications while browsing Friends or Settings.
- Record, cancel, stop, and attach voice notes. Test denied microphone access, the two-minute limit, interruptions/backgrounding, and playback after scrolling out of view.
- Open a protected PDF and image in Quick Look. Confirm downloads use the app session. Test names with spaces and Unicode, unavailable files, large files, and drag-and-drop uploads.
- Check text spoilers, an image inside a spoiler sentence, isolated spoiler attachments, and attachment syntax inside inline/fenced code. Hidden attachments must not load before reveal.
- Open a voice channel from native navigation, change sections during a live call, and return. Separately exercise secondary tool dialogs, uploads, downloads, reload errors, and external links. Check native calls on real devices.
- Resize the Mac window, switch appearance, enable Reduce Motion, and use VoiceOver and larger text. Check member-panel/composer animations, hover actions, keyboard commands, and all sheets on a narrow iPhone.

## 2.1 native calling and navigation

- Run `./scripts/verify-calling.sh` on Mac. It builds the app, checks invitation tokens and permission/startup cancellation, then negotiates native SDP/ICE between two local peers with capture tracks disabled. It does not contact Plainwire.
- Call between two signed-in accounts in both directions, including a Swift client and an existing Plainwire client. Check ringing, answer, decline, missed/cancelled calls, and group call membership.
- Join a server voice channel. Check mute, deafen restoring the prior mute state, participants leaving/rejoining, camera on/off, and native remote video.
- Minimize the call and browse Messages, Servers, Friends, and Activity. Open and close a sheet during a call. Confirm audio persists and Workspace never opens for calling.
- Drop the network, restore it, and reconnect. Check that the room and mute state return without replaying stale SDP/ICE. Check a full room, denied access, an expired invite, a second incoming call, revoked access, and another client taking over a call.
- Hang up or sign out during permissions, relay loading, connection negotiation, and camera startup. Confirm the microphone/camera indicators turn off and no old call returns after another sign-in.
- On iOS, background the app during a call. Confirm capture stops and the call ends; return and check native chat reconnects. Background calling is not included in 2.1.
- On macOS/iOS 26 or newer, verify native Liquid Glass switches with keyboard, VoiceOver, increased contrast, and Reduce Motion. On macOS 15/iOS 18, verify ordinary native switches and fallback buttons.
- Check Mac Settings via ⌘, and the app menu. Check the five iPhone tabs and iPad touch settings access. Open secondary tools from the More tools menu or You → More tools.

## 2.1.1 presence and floating calls

- With one friend online and another disconnected, verify Friends and profile/member panels show Online and Offline. Open a searched person's profile, verify presence updates, close it, and reopen it.
- Disconnect the observing client: presence should become unavailable until its new snapshot. Restore networking and verify status, platform badges, and call media recover. Change the selected profile status to Away, Busy, or Invisible and check from another account.
- Exercise a server realtime registry restart. Verify unchanged presence watches and room subscriptions are restored and chat catches up.
- Drag the call panel to every window edge, grow/shrink it from its lower-right corner, minimize/expand, resize the main window, and rotate an iPad/iPhone. Confirm controls remain reachable, video follows the panel width, and chat outside the panel remains interactive.
- Use Small panel, Large panel, and Reset position and size. Verify keyboard/VoiceOver menu access and the resize handle's adjustable action.
- Receive a second invitation while the first is unanswered; verify the original remains and the second is declined. Disconnect during microphone permission/startup, then reconnect or hang up; capture must not return from stale work.

## 2.1.2 pointer crash and cross-client conversation calls

- Run `./scripts/verify-calling.sh`. It now compiles an optimized full-app smoke executable, mounts the actual call panel in an invisible window, exercises AppKit hit testing, and drives repeated move/resize events plus cancellation. It also verifies website-call presence and transfer commands without server accounts.
- In the packaged Release app, drag the top grip slowly, quickly, and past every window edge. Resize repeatedly, press Escape during a drag, resize the app window, and minimize/expand the call. Confirm the grip follows the pointer smoothly and audio continues.
- Join a direct/group conversation call in the website, then open the native app. Verify the other-client panel and conversation indicator appear without activating the native microphone or camera.
- Choose Move call here; verify the website relinquishes audio, no participant is rung again, mute/deafen survive, and native media connects. Move it back to the website and verify native capture stops and the other-client panel returns.
- Deny microphone permission during transfer or fail relay loading before joining. Confirm the website call survives and the native app presents the error. End the website call and confirm the panel disappears.
- On iPhone/iPad, move and resize using the native pan handles; rotate during an interaction and verify controls remain reachable.
