# tele_flutter

Tele video calling for Flutter apps:

- **`TeleClient`**: the Tele REST API acting as the signed-in user (user token): calls, members,
  invites, joining, chat history, recordings, sessions.
- **`TeleCallScreen`**: a native prebuilt call screen on [`livekit_client`](https://pub.dev/packages/livekit_client)
  with a lobby, video tiles, screen share, pinning, chat, reconnect handling, a recording banner,
  English and Bangla labels, and light and dark themes.
- **`TeleCallController`**: the call logic behind the screen, usable on its own for a custom UI.

It follows the same rules as the web call UI (`@tele/call-ui`), so a Flutter user and a browser
user in the same call see the same stage and chat.

## Install

The package is not on pub.dev. Add it from the release tag:

```yaml
dependencies:
  tele_flutter:
    git:
      url: https://github.com/cloudguys-io/tele-flutter
      ref: v0.1.0
```

It needs Dart 3.10 and Flutter 3.38 or later, and depends on `livekit_client` ^2.13.1 (2.12.0 or
later is required for Bangla and emoji chat) and `http`.

### Platform setup

iOS, `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key><string>Video calls</string>
<key>NSMicrophoneUsageDescription</key><string>Audio calls</string>
<key>UIBackgroundModes</key><array><string>audio</string></array>
```

Android, `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
```

To keep a call alive in the background on Android 14 and later, your app needs a foreground service
of type `microphone|camera`. The [example](example/) has both files set up.

**Web:** Tele sends no CORS headers, so a browser can't call the Tele API from your app's origin.
On Flutter web, a `TeleJoinProxy` alone only fixes joins: the call screen's chat history
(`GET /v1/calls/{id}/messages`) and saving sent messages (`POST /v1/calls/{id}/messages`) would still
go to Tele and be blocked. Pick one:

- set `baseUrl` to a same-origin path that your server forwards to Tele's `/v1` (everything works as
  on native), or
- route through your backend with `TeleJoinProxy.backend(...)`, which also reads chat history from
  `GET /api/tele/calls/{id}/messages`, and pass `persistChat: false` (Tele's recorder still saves
  every message sent over `lk.chat`; the extra `POST` is only a stronger guarantee).

See [Joining through your backend](#joining-through-your-backend).

## Security

Your **API secret never leaves your backend**. The app only ever holds short-lived user tokens that
your backend signs (HS256, at most 1 hour) for the signed-in user. Give `TeleClient` a function that
asks your backend for one:

```dart
final tele = TeleClient(
  tokenProvider: () async {
    final res = await http.post(Uri.parse('https://yourapp.example/api/tele/token'),
        headers: {'Authorization': 'Bearer ${await mySession()}'});
    return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
  },
);
```

`POST /api/tele/token` returning `{"token": "...", "expires_at": "..."}` is the shared route
convention of the Tele backend SDKs (see the guide's Authentication page). Never put the API
secret, or a service token, in an app.

Treat invite codes like bearer links: anyone with the code can preview the call and (per its access
policy) join. Don't log them.

## Quickstart

```dart
import 'package:tele_flutter/tele_flutter.dart';

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.tele, required this.inviteCode});
  final TeleClient tele;
  final String inviteCode;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  late final call = TeleCallController.invite(widget.tele, widget.inviteCode);

  @override
  void dispose() {
    call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TeleCallScreen(
          controller: call,
          onLeave: (reason) => Navigator.of(context).pop(),
        ),
      );
}
```

The user lands in the lobby (camera preview, microphone and camera toggles, device pickers), taps
**Join call**, and is in. Errors from Tele get friendly text: `too_early` shows "This call isn't
open yet." with the opening time.

## `TeleClient`

```dart
final tele = TeleClient(
  tokenProvider: getTeleToken,                         // required
  baseUrl: Uri.parse('https://tele-api.cloudguys.io'), // the default
  platform: 'android',                                 // X-Client-Platform on joins; detected by default
  joinProxy: null,                                     // see below
);
```

The client keeps the last token, asks for a new one 30 seconds before it expires, and on a `401`
gets a fresh one and retries the request once. `invalidateToken()` forgets it. A token provider that
throws becomes a `TeleException` with code `token_provider`; a request slower than `timeout`
(default 20 s) one with code `timeout`. The platform is sent as `flutter-web`, `flutter-ios`,
`flutter-android`, `flutter-macos`, `flutter-windows` or `flutter-linux`, so the call record shows
the SDK; pass `platform:` to override it.

Recording downloads (`GET /v1/recordings/{id}/download`) are not wrapped: stream them through your
backend.

| Method | Endpoint |
|---|---|
| `createCall(title:, accessPolicy:, scheduledStart:, scheduledEnd:, joinOpensBeforeMinutes:, joinClosesAfterMinutes:, maxParticipants:, maxDurationMinutes:, record:, members:, invite:)` | `POST /v1/calls` (the token's user is the host) |
| `listCalls(statuses:, from:, to:, limit:)` | `GET /v1/calls` |
| `getCall(id)` | `GET /v1/calls/{id}` |
| `updateCall(id, title:, accessPolicy:, scheduledStart:, scheduledEnd:, maxParticipants:, record:)` | `PATCH /v1/calls/{id}` |
| `cancelCall(id)` | `DELETE /v1/calls/{id}` |
| `endCall(id)` | `POST /v1/calls/{id}/end` |
| `putMember(id, userId, name:, team:)` | `PUT /v1/calls/{id}/members/{user_id}` |
| `removeMember(id, userId)` | `DELETE /v1/calls/{id}/members/{user_id}` |
| `listSessions(id)` | `GET /v1/calls/{id}/sessions` |
| `createInvite(id, options:)` | `POST /v1/calls/{id}/invites` |
| `listInvites(id)` | `GET /v1/calls/{id}/invites` |
| `revokeInvite(inviteId)` | `DELETE /v1/invites/{invite_id}` |
| `previewInvite(code)` | `GET /v1/invites/{code}` |
| `joinInvite(code)` | `POST /v1/invites/{code}/join` |
| `joinCall(id)` | `POST /v1/calls/{id}/join` |
| `listMessages(id, after:, limit:)`, `listAllMessages(id)` | `GET /v1/calls/{id}/messages` |
| `postMessage(id, streamId:, body:, sentAt:)` | `POST /v1/calls/{id}/messages` |
| `startRecording(id)`, `stopRecording(id)` | `POST /v1/calls/{id}/recording/start`, `/stop` |
| `listRecordings(id)` | `GET /v1/calls/{id}/recordings` |
| `getRecording(recordingId)`, `restoreRecording(recordingId)` | `GET /v1/recordings/{id}`, `POST /v1/recordings/{id}/restore` |
| `me()` | `GET /v1/me` |
| `reportDiagnostic(id, grantId:, participantSid:, kind:, payload:)` | `POST /v1/calls/{id}/diagnostics` |

Responses are typed (`TeleCall`, `TeleInvite`, `TeleInvitePreview`, `TeleJoinResponse`,
`TeleChatMessage`, `TeleRecording`, `TeleSession`, `TeleMe`, ...). Times are `DateTime`; optional
fields are nullable. Enum-like strings parse to enums with an `unknown` fallback.

### Errors

Every failure is a `TeleException` with the HTTP `status`, the Tele `code` and a `message`
(`opensAt` for `too_early`). Branch on `code`:

```dart
try {
  await tele.joinInvite(code);
} on TeleException catch (e) {
  switch (e.code) {
    case 'too_early': showCountdown(e.opensAt!);
    case 'call_full': showFull();
    case 'network_error': showOffline(); // status 0: no response
    default: showError(e.message);
  }
}
```

A response that isn't a Tele error body becomes `http_<status>`; no response is `network_error` or
`timeout`; a failing token provider is `token_provider`.

### Joining through your backend

Tele backend SDKs expose a shared set of routes under `/api/tele`:

| Method | Path | Does |
|---|---|---|
| `POST` | `/api/tele/token` | a user token for the signed-in user |
| `POST` | `/api/tele/invites/{code}/join` | invite join, as the user |
| `POST` | `/api/tele/calls/{id}/join` | call join with a service token carrying the user's IP and user agent |
| `GET` | `/api/tele/calls/{id}/messages` | chat history, as the user (`after` and `limit` passed through) |

`TeleJoinProxy.backend` points the client at them. Joins POST there with `X-Client-Platform` and
your headers; history is read there too. Your backend returns Tele's bodies, and Tele's error shape,
unchanged:

```dart
final tele = TeleClient(
  tokenProvider: getTeleToken, // POST https://yourapp.example/api/tele/token
  joinProxy: TeleJoinProxy.backend(
    Uri.parse('https://yourapp.example/api/tele'),
    headers: () async => {'Authorization': 'Bearer ${await mySession()}'},
  ),
);
```

That is the same as:

```dart
TeleJoinProxy(
  url: (t) => t.inviteCode != null
      ? Uri.parse('https://yourapp.example/api/tele/invites/${Uri.encodeComponent(t.inviteCode!)}/join')
      : Uri.parse('https://yourapp.example/api/tele/calls/${Uri.encodeComponent(t.callId!)}/join'),
  messages: (callId) => Uri.parse('https://yourapp.example/api/tele/calls/${Uri.encodeComponent(callId)}/messages'),
  headers: () async => {'Authorization': 'Bearer ${await mySession()}'},
)
```

**Which IP the call record shows.** For user-token calls, Tele records the IP the request came from,
and it trusts no proxy in front of hosted Tele. So:

- **Call-id joins through the backend** (`/api/tele/calls/{id}/join`) use a service token that
  carries the end user's IP, so the record shows the user's IP.
- **Invite joins through a backend** record the **backend's** IP. Browsers can't avoid this, because
  Tele sends no CORS headers. **Native apps** (iOS, Android, desktop) can: leave out `joinProxy` and
  call `POST /v1/invites/{code}/join` directly with a user token, and Tele sees the device's IP.
- After the first invite join, rejoins go through the call-id route (`TeleCallController.invite`
  already does this), so they don't use up the invite and, through the backend, carry the user's IP.

### `X-Client-Platform`

Joins send `X-Client-Platform` so the call record shows the device. The default is `flutter-<os>`:
`flutter-android`, `flutter-ios`, `flutter-web`, `flutter-macos`, `flutter-windows`,
`flutter-linux` or `flutter-fuchsia` (from `defaultTelePlatform()`). Pass `platform:` to send your own
value (at most 32 characters). A join proxy forwards the header to Tele.

## `TeleCallScreen`

```dart
TeleCallScreen(
  controller: call,
  onLeave: (TeleEndReason reason) {},  // left, roomDeleted, duplicateIdentity, removed, joinFailure, disconnected, error
  onEvent: (TeleCallEvent e) {},       // TeleCallJoined, TeleParticipantJoined/Left, TeleChatReceived, TeleCallLeft, TeleCallFailed
  language: 'bn',                      // en or bn; a tag like bn-BD uses bn; defaults to the app locale
  strings: {TeleStringKey.exit: 'Back to my calls'},
  theme: TeleCallTheme.dark.copyWith(accent: Color(0xFF0A7CFF), radius: 8),
  title: preview.call.title,           // lobby heading
  displayName: me.user?.name,          // "Joining as {name}" in the lobby
  lobby: true,                         // false joins at once with microphone and camera on
  chat: true,
  screenShare: true,                   // the share button on web and desktop
  devicePickers: true,
  recordingIndicator: true,
  extraControls: [/* more buttons for the control bar */],
)
```

What it does:

- **Lobby:** camera preview, microphone and camera toggles, camera flip on phones, microphone,
  camera and speaker pickers where the platform lists more than one, and **Join call**. The name
  others see comes from the user token, so the lobby shows it ("Joining as ...") rather than asking.
- **Stage:** what goes large, in order: a tile you pinned (every tile has a pin button, and a double
  tap pins too; pinning again unpins), then someone else's screen share (your own stays small unless
  you pin it), then the active speaker in speaker layout. The other tiles sit in a strip below, or
  beside it once the screen is 900 px wide. Pins are local and never sent to anyone, and a pin is
  dropped when that person leaves. Others' screen shares get a tile once the track is subscribed.
  Tiles keep their video renderer when they move, so the video doesn't flash. Grid and speaker
  layouts switch from the control bar.
- **Controls:** mute, camera, flip camera (phones), speakerphone (phones), share screen (web and
  desktop), layout, devices, chat with an unread badge, record and stop (hosts), end for all
  (hosts, with a confirmation), leave.
- **Chat** on the `lk.chat` text stream topic, so it talks to web and native Tele clients. Earlier
  messages load from Tele when you join, deduplicated against live messages by `stream_id`. Sent
  messages are also saved with `POST /v1/calls/{id}/messages`. Messages are limited to 2,000
  characters (Unicode code points, as the server counts), like the web call UI. A failed send keeps
  the draft and shows a notice.
- **Audio on the web:** if the browser blocks autoplay, a banner asks for a tap to turn on call audio.
- **Notices:** a recording banner while the media server reports recording, "Reconnecting..." while
  the SDK reconnects or the screen rejoins, and device problems.
- **Ended and error screens** with the reason, Rejoin or Try again, and Close.
- **Accessibility:** every control has a semantics label and is at least 48 px; tiles announce the
  name, "(you)", "screen" and "muted"; banners are live regions.

Screen sharing from phones needs an iOS broadcast extension or an Android foreground service in your
app, so the share button shows on web and desktop only. Everyone sees screen shares from others.

### Theming

Add `TeleCallTheme` to your theme's extensions (or pass `theme:`):

```dart
MaterialApp(
  theme: ThemeData(extensions: [TeleCallTheme.light.copyWith(accent: Color(0xFF0A7CFF))]),
  darkTheme: ThemeData(brightness: Brightness.dark, extensions: [TeleCallTheme.dark]),
)
```

Fields: `accent`, `onAccent`, `radius`, `background`, `surface`, `tile`, `text`, `muted`, `line`,
`danger`, `onDanger`. Without one, the screen picks `light` or `dark` from the ambient brightness.

### Strings

All labels are in `TeleStringKey`, with English and Bangla dictionaries. Override any of them with
`strings:`. `TeleStrings.of('bn')` and `teleErrorText(strings, error)` are available for your own
screens, for example to show an invite preview's reason before joining.

## `TeleCallController`

```dart
final call = TeleCallController(
  join: () => tele.joinInvite(code),  // or tele.joinCall(id), or your backend
  client: tele,                        // optional: chat history and saving, recording, end for all
  layout: TeleLayout.speaker,
  persistChat: true,
  loadChatHistory: true,
  maxRejoinAttempts: 2,
  endForAll: null,                     // custom "end for all" instead of tele.endCall
  setRecording: null,                  // custom recording start/stop instead of the client
);
```

`TeleCallController.invite(tele, code)` and `TeleCallController.call(tele, callId)` are shortcuts
and take the same options (`microphone`, `camera`, `persistChat`, `loadChatHistory`,
`maxRejoinAttempts`, `endForAll`, `setRecording`, `engine`, `ownsEngine`, `layout`).

It is a `ChangeNotifier` with `phase` (`lobby`, `joining`, `live`, `ended`, `error`, `left`),
`joinResponse`, `isHost`, `error`/`errorCode`, `endReason`, `notice`, `reconnecting`,
`participants`, `stage`, `pinned`, `layout`, `messages`, `unreadCount`, `chatOpen`, `isRecording`,
`canRecord`, `canEndForAll`, and an `events` stream. Methods: `startPreview()`, `join()`, `retry()`,
`leave()`, `endForAll()`, `setMicrophone()`, `setCamera()`, `toggleMicrophone()`, `toggleCamera()`,
`flipCamera()`, `setSpeakerphone()`, `setScreenShare()`, `devices()`, `selectDevice()`,
`setRecording()`, `sendChat()`, `togglePinned()`, `dismissNotice()`.

How it connects (as in the guide's Flutter page): `ws_url` and `token` go to `Room.connect`;
`ice_servers` become `ConnectOptions(rtcConfiguration: RTCConfiguration(iceServers: ...))`, passed as
is; when `ice_servers` is null or empty, no servers are passed and the SDK's defaults are used. `rtcConfigurationFor(join)` is the
mapping, if you connect a `Room` yourself.

**Reconnects (automatic rejoin):** the SDK reconnects after network blips. When it gives up (for
example after a long outage, once the TURN credentials have expired), the controller drops the dead
room and the cached token, joins again and reconnects, up to `maxRejoinAttempts` times (0 turns
this off). The rejoin uses `rejoin:` (given the call id), which defaults to `client.joinCall`, so
a call opened from an invite doesn't use up another of the invite's uses. Without a client it calls
`join` again. If the call ended, or the user may no longer join (`not_invited`, `invite_*`), it stops
and shows the ended screen. A second device joining as the same user disconnects this one with
`duplicateIdentity` ("You joined this call from another device").

The media side is behind the `CallEngine` interface (experimental: it may gain members in minor
releases). `LiveKitCallEngine` is the real one; pass your own `engine:` to fake it in tests. The
controller disposes an engine it created; a caller-supplied engine is only disconnected unless you
pass `ownsEngine: true`. `controller.media` is a `Listenable` for media-only changes (tracks,
speakers, pins), which the stage listens to so speaker changes don't rebuild the whole screen.

## Example

[`example/`](example/) gets a token from a configurable backend URL, previews an invite and opens the
call screen:

```bash
cd example
flutter run --dart-define=TELE_TOKEN_URL=https://yourapp.example/api/tele/token \
            --dart-define=TELE_INVITE=<invite code>
```

## Development

```bash
flutter analyze
flutter test                    # unit, controller and widget tests; live API tests skip

# Live API tests (create call, invite, preview, join, chat, end) against a running Tele API.
# The test signs user tokens itself, so it needs the API secret: keep it in your shell, never in the repo.
export TELE_API_URL=http://127.0.0.1:8080 TELE_API_KEY=... TELE_API_SECRET=...
flutter test test/integration
```

### End-to-end test

`tool/e2e/` drives the web example in two Chrome contexts (host and guest) with fake camera and
microphone against a live Tele API and LiveKit: lobby preview, both video tiles, chat both ways and
saved, pinning, leaving. See [tool/e2e/README.md](tool/e2e/README.md). Native iOS and Android builds
are not exercised there.

## Public API

Everything is exported from `package:tele_flutter/tele_flutter.dart`. Besides the client, controller
and screen, the supported building blocks for a custom UI are `TeleStageView`, `TeleChatPanel` and
`TeleDevicePickers`; other widgets are internal.

## License

MIT. See [LICENSE](LICENSE).
