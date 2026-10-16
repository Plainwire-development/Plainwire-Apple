# Plainwire for Apple 2.3.0

Forums now live in the native app, alongside a visual refresh across the main pages.

## Native forums

- Explore communities in a responsive card grid, filter joined forums, and search and sort discussions.
- Join or create a forum, publish discussions, reply, vote, and share links. Website and native clients use the same Plainwire account and server data, including self-hosted installations.
- Write with Markdown previews and file attachments. Discussion and reply drafts persist separately for each host and account.
- Edit your posts and use the moderation controls granted by the server. Forum owners can pin or close discussions and remove content. Destructive actions ask for confirmation.
- Receive live discussion and reply updates. Forum and discussion links open native pages; older responses cannot restore deleted content or overwrite a newer search.

## A more cohesive interface

- Refreshed community, Friends, and Activity pages have clearer headings, generous spacing, rounded cards, and adaptive light/dark colors.
- Conversation previews, server navigation, sign-in, Settings surfaces, and empty states share consistent styling and rounded controls.
- Five visible iPhone tabs keep Forums easy to reach; Friends and Activity share the People tab with an unread badge.
- Native scrolling and resizable editors keep long content usable. Semantic colors, increased-contrast borders, system text styles, and accessibility labels support Apple platform conventions.
- Shared GIF downloads and cached decoded avatars from 2.2.1 remain in place for fast DM profile images.

## Reliability and performance

- Forum searches and realtime refreshes are debounced, recent discussion details are bounded, and inactive pages stop periodic refreshes.
- Forum state is invalidated during sign-out and host changes. UTF-8 limits match the backend so emoji-heavy posts are not silently truncated.
- Verification covers 63 core tests, Mac and iOS Simulator builds, and optimized native checks for forum sync, permissions, moderation, deletion races, host isolation, media, calling, and compact layouts.

The Mac download includes a universal Apple Silicon/Intel app, installer, updater, swap helper, and SHA-256 checksums. Requires macOS 15 or later; the source also targets iOS/iPadOS 18 or later.
