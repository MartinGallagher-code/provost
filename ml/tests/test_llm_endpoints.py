# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for --llm's endpoints and offline mode (extract/llm/template.py,
PV-019): the Anthropic and OpenAI-compatible wire formats against a stub
HTTP server on loopback, and offline mode, which must refuse before any
connection is opened. Stdlib only; nothing leaves 127.0.0.1.

    python3 -m unittest discover -s ml/tests -v
"""
import json
import os
import socket
import sys
import tempfile
import threading
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "extract", "llm"))
import template as T  # noqa: E402

ENV = ("PROVOST_LLM_API", "PROVOST_LLM_API_KEY", "ANTHROPIC_API_KEY", "PROVOST_LLM_BASE_URL",
       "PROVOST_LLM_OFFLINE", "PROVOST_LLM_ALLOW_HOSTS", "PROVOST_LLM_LOG", "PROVOST_WORKSPACE")
LINES = ["NAME    SIZE", "sda1    40G", "sda2    1.2T"]
GOOD = {"format": 1, "tool": "disks", "detect": "^NAME\\s+SIZE", "skip": [],
        "blocks": [{"name": "disks", "kind": "table", "header": "^NAME\\s",
                    "line": "^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT])$"}]}


class Env(unittest.TestCase):
    """Each test starts with every --llm setting unset, and gets them back."""

    def setUp(self):
        self._env = {k: os.environ.pop(k) for k in ENV if k in os.environ}

    def tearDown(self):
        for k in ENV:
            os.environ.pop(k, None)
        os.environ.update(self._env)


class Stub:
    """An HTTP server on 127.0.0.1 that records each request and answers
    with the next of REPLIES (a dict, sent as JSON with 200)."""

    def __init__(self, *replies):
        self.requests, replies = [], list(replies)
        stub = self

        class H(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))))
                stub.requests.append({"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()},
                                      "body": body})
                out = json.dumps(replies.pop(0) if len(replies) > 1 else replies[0]).encode()
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)

            def log_message(self, *a):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def chat(text, finish="stop", **message):
    return {"id": "chatcmpl-1", "object": "chat.completion", "model": "local-model",
            "choices": [{"index": 0, "finish_reason": finish, "message": dict({"role": "assistant", "content": text},
                                                                               **message)}],
            "usage": {"prompt_tokens": 5, "completion_tokens": 7, "total_tokens": 12}}


ANTH = {"model": "claude-opus-5-5", "stop_reason": "end_turn", "usage": {"input_tokens": 3, "output_tokens": 2},
        "content": [{"type": "text", "text": "{}"}]}


class OpenAI(Env):
    """PROVOST_LLM_API=openai: Chat Completions, a bearer key, the system
    prompt as the first message; the same prompt otherwise."""

    def setUp(self):
        super().setUp()
        os.environ.update(PROVOST_LLM_API="openai", PROVOST_LLM_API_KEY="k-local")

    def test_the_request_body_and_the_reply(self):
        stub = Stub(chat('{"a": 1}'))
        try:
            os.environ["PROVOST_LLM_BASE_URL"] = stub.url
            out = T.call_claude("SYS", [{"role": "user", "content": "hello"}], "org/model:q4", max_tokens=99)
        finally:
            stub.close()
        self.assertEqual(out, '{"a": 1}')
        (r,) = stub.requests
        self.assertEqual(r["path"], "/v1/chat/completions")
        self.assertEqual(r["headers"]["authorization"], "Bearer k-local")
        self.assertNotIn("x-api-key", r["headers"])
        self.assertNotIn("anthropic-version", r["headers"])
        self.assertEqual(r["body"], {"model": "org/model:q4", "max_tokens": 99,
                                     "messages": [{"role": "system", "content": "SYS"},
                                                  {"role": "user", "content": "hello"}]})

    def test_a_base_url_ending_in_v1_is_not_doubled(self):
        stub = Stub(chat("x"))
        try:
            os.environ["PROVOST_LLM_BASE_URL"] = stub.url + "/v1/"
            T.call_claude("s", [], "m")
        finally:
            stub.close()
        self.assertEqual(stub.requests[0]["path"], "/v1/chat/completions")

    def test_a_refusal_or_an_empty_reply_is_an_error(self):
        stub = Stub(chat(None, refusal="I can't help with that"), chat("", finish="length"))
        try:
            os.environ["PROVOST_LLM_BASE_URL"] = stub.url
            with self.assertRaises(T.TemplateError) as cm:
                T.call_claude("s", [], "m")
            self.assertIn("declined", str(cm.exception))
            with self.assertRaises(T.TemplateError) as cm:
                T.call_claude("s", [], "m")
            self.assertIn("finish reason length", str(cm.exception))
        finally:
            stub.close()

    def test_it_needs_a_base_url_and_never_takes_the_anthropic_key(self):
        with self.assertRaises(T.TemplateError) as cm:
            T.call_claude("s", [], "m")
        self.assertIn("needs PROVOST_LLM_BASE_URL", str(cm.exception))
        del os.environ["PROVOST_LLM_API_KEY"]
        os.environ.update(ANTHROPIC_API_KEY="sk-ant-secret", PROVOST_LLM_BASE_URL="http://127.0.0.1:9")
        with self.assertRaises(T.TemplateError) as cm:
            T.call_claude("s", [], "m")
        self.assertIn("no API key", str(cm.exception))

    def test_the_log_records_the_api(self):
        stub = Stub(chat("x"))
        with tempfile.TemporaryDirectory() as d:
            os.environ.update(PROVOST_LLM_BASE_URL=stub.url, PROVOST_LLM_LOG=os.path.join(d, "log"))
            try:
                T.call_claude("s", [], "m", purpose="learn", tool="disks")
            finally:
                stub.close()
            with open(os.path.join(d, "log"), encoding="utf-8") as fh:
                rec = json.loads(fh.read())
        self.assertEqual((rec["api"], rec["model"], rec["stop_reason"], rec["usage"]["completion_tokens"]),
                         ("openai", "local-model", "stop", 7))

    def test_learn_writes_a_template_through_it(self):
        stub = Stub(chat(json.dumps(GOOD)))
        try:
            os.environ["PROVOST_LLM_BASE_URL"] = stub.url
            t = T.learn(LINES, "disks", "local-model", review=False)
        finally:
            stub.close()
        self.assertEqual(t["blocks"][0]["name"], "disks")
        self.assertTrue(all(r["path"] == "/v1/chat/completions" for r in stub.requests))
        with open(T.GUIDE, encoding="utf-8") as fh:     # the same prompt as Claude gets
            self.assertEqual(stub.requests[0]["body"]["messages"][0], {"role": "system", "content": fh.read()})

    def test_an_unknown_api_is_refused(self):
        os.environ.update(PROVOST_LLM_API="gopher", PROVOST_LLM_BASE_URL="http://127.0.0.1:9")
        with self.assertRaises(T.TemplateError) as cm:
            T.call_claude("s", [], "m")
        self.assertIn("anthropic or openai", str(cm.exception))


class Anthropic(Env):
    """PROVOST_LLM_API unset: the Messages API, exactly as before."""

    def test_unset_is_the_messages_api(self):
        stub = Stub(ANTH)
        try:
            os.environ.update(PROVOST_LLM_API_KEY="k-test", PROVOST_LLM_BASE_URL=stub.url)
            self.assertEqual(T.call_claude("SYS", [{"role": "user", "content": "hi"}], "claude-opus-5-5"), "{}")
        finally:
            stub.close()
        (r,) = stub.requests
        self.assertEqual(r["path"], "/v1/messages")
        self.assertEqual((r["headers"]["x-api-key"], r["headers"]["anthropic-version"],
                          r["headers"]["anthropic-beta"]), ("k-test", T.API_VERSION, T.FALLBACK_BETA))
        self.assertNotIn("authorization", r["headers"])
        self.assertEqual(list(r["body"]), ["model", "max_tokens", "system", "messages", "output_config", "fallbacks"])
        self.assertEqual((r["body"]["system"], r["body"]["fallbacks"]), ("SYS", "default"))

    def test_anthropic_still_takes_ANTHROPIC_API_KEY(self):  # noqa: N802
        os.environ["ANTHROPIC_API_KEY"] = "k-a"
        self.assertEqual(T._api_key(), "k-a")
        self.assertEqual(T._api_key("openai"), "")


class Offline(Env):
    """Offline mode refuses before a request is built: no urlopen, no
    socket, whatever key and base URL are set."""

    def setUp(self):
        super().setUp()
        os.environ.update(PROVOST_LLM_API_KEY="k-test", ANTHROPIC_API_KEY="k-a",
                          PROVOST_LLM_BASE_URL="http://127.0.0.1:9")
        self._urlopen, self._socket = urllib.request.urlopen, socket.socket

        def forbidden(*a, **k):
            raise AssertionError("a network call was made in offline mode")
        urllib.request.urlopen = forbidden
        socket.socket = forbidden

    def tearDown(self):
        urllib.request.urlopen, socket.socket = self._urlopen, self._socket
        super().tearDown()

    def assert_refused(self, why):
        for api in ("anthropic", "openai"):
            os.environ["PROVOST_LLM_API"] = api
            with self.assertRaises(T.TemplateError) as cm:
                T.call_claude("s", [{"role": "user", "content": "x"}], "m")
            self.assertIn("offline mode is on", str(cm.exception))
            self.assertIn(why, str(cm.exception))
            # and every path that asks for a template: learn, repair, judge
            for call in (lambda: T.learn(LINES, "disks"),
                         lambda: T.repair(dict(GOOD, examples=["\n".join(LINES)]), LINES + ["sdb 9X extra words"],
                                          "disks"),
                         lambda: T.judge(GOOD, LINES, "disks")):
                with self.assertRaises(T.TemplateError) as cm:
                    call()
                self.assertIn("offline mode is on", str(cm.exception))

    def test_the_environment_turns_it_on(self):
        os.environ["PROVOST_LLM_OFFLINE"] = "1"
        self.assert_refused("PROVOST_LLM_OFFLINE=1")

    def test_the_stores_file_turns_it_on_whatever_the_environment_says(self):
        with tempfile.TemporaryDirectory() as ws:
            open(os.path.join(ws, T.OFFLINE_FILE), "w").close()
            os.environ.update(PROVOST_WORKSPACE=ws, PROVOST_LLM_OFFLINE="0")
            self.assert_refused("llm-offline")

    def test_off_is_off(self):
        self.assertEqual(T.offline(), "")
        os.environ["PROVOST_LLM_OFFLINE"] = "0"
        self.assertEqual(T.offline(), "")


class AllowHosts(Env):
    def test_a_host_not_listed_is_refused_before_a_request(self):
        stub = Stub(ANTH)
        try:
            os.environ.update(PROVOST_LLM_API_KEY="k", PROVOST_LLM_BASE_URL=stub.url,
                              PROVOST_LLM_ALLOW_HOSTS="llm.internal, gpu01")
            with self.assertRaises(T.TemplateError) as cm:
                T.call_claude("s", [], "m")
            self.assertIn("not in PROVOST_LLM_ALLOW_HOSTS", str(cm.exception))
            self.assertEqual(stub.requests, [])
            os.environ["PROVOST_LLM_ALLOW_HOSTS"] = "gpu01,127.0.0.1"
            self.assertEqual(T.call_claude("s", [], "m"), "{}")
            self.assertEqual(len(stub.requests), 1)
        finally:
            stub.close()


if __name__ == "__main__":
    unittest.main()
