# Manual checks

Run `./scripts/verify.sh` and build the Mac and iOS Simulator targets before a release. The checks below need a running Plainwire server and two accounts.

## Mac install

- Run `./scripts/install-macos.sh` from a clean checkout. Confirm `~/Applications/Plainwire.app` opens.
- After publishing a release, run the README's curl command on a Mac without the checkout. Confirm it downloads, verifies, and opens the latest app. Run it again to check upgrades.
- Install a downloaded bundle with `--app`, then upgrade it with another bundle. Confirm the app opens and only the installed Plainwire bundle has its quarantine attribute removed.
- Run the README updater against an installed older version. Confirm it verifies the release, quits the running app, swaps it, and reopens the new version. Run it again and confirm it skips the download.
- Try an invalid release tag and a corrupt archive in a test destination. Confirm the existing app is intact and launches afterward.
- Resize the window and use the sidebar and keyboard shortcuts. Check Settings at the minimum window size.

## Account and chat

- Sign in, restart, and confirm the session restores. Sign out and confirm private images are no longer shown.
- Open a direct message and a channel. Send, reply, edit, delete, and react from both accounts.
- Scroll up while a new message arrives. Confirm the view stays put and the new-message button appears.
- Load older messages and confirm the current row keeps its position.
- Check long messages and dates in light and dark mode, at large text sizes, and with VoiceOver.
- Open a member profile from Friends and from a message author. Check the avatar, banner, bio, status, and message action.
- Edit your profile name, bio, status, avatar, banner, and theme. Restart and confirm the theme and account values persist.
- Change the username, email, and password. Review active sessions, sign out other sessions, and verify the current device remains signed in.

## Servers and workspace

- Create a server, edit its name, description, welcome message, icon, banner, and accent. Create a category and text channel; edit a channel name and topic.
- Set your nickname, avatar, and bio for one server. Confirm the global profile stays separate.
- Create and share an invite. Join from another account by pasting the code or link, then revoke it and confirm it can no longer be used.
- Open Workspace after signing in. Confirm it opens without a second login. Change a setting there, return to a native tab, and confirm it refreshes. Sign out in Workspace and confirm the native app signs out.
- Check web voice/video permissions on real Mac and iOS devices if you use live calls.

## Attachments

- Attach several files at once. Try an image, PDF, and MP4/MOV video.
- Send an attachment as a spoiler. Confirm its image or video does not load until revealed and that it can be hidden again.
- Open a room with many repeated avatars and images. Scroll away and back; they should appear from cache without a visible reload.
- Try an unavailable image and a large upload. Confirm the error is readable and the rest of chat still works.

## Notifications and connection

- Enable notifications from Settings. Check previews on and off, sound on and off, and a muted direct message.
- With the app open to another room, receive a message. Confirm one notification appears with the right room name; tapping it opens that room.
- With the active room visible, confirm a new message does not produce an extra banner.
- Disconnect the network, reconnect, and confirm messages and presence catch up without duplicates.
- On iPhone, background and reopen the app. Confirm it reconnects and syncs.
