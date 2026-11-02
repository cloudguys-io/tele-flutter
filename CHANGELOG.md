# Changelog

## 0.1.0

First release.

- `TeleClient`: the Tele REST API as the signed-in user. Calls, members, sessions, invites, invite
  preview, joins (with `X-Client-Platform`), chat history and saving, recordings, `me`, diagnostics.
  Tokens come from your token provider, are refreshed before expiry and once on a `401`. Joins can
  go through your backend with `TeleJoinProxy`. Errors are `TeleException` with `status`, `code`,
  `message` and `opensAt`.
- `TeleCallController`: lobby preview, connect with the join response's `ws_url`, `token` and
  `ice_servers`, microphone, camera, camera flip, speakerphone, screen share, devices, active
  speaker, pinning and the stage rules of the web call UI, reconnect and rejoin, `lk.chat` chat with
  history and deduplication by `stream_id`, recording, end for all, end reasons and events.
- `TeleCallScreen`: lobby, stage with grid and speaker layouts, control bar, chat panel with an
  unread badge, recording banner, reconnect and device notices, ended and error screens. English
  and Bangla labels with overrides, `TeleCallTheme` for light and dark.
- `CallEngine` interface with `LiveKitCallEngine` on `livekit_client` ^2.13.1.
