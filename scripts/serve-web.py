#!/usr/bin/env python3
"""Serves the web version (Web/dist, from scripts/build-web.sh) on this Mac,
with the same headers gregular.tv sends (Web/public/_headers), so the
Content Security Policy is tried locally too.

    scripts/build-web.sh debug
    python3 scripts/serve-web.py            # http://localhost:8080

Pair it with scripts/demo-server.py and open
http://localhost:8080/?demoServer=http://127.0.0.1:8765 for demo mode (Debug builds).
"""

import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8080"))
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Web", "dist")


def read_headers():
    """The headers for "/*" in _headers (the only block it has)."""
    headers, current = [], None
    with open(os.path.join(ROOT, "_headers")) as file:
        for line in file:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not line[0].isspace():
                current = line.strip()
            elif current == "/*":
                name, value = line.strip().split(":", 1)
                headers.append((name.strip(), value.strip()))
    return headers


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm", ".js": "text/javascript", ".mjs": "text/javascript",
                      ".svg": "image/svg+xml", ".m4a": "audio/mp4"}

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        for name, value in HEADERS:
            self.send_header(name, value)
        super().end_headers()

    def log_message(self, format, *args):
        pass  # quiet

    def do_GET(self):
        if self.path.split("?")[0] in ("/_headers",):
            self.send_error(404)
            return
        super().do_GET()


if __name__ == "__main__":
    if not os.path.exists(os.path.join(ROOT, "index.html")):
        sys.exit("Missing Web/dist. Run: scripts/build-web.sh debug")
    HEADERS = read_headers()
    print(f"Gregular TV on http://localhost:{PORT} (Web/dist). Ctrl-C to stop.")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
