# tele_flutter example

Opens a Tele call from an invite code.

1. Your backend needs a token endpoint: `POST <token URL>` returns `{"token": "<Tele user token>"}`
   for the signed-in user (see the guide's Authentication page). The API secret stays there.
2. Run the app with your URLs baked in, or type them on the first screen:

```bash
flutter run --dart-define=TELE_TOKEN_URL=https://yourapp.example/api/tele-token \
            --dart-define=TELE_API_URL=https://tele-api.cloudguys.io \
            --dart-define=TELE_INVITE=<invite code>
```

The app previews the invite (so it can show "This call isn't open yet" before joining) and opens
`TeleCallScreen`.

Camera, microphone and background audio permissions are already set in
`ios/Runner/Info.plist` and `android/app/src/main/AndroidManifest.xml`. On Android 14 and later,
add a foreground service of type `microphone|camera` to keep calls alive in the background.

For Flutter web, the Tele API sends no CORS headers: serve the app and a proxy to the Tele API from
the same origin and set `TELE_API_URL` to that proxy path.
