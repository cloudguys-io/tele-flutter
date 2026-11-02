// Two-browser end-to-end test of the Flutter web example against a live Tele API and LiveKit.
// See README.md in this folder. Exits 0 when every check passes, 1 on a failed check, 2 when the
// environment isn't set up.
import { spawn, execFileSync } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { chromium } from 'playwright-core';

const here = path.dirname(fileURLToPath(import.meta.url));
const example = path.resolve(here, '../../example');
const port = Number(process.env.E2E_PORT ?? 8791);
const origin = `http://127.0.0.1:${port}`;
const flutter = process.env.FLUTTER ?? 'flutter';
// The browser talks to Tele directly (Tele allows any origin); the local server only serves the
// build, the token endpoint and test helpers.
const teleApi = (process.env.TELE_API_URL ?? '').replace(/\/+$/, '');
const teleCalls = []; // Tele API requests the browsers made, with the CORS header Tele answered
const suffix = Math.random().toString(36).slice(2, 8);
const host = { id: `tele-flutter-e2e-host-${suffix}`, name: 'E2E Host' };
const guest = { id: `tele-flutter-e2e-guest-${suffix}`, name: 'E2E Guest' };

for (const v of ['TELE_API_URL', 'TELE_API_KEY', 'TELE_API_SECRET']) {
  if (!process.env[v]) {
    console.error(`${v} is not set; see tool/e2e/README.md`);
    process.exit(2);
  }
}

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

async function waitFor(fn, { timeout = 20000, every = 250 } = {}) {
  const end = Date.now() + timeout;
  let last;
  while (Date.now() < end) {
    try {
      last = await fn();
      if (last) return last;
    } catch (e) {
      last = e;
    }
    await new Promise((r) => setTimeout(r, every));
  }
  return false;
}

// Flutter web exposes semantics nodes (with ARIA roles and labels) once accessibility is enabled.
const control = (page, name) =>
  page.getByRole('button', { name, exact: true }).or(page.getByRole('switch', { name, exact: true }));
const text = (page) => page.evaluate(() => document.body.innerText);
const playingVideos = (page) =>
  page.locator('video').evaluateAll((vs) => vs.filter((v) => v.videoWidth > 0 && v.readyState >= 2).length);

async function typeInto(page, label, value) {
  const box = page.getByRole('textbox', { name: label });
  await box.click();
  await page.waitForTimeout(300); // Flutter attaches its editing element after the focus
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.press('Backspace');
  await page.keyboard.type(value);
  await page.waitForTimeout(200);
  const got = await page.evaluate(() => document.activeElement && 'value' in document.activeElement ? document.activeElement.value : null);
  if (got !== value) throw new Error(`typing into "${label}" gave ${JSON.stringify(got)}`);
}

async function openApp(browser, who, code) {
  const context = await browser.newContext({ permissions: ['camera', 'microphone'], viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  page.on('pageerror', (e) => console.log(`[${who.name}] page error: ${e.message}`));
  page.on('response', (r) => {
    if (r.url().startsWith(`${teleApi}/v1/`)) {
      teleCalls.push({ who: who.name, method: r.request().method(), path: new URL(r.url()).pathname, status: r.status(), cors: r.headers()['access-control-allow-origin'] });
    }
  });
  await page.goto(origin);
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 30000 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await typeInto(page, 'Token URL (your backend)', `${origin}/api/tele/token?user=${who.id}&name=${encodeURIComponent(who.name)}`);
  await typeInto(page, 'Tele API URL', teleApi);
  await typeInto(page, 'Invite code', code);
  await control(page, 'Open call').click();
  try {
    await control(page, 'Join call').waitFor({ timeout: 20000 });
  } catch (e) {
    throw new Error(`${who.name} never reached the lobby; page shows: ${JSON.stringify(await text(page))}`);
  }
  return { context, page };
}

const json = async (res) => {
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
};

let server;
let browser;
let callId;
try {
  if (!process.env.E2E_SKIP_BUILD) {
    console.log('building the example for web...');
    execFileSync(flutter, ['build', 'web', `--dart-define=TELE_API_URL=${teleApi}`, `--dart-define=TELE_TOKEN_URL=${origin}/api/tele/token`], {
      cwd: example,
      stdio: 'inherit',
    });
  }
  server = spawn('python3', [path.join(here, 'server.py'), path.join(example, 'build/web'), String(port)], {
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  await once(server.stdout, 'data');

  const call = await json(await fetch(`${origin}/e2e/call?host=${host.id}&title=${encodeURIComponent(`tele-flutter e2e ${suffix}`)}`, { method: 'POST' }));
  callId = call.id;
  const code = call.invite.code;
  console.log(`call ${callId}`);

  browser = await chromium.launch({
    channel: process.env.E2E_CHANNEL ?? 'chrome',
    headless: !process.env.E2E_HEADED,
    args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'],
  });

  // Host: lobby preview, then join (the preview track is published).
  const h = await openApp(browser, host, code);
  check('host lobby shows the camera preview', !!(await waitFor(async () => (await playingVideos(h.page)) >= 1)));
  await control(h.page, 'Join call').click();
  check('host is live', !!(await waitFor(async () => (await text(h.page)).includes('1 in call'))));

  // Guest joins through the same invite.
  const g = await openApp(browser, guest, code);
  check('guest lobby shows the camera preview', !!(await waitFor(async () => (await playingVideos(g.page)) >= 1)));
  await control(g.page, 'Join call').click();

  for (const [who, page] of [['host', h.page], ['guest', g.page]]) {
    check(`${who} sees 2 in call`, !!(await waitFor(async () => (await text(page)).includes('2 in call'))));
    const videos = await waitFor(async () => {
      const n = await playingVideos(page);
      return n >= 2 ? n : false;
    }, { timeout: 30000 });
    check(`${who} sees both video tiles playing`, !!videos, `videos playing: ${videos || await playingVideos(page)}`);
  }
  check('host sees the guest tile', await control(h.page, `Pin ${guest.name}`).isVisible());
  check('guest sees the host tile', await control(g.page, `Pin ${host.name}`).isVisible());
  check('the host gets host controls', await control(h.page, 'End for all').isVisible());
  check('the guest gets no host controls', !(await control(g.page, 'End for all').isVisible()));

  // Chat both ways on lk.chat.
  const hostMsg = `hello from the host ${suffix}`;
  const guestMsg = `হ্যালো 👋 from the guest ${suffix}`;
  await control(h.page, 'Chat').click();
  await typeInto(h.page, 'Message', hostMsg);
  await control(h.page, 'Send').click();
  check('guest gets an unread badge', !!(await waitFor(async () => control(g.page, 'Chat, 1 unread').isVisible())));
  await control(g.page, 'Chat, 1 unread').click();
  const seen = await waitFor(async () => (await text(g.page)).includes(hostMsg));
  check('guest sees the host message', !!seen, seen ? '' : JSON.stringify(await text(g.page)));
  await typeInto(g.page, 'Message', guestMsg);
  await control(g.page, 'Send').click();
  check('host sees the guest message (Bangla and emoji)', !!(await waitFor(async () => (await text(h.page)).includes(guestMsg))));

  const saved = await waitFor(async () => {
    const { messages } = await json(await fetch(`${origin}/e2e/messages?call=${callId}&user=${host.id}`));
    const bodies = messages.map((m) => m.body);
    return bodies.includes(hostMsg) && bodies.includes(guestMsg) ? messages : false;
  });
  check('both messages are saved (GET /messages)', !!saved, saved ? `${saved.length} saved, each stream_id once: ${new Set(saved.map((m) => m.stream_id)).size === saved.length}` : '');

  // Pinning (a single tap resolves after the double-tap timeout).
  await control(h.page, `Pin ${guest.name}`).click();
  check('host pins the guest', !!(await waitFor(async () => control(h.page, `Unpin ${guest.name}`).isVisible())));
  await control(h.page, `Unpin ${guest.name}`).click();
  check('host unpins the guest', !!(await waitFor(async () => control(h.page, `Pin ${guest.name}`).isVisible())));

  // Everything above went from the browser straight to Tele, across origins. The save answers 201 when
  // new, or 200 when Tele's chat recorder already stored the message from the room (deduplicated).
  const posts = teleCalls.filter((c) => c.method === 'POST' && c.path.endsWith('/messages'));
  check('chat messages were saved by the browsers directly on Tele (CORS)', posts.length === 2 && posts.every((c) => (c.status === 201 || c.status === 200) && c.cors === '*'), JSON.stringify(posts));
  const kinds = new Set(teleCalls.map((c) => `${c.method} ${c.path.replace(/\/v1\/(calls|invites)\/[^/]+/, '/v1/$1/{id}')}`));
  check('previews, joins and history also went to Tele directly', ['GET /v1/invites/{id}', 'POST /v1/invites/{id}/join', 'GET /v1/calls/{id}/messages'].every((k) => kinds.has(k)), [...kinds].join(', '));
  check('the page origin is not the Tele origin', new URL(origin).origin !== new URL(teleApi).origin);

  const sessions = await json(await fetch(`${origin}/e2e/sessions?call=${callId}&host=${host.id}`));
  const platforms = sessions.sessions.flatMap((s) => s.participants.map((p) => p.platform));
  check('the call record shows flutter-web for both', platforms.filter((p) => p === 'flutter-web').length >= 2, platforms.join(','));

  // The guest leaves; the host sees it.
  await control(g.page, 'Leave').click();
  check('host sees the guest leave', !!(await waitFor(async () => (await text(h.page)).includes('1 in call'))));
  check('the guest is back on the start page', !!(await waitFor(async () => (await text(g.page)).includes('Open call'))));
} catch (e) {
  check('run', false, e.stack ?? String(e));
} finally {
  if (callId) await fetch(`${origin}/e2e/end?call=${callId}&host=${host.id}`, { method: 'POST' }).catch(() => {});
  await browser?.close().catch(() => {});
  server?.kill();
}

const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
process.exit(failed.length ? 1 : 0);
