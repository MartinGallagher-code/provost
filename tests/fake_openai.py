# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""A stand-in for an OpenAI-compatible Chat Completions server (vLLM,
llama.cpp's server, Ollama), for the smoke test of `provost --llm` with
PROVOST_LLM_API=openai (no network, no key, no cost).

    python3 tests/fake_openai.py PORT_FILE LOG_FILE REPLY_FILE

Listens on 127.0.0.1 (an ephemeral port, written to PORT_FILE), answers
every POST /v1/chat/completions with REPLY_FILE and appends each request's
path, headers and body to LOG_FILE as one JSON line; any other path gets a
404 (and is logged too, so a test can see a request went astray).

REPLY_FILE holds a JSON list of strings, the replies' text, in order (the
last answers the rest; the order starts again whenever REPLY_FILE changes).
Each is wrapped in a Chat Completions response body here.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT_FILE, LOG_FILE, REPLY_FILE = sys.argv[1:4]
STATE = {"seen": None, "n": 0}


def next_text():
    with open(REPLY_FILE, "rb") as fh:
        raw = fh.read()
    if raw != STATE["seen"]:
        STATE["seen"], STATE["n"] = raw, 0
    texts = json.loads(raw)
    text = texts[min(STATE["n"], len(texts) - 1)]
    STATE["n"] += 1
    return text


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 (http.server's naming)
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"path": self.path, "headers": dict(self.headers), "body": body}) + "\n")
        if self.path != "/v1/chat/completions":
            reply, code = json.dumps({"error": {"message": "no such route: " + self.path}}).encode(), 404
        else:
            reply = json.dumps({
                "id": "chatcmpl-1", "object": "chat.completion", "model": body.get("model"),
                "choices": [{"index": 0, "finish_reason": "stop",
                             "message": {"role": "assistant", "content": next_text()}}],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}}).encode()
            code = 200
        self.send_response(code)
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
