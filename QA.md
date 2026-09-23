# Manual checks

Run `./scripts/verify.sh` and build the Mac and iOS Simulator targets before a release. The checks below need a running Plainwire server and two accounts.

## Mac install

- Run `./scripts/install-macos.sh` from a clean checkout. Confirm `~/Applications/Plainwire.app` opens.
- After publishing a release, run the README's curl command on a Mac without the checkout. Confirm it downloads, verifies, and opens the latest app. Run it again to check upgrades.
- Install a downloaded bundle with `--app`, then upgrade it with another bundle. Confirm the app opens and only the installed Plainwire bundle has its quarantine attribute removed.
- Resize the window and use the sidebar and keyboard shortcuts. Check Settings at the minimum window size.

## Account and chat

- Sign in, restart, and confirm the session restores. Sign out and confirm private images are no longer shown.
- Open a direct message and a channel. Send, reply, edit, delete, and react from both accounts.
- Scroll up while a new message arrives. Confirm the view stays put and the new-message button appears.
- Load older messages and confirm the current row keeps its position.
- Check long messages and dates in light and dark mode, at large text sizes, and with VoiceOver.

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
