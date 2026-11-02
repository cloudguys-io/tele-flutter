"""Same-origin stand-in backend for the E2E test. TEST ONLY: it signs tokens for any user it is asked
for, so never run it anywhere but your machine.

Serves the built Flutter web example, a token endpoint, a few helpers for the test, and a proxy to
the Tele API (which sends no CORS headers, so a browser can't call it from another origin).

    TELE_API_URL, TELE_API_KEY, TELE_API_SECRET   from the environment (never printed)
    python3 server.py <web build dir> <port>
"""
import base64, hashlib, hmac, json, os, sys, time, urllib.parse, urllib.request, urllib.error
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

API = os.environ["TELE_API_URL"].rstrip("/")
KEY, SECRET = os.environ["TELE_API_KEY"], os.environ["TELE_API_SECRET"]
ROOT, PORT = sys.argv[1], int(sys.argv[2])


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def user_token(sub, name):
    now = int(time.time())
    h = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    p = b64(json.dumps({"iss": KEY, "sub": sub, "iat": now, "nbf": now, "exp": now + 900,
                        "name": name, "tele": {"scope": "user"}}).encode())
    s = b64(hmac.new(SECRET.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"


def tele(method, path, sub, body=None):
    req = urllib.request.Request(API + path, method=method, data=None if body is None else json.dumps(body).encode())
    req.add_header("Authorization", "Bearer " + user_token(sub, sub))
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def log_message(self, *a):
        pass

    def send(self, status, body, ctype="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def proxy(self):
        n = int(self.headers.get("Content-Length") or 0)
        req = urllib.request.Request(API + self.path, data=self.rfile.read(n) if n else None, method=self.command)
        for k in ("Authorization", "Content-Type", "X-Client-Platform", "Accept"):
            if self.headers.get(k):
                req.add_header(k, self.headers[k])
        try:
            with urllib.request.urlopen(req) as r:
                self.send(r.status, r.read(), r.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as e:
            self.send(e.code, e.read())

    def do_POST(self):
        url = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        if url.path == "/api/tele/token":
            return self.send(200, json.dumps({"token": user_token(q["user"], q.get("name", q["user"])),
                                              "expires_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 900))}).encode())
        if url.path == "/e2e/call":
            return self.send(*tele("POST", "/v1/calls", q["host"], {"title": q.get("title", "tele-flutter e2e"),
                                                                   "access_policy": "any_client_user"}))
        if url.path == "/e2e/end":
            return self.send(*tele("POST", f"/v1/calls/{q['call']}/end", q["host"]))
        if url.path.startswith("/v1/"):
            return self.proxy()
        self.send(404, b"{}")

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        q = dict(urllib.parse.parse_qsl(url.query))
        if url.path == "/e2e/messages":
            return self.send(*tele("GET", f"/v1/calls/{q['call']}/messages", q["user"]))
        if url.path == "/e2e/sessions":
            return self.send(*tele("GET", f"/v1/calls/{q['call']}/sessions", q["host"]))
        if url.path.startswith("/v1/"):
            return self.proxy()
        return super().do_GET()

    do_PUT = do_PATCH = do_DELETE = proxy


if __name__ == "__main__":
    print(f"listening on http://127.0.0.1:{PORT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
