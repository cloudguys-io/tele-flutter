# End-to-end test (Flutter web, two browsers)

Builds `example/` for web and drives it in two Chrome contexts, a host and a guest, against a live
Tele API and its LiveKit server, with Chrome's fake camera and microphone
(`--use-fake-ui-for-media-stream --use-fake-device-for-media-stream`).

It checks:

- each lobby shows the camera preview, and joining publishes it (the other side plays it);
- each side sees "2 in call" and both video tiles playing, and the other's tile;
- only the host gets host controls;
- `lk.chat` messages go both ways (Bangla and emoji included), the unread badge shows, and both
  messages are saved (`GET /v1/calls/{id}/messages`);
- pinning and unpinning the other's tile;
- the call record shows `flutter-web` for both participants;
- previews, joins, history and saving chat messages went from the browsers straight to the Tele
  API, cross-origin (CORS `*`);
- the guest leaves and the host sees "1 in call".

## Run

Needs Flutter, Python 3, Node 20+, Google Chrome (or set `E2E_CHANNEL=chromium` with Playwright's
Chromium installed), and a Tele API with LiveKit.

```bash
cd tool/e2e
npm install                 # playwright-core only; no browser download
export TELE_API_URL=http://127.0.0.1:8080 TELE_API_KEY=... TELE_API_SECRET=...
node e2e.mjs                # E2E_HEADED=1 to watch, E2E_SKIP_BUILD=1 to reuse example/build/web
```

`server.py` is a **test-only** stand-in for your backend: it serves the web build, signs user
tokens for whichever user the test asks for, and has small helpers for the test. It does not proxy
Tele: the browsers call the Tele API directly from another origin, which the test checks (CORS,
including saving chat messages). It reads the secret from the environment and never prints it.
Never deploy it.

Not covered here: native iOS and Android builds (no device or simulator in this setup), and
publishing a screen share (the fake-device flags don't provide one).
