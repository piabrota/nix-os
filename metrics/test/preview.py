#!/usr/bin/env python3
"""Serve metrics/index.html with one fixture case, to open it in a browser.

  python3 metrics/test/preview.py [healthy|stale|missing|hostile] [port]    (just metrics-preview)
  python3 metrics/test/preview.py --check                                   (just metrics-test)

The "ts" in a fixture is seconds from now; the server adds the time of each request, so a healthy
host stays live and a stale one stays stale. Stop with Ctrl-C. `--check` serves the healthy case
on a free port, fetches the page and the data as the browser does, and prints "N checks, M failed".
Standard library only.
"""

import functools
import http.server
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
PAGE = HERE.parent / "index.html"
CASES = sorted(p.name for p in (HERE / "fixtures").iterdir() if p.is_dir())


def finite(x):
    """Infinity as jq -c writes it (the largest double), so the page gets valid JSON."""
    if isinstance(x, float) and abs(x) == float("inf"):
        return sys.float_info.max if x > 0 else -sys.float_info.max
    if isinstance(x, dict):
        return {k: finite(v) for k, v in x.items()}
    if isinstance(x, list):
        return [finite(v) for v in x]
    return x


def live(raw, now):
    """A fixture with its times moved to now. json takes the hostile case's Infinity, as jq does."""
    data = finite(json.loads(raw))
    data["ts"] += now
    if isinstance(data.get("domains", {}).get("ts"), (int, float)):
        data["domains"]["ts"] += now
    return json.dumps(data, separators=(",", ":"))


class Handler(http.server.BaseHTTPRequestHandler):
    def __init__(self, *args, case, **kw):
        self.case = case
        super().__init__(*args, **kw)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            body, kind = PAGE.read_bytes(), "text/html"
        elif path.startswith("/data/") and "/" not in path[6:] and path.endswith(".json"):
            f = HERE / "fixtures" / self.case / "data" / path[6:]
            if not f.is_file():
                return self.send_error(404)
            body, kind = live(f.read_text(), int(time.time())).encode(), "application/json"
        else:
            return self.send_error(404)
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def serve(case, port):
    return http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(Handler, case=case))


def get(url):
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""


def check():
    server = serve("healthy", 0)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{server.server_address[1]}"
    now = int(time.time())
    host2 = json.loads(get(f"{base}/data/piabrota2.json")[1] or b"{}")
    results = {
        "GET / gives the page": get(f"{base}/")[1] == PAGE.read_bytes(),
        "GET /data/piabrota2.json is fresh JSON": host2.get("ts", 0) >= now - 10 and host2.get("host") == "piabrota2",
        "GET /data/piabrota.json": json.loads(get(f"{base}/data/piabrota.json")[1] or b"{}").get("host") == "piabrota",
        "a missing host is a 404": get(f"{base}/data/nope.json")[0] == 404,
        "a path out of data/ is a 404": get(f"{base}/data/../index.html")[0] == 404,
    }
    server.shutdown()
    failed = [name for name, ok in results.items() if not ok]
    for name in failed:
        print(f"FAIL {name}")
    print(f"{len(results)} checks, {len(failed)} failed")
    return int(bool(failed))


def main(argv):
    if argv[:1] == ["--check"]:
        return check()
    case = argv[0] if argv else "healthy"
    port = int(argv[1]) if len(argv) > 1 else 8080
    if case not in CASES:
        print(f"no such case: {case} ({', '.join(CASES)})", file=sys.stderr)
        return 2
    server = serve(case, port)
    print(f"case {case}: http://127.0.0.1:{port}/ (Ctrl-C stops)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
