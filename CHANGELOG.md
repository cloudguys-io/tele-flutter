# Changelog

## 0.1.0

First release.

- `TeleClient`: the Tele REST API as the signed-in user. Calls, members, sessions, invites, invite
  preview, joins (with `X-Client-Platform`), chat history and saving, recordings, `me`, diagnostics.
  Tokens come from your token provider, are refreshed before expiry and once on a `401`. Joins can
  go through your backend with `TeleJoinProxy`; `TeleJoinProxy.backend` follows the shared `/api/tele`
  route convention and can also read chat history from `GET /api/tele/calls/{id}/messages` (for
  Flutter web, where Tele sends no CORS headers). Joins send `X-Client-Platform: flutter-<os>`. Errors are `TeleException` with `status`, `code`,
  `message` and `opensAt`.
- `TeleCallController`: lobby preview, connect with the join response's `ws_url`, `token` and
  `ice_servers`, microphone, camera, camera flip, speakerphone, screen share, devices, active
  speaker, pinning and the stage rules of the web call UI, reconnect and rejoin, `lk.chat` chat with
  history and deduplication by `stream_id`, recording, end for all, end reasons and events.
- `TeleCallScreen`: lobby, stage with grid and speaker layouts, control bar, chat panel with an
  unread badge, recording banner, reconnect and device notices, ended and error screens. English
  and Bangla labels with overrides, `TeleCallTheme` for light and dark.
- `CallEngine` interface (experimental) with `LiveKitCallEngine` on `livekit_client` ^2.13.1.
- Requires Dart 3.10 and Flutter 3.38 or later.

Tested:

- `flutter analyze` (package and example): no issues. `flutter test`: unit, controller and widget
  tests pass; the live API tests (`test/integration`) pass against a local Tele API.
- `tool/e2e` (2026-11-03, Flutter 3.47.9 web, Chrome with fake camera and microphone, local Tele API
  and LiveKit): 20/20 checks. Covered: both lobby previews, both sides playing both video tiles, host
  controls for the host only, `lk.chat` both ways with Bangla and emoji, both messages saved once
  each, pin and unpin, `flutter-web` in the call record, and leaving.
- Not exercised: native iOS and Android builds (no device or simulator), publishing a screen share.
