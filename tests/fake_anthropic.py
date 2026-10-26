# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""A stand-in for the Anthropic Messages API, for the smoke test of
`provost --llm` (no network, no key, no cost).

    python3 tests/fake_anthropic.py PORT_FILE LOG_FILE REPLY_FILE

Listens on 127.0.0.1 (an ephemeral port, written to PORT_FILE), answers
every POST /v1/messages with REPLY_FILE (a Messages API response body, JSON)
and appends each request's headers and body to LOG_FILE as one JSON line.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, LOG_FILE, REPLY_FILE = sys.argv[1:4]


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 (http.server's naming)
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"path": self.path, "headers": dict(self.headers),
                                 "body": json.loads(body or b"{}")}) + "\n")
        with open(REPLY_FILE, "rb") as fh:
            reply = fh.read()
        self.send_response(200 if self.path == "/v1/messages" else 404)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(PORT_FILE + ".tmp", "w") as fh:
    fh.write(str(server.server_address[1]))
os.replace(PORT_FILE + ".tmp", PORT_FILE)
server.serve_forever()
