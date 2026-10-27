# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Tests for LLM-written parsing templates (extract/llm/template.py), stdlib only.

    python3 -m unittest discover -s ml/tests -v
"""
import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "extract", "llm"))
import template as T  # noqa: E402

LINES = ["Status: ok", "Uptime:  3 days", "", "NAME    SIZE   MOUNTED ON", "-------------------",
         "sda1    40G    /boot", "sda2    1.2T   /data disk", "free text no one matches"]
TPL = {"format": 1, "tool": "disks", "detect": "^NAME\\s+SIZE",
       "skip": ["^-+$"],
       "blocks": [{"name": "disks", "kind": "table", "header": "^NAME\\s",
                   "line": "^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT])\\s+(?P<mount>/.*)$",
                   "columns": {"mount": "Mounted on"}},
                  {"name": "status", "kind": "kv", "line": "^(?P<key>[A-Z][a-z]+):\\s+(?P<value>.+)$"}]}


class Apply(unittest.TestCase):
    def test_lines_go_to_skip_header_and_blocks(self):
        blocks, cov, nb, skipped = T.apply(T.compile_template(TPL), LINES)
        self.assertEqual((cov, nb, skipped), (6, 7, 1))
        self.assertEqual([b["name"] for b in blocks], ["disks", "status"])
        self.assertEqual(blocks[0]["records"][1], {"name": "sda2", "size": "1.2T", "Mounted_on": "/data disk"})
        self.assertEqual(blocks[1]["records"], [{"Status": "ok"}, {"Uptime": "3 days"}])

    def test_flat_records(self):
        blocks, *_ = T.apply(T.compile_template(TPL), LINES)
        self.assertEqual(T.flat_records(blocks[1]), ["Status ok", "Uptime 3 days"])
        recs = T.flat_records(blocks[0])
        self.assertIn("entry2.Mounted_on /data disk", recs)
        self.assertEqual(recs[-1], "total_entries 2")

    def test_a_repeated_kv_key_is_numbered(self):
        b = {"kind": "kv", "records": [{"a": "1"}, {"a": "2"}]}
        self.assertEqual(T.flat_records(b), ["a 1", "a_2 2"])

    def test_bad_templates_are_refused(self):
        for bad, why in ((dict(TPL, format=3), "format-1 or format-2"), (dict(TPL, blocks=[]), "at least one"),
                         (dict(TPL, blocks=[{"kind": "kv", "line": "^(?P<k>.*)$"}]), "key and value"),
                         (dict(TPL, blocks=[{"kind": "table", "line": "(unclosed"}]), "line"),
                         (dict(TPL, blocks=[{"kind": "table", "line": "^.*$"}]), "named groups")):
            with self.assertRaises(T.TemplateError) as cm:
                T.compile_template(bad)
            self.assertIn(why, str(cm.exception))

    def test_write_blocks(self):
        blocks, *_ = T.apply(T.compile_template(TPL), LINES)
        with tempfile.TemporaryDirectory() as d:
            T.write_blocks(blocks, LINES, d, "disks")
            self.assertEqual(open(os.path.join(d, "blk.1.txt")).read().splitlines()[0], "NAME    SIZE   MOUNTED ON")
            self.assertEqual(open(os.path.join(d, "blk.2.name")).read().strip(), "status")
            self.assertEqual(open(os.path.join(d, "tool")).read().strip(), "disks")


PARSER = '''import re
HEAD = re.compile(r"^(?P<n>\\d+): (?P<name>\\S+)$")
def parse(lines):
    rows, used, skip = [], [], []
    for j, ln in enumerate(lines):
        m = HEAD.match(ln)
        if m:
            rows.append({"n": m.group("n"), "name": m.group("name")}); used.append(j)
        elif ln.startswith("    ") and rows:
            k, v = ln.split(": ", 1); rows[-1][k.strip()] = v; used.append(j)
        elif ln.startswith("#"):
            skip.append(j)
    return {"blocks": [{"name": "items", "kind": "table", "lines": used, "records": rows}], "skip": skip}
'''
NESTED = ["# items", "1: alpha", "    size: 10 MB", "    state: up", "2: beta", "    size: 2 GB", "stray"]
TPL2 = {"format": 2, "tool": "items", "detect": "^\\d+: \\S+$", "parser": PARSER}


class Parser(unittest.TestCase):
    def test_a_parser_template_runs_in_the_box_and_counts_its_skips(self):
        blocks, cov, nb, skipped = T.apply(T.compile_template(TPL2), NESTED)
        self.assertEqual((cov, nb, skipped), (6, 7, 1))
        self.assertEqual(blocks[0]["records"][0], {"n": "1", "name": "alpha", "size": "10 MB", "state": "up"})
        self.assertEqual(blocks[0]["lines"], [1, 2, 3, 4, 5])
        self.assertEqual(T.flat_records(blocks[0])[-1], "total_entries 2")
        self.assertEqual(T._report(NESTED, TPL2), (6 / 7, [6]))

    def test_a_parser_that_imports_or_reaches_out_is_refused_before_it_runs(self):
        for code, why in (("import os\ndef parse(l): return []", "imports os"),
                          ("def parse(l):\n    return open('/etc/passwd')", "uses open"),
                          ("def parse(l):\n    return l.__class__", "__class__"),
                          ("def nothing(l): pass", "no parse"),
                          ("def parse(l:\n", "syntax error")):
            with self.assertRaises(T.TemplateError) as cm:
                T.compile_template(dict(TPL2, parser=code))
            self.assertIn(why, str(cm.exception))

    def test_a_runaway_or_broken_parser_is_an_error_not_a_hang(self):
        with self.assertRaises(T.TemplateError):
            T.apply(T.compile_template(dict(TPL2, parser="def parse(l):\n    while True: pass")), NESTED)
        for code, why in (("def parse(l):\n    return 7", "list of blocks"),
                          ("def parse(l):\n    return [{'kind': 'row'}]", "table or kv"),
                          ("def parse(l):\n    return [{'kind': 'kv', 'lines': [99], 'records': []}]", "line indexes"),
                          ("def parse(l):\n    raise ValueError('boom')", "boom"),
                          ("def parse(l):\n    import socket", "imports socket")):
            with self.assertRaises(T.TemplateError) as cm:
                T.apply(T.compile_template(dict(TPL2, parser=code)), NESTED)
            self.assertIn(why, str(cm.exception))

    def test_find_and_write_blocks_take_a_parser_template(self):
        with tempfile.TemporaryDirectory() as d:
            json.dump(TPL2, open(os.path.join(d, "items.json"), "w"))
            json.dump(TPL, open(os.path.join(d, "disks.json"), "w"))
            path, score = T.find(NESTED, [d])
            self.assertEqual(os.path.basename(path), "items.json")
            blocks, *_ = T.apply(T.compile_template(TPL2), NESTED)
            T.write_blocks(blocks, NESTED, os.path.join(d, "out"), "items")
            self.assertIn("entry2.size 2 GB", open(os.path.join(d, "out", "blk.1.rec")).read())


class Store(unittest.TestCase):
    def test_key_is_the_name_or_a_signature_of_the_first_lines(self):
        self.assertEqual(T.key(LINES, "df -h"), "df_-h.json")
        a = T.key(["Total 12 items", "x 1"])
        self.assertEqual(a, T.key(["Total 99 items", "x 7"]))     # digits folded
        self.assertNotEqual(a, T.key(["Other 12 items", "x 1"]))
        self.assertTrue(a.startswith("sig-"))

    def test_find_needs_detect_and_picks_the_best_cover(self):
        with tempfile.TemporaryDirectory() as d:
            json.dump(TPL, open(os.path.join(d, "disks.json"), "w"))
            json.dump(dict(TPL, detect="^nothing like this"), open(os.path.join(d, "other.json"), "w"))
            path, score = T.find(LINES, [d])
            self.assertEqual(os.path.basename(path), "disks.json")
            self.assertAlmostEqual(score, 6 / 7)

    def test_the_shipped_templates_compile_and_detect_their_sample(self):
        path, score = T.find(T.read_lines(os.path.join(ROOT, "extract", "samples", "llm-template", "basic.txt")),
                             [T.SHIPPED])
        self.assertEqual(os.path.basename(path), "mcstatus.json")
        self.assertEqual(score, 1.0)
        for f in os.listdir(T.SHIPPED):
            T.compile_template(T.load(os.path.join(T.SHIPPED, f)))


class FakeAPI:
    def setUp(self):
        self.calls, self._orig = [], T.call_claude

    def tearDown(self):
        T.call_claude = self._orig

    def fake(self, *replies):
        replies = list(replies)

        def call(system, messages, model, **kw):
            self.calls.append([dict(m) for m in messages])
            return replies.pop(0)
        T.call_claude = call


class Learn(FakeAPI, unittest.TestCase):

    def test_a_template_that_misses_lines_gets_one_more_try(self):
        poor = dict(TPL, blocks=TPL["blocks"][:1])         # no status block: 4/7
        good = dict(TPL, skip=TPL["skip"] + ["^free text"])
        self.fake(json.dumps(poor), "```json\n" + json.dumps(good) + "\n```")
        t = T.learn(LINES, "disks")
        self.assertEqual(t["blocks"][1]["name"], "status")
        self.assertEqual(len(self.calls), 2)
        self.assertIn("These lines match no skip, header or line pattern", self.calls[1][-1]["content"])
        self.assertIn("0 |Status: ok", self.calls[1][-1]["content"])

    def test_an_invalid_reply_is_sent_back_then_refused(self):
        self.fake("not json", json.dumps(dict(TPL, format=7)))
        with self.assertRaises(T.TemplateError) as cm:
            T.learn(LINES, "disks")
        self.assertIn("format-1", str(cm.exception))
        self.assertIn("invalid", self.calls[1][-1]["content"])

    def test_large_captures_are_not_sent(self):
        self.fake()
        with self.assertRaises(T.TemplateError):
            T.learn(["x"] * (T.MAX_LINES + 1))
        self.assertEqual(self.calls, [])

    def test_no_key_is_an_error_not_a_request(self):
        T.call_claude = self._orig
        env = {k: os.environ.pop(k) for k in ("PROVOST_LLM_API_KEY", "ANTHROPIC_API_KEY") if k in os.environ}
        try:
            with self.assertRaises(T.TemplateError) as cm:
                T.call_claude("s", [{"role": "user", "content": "x"}], "claude-opus-5-5")
            self.assertIn("no API key", str(cm.exception))
        finally:
            os.environ.update(env)

    def test_a_learned_template_keeps_its_capture(self):
        self.fake(json.dumps(dict(TPL, skip=TPL["skip"] + ["^free text"])))
        self.assertEqual(T.learn(LINES, "disks")["examples"], ["\n".join(LINES)])


class CallClaude(unittest.TestCase):
    """The HTTP side: transient errors are retried, the rest are not, and
    PROVOST_LLM_LOG gets each reply's usage."""
    REPLY = {"model": "claude-opus-5-5", "stop_reason": "end_turn", "usage": {"input_tokens": 3, "output_tokens": 2},
             "content": [{"type": "text", "text": "{}"}]}

    def setUp(self):
        import urllib.request
        self.ur, self._urlopen, self._sleep = urllib.request, urllib.request.urlopen, T.time.sleep
        self.env = {k: os.environ.get(k) for k in ("PROVOST_LLM_API_KEY", "PROVOST_LLM_LOG")}
        os.environ["PROVOST_LLM_API_KEY"] = "k-test"
        os.environ.pop("PROVOST_LLM_LOG", None)
        T.time.sleep = lambda s: None
        self.calls = 0

    def tearDown(self):
        self.ur.urlopen, T.time.sleep = self._urlopen, self._sleep
        for k, v in self.env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def serve(self, *outcomes):
        import io
        import urllib.error
        outcomes = list(outcomes)

        def urlopen(req, timeout=None):
            self.calls += 1
            o = outcomes.pop(0)
            if isinstance(o, int):
                raise urllib.error.HTTPError(req.full_url, o, "x", {}, io.BytesIO(b'{"error": {"message": "busy"}}'))
            if isinstance(o, Exception):
                raise o
            return io.BytesIO(json.dumps(o).encode())
        self.ur.urlopen = urlopen

    def test_an_overload_or_a_timeout_is_retried(self):
        import urllib.error
        self.serve(529, urllib.error.URLError(TimeoutError("timed out")), self.REPLY)
        self.assertEqual(T.call_claude("s", [], "m"), "{}")
        self.assertEqual(self.calls, 3)

    def test_a_bad_request_or_a_refused_connection_is_not(self):
        import urllib.error
        self.serve(400)
        with self.assertRaises(T.TemplateError) as cm:
            T.call_claude("s", [], "m")
        self.assertIn("400: busy", str(cm.exception))
        self.serve(urllib.error.URLError(ConnectionRefusedError("refused")))
        with self.assertRaises(T.TemplateError):
            T.call_claude("s", [], "m")
        self.assertEqual(self.calls, 2)

    def test_retries_run_out(self):
        self.serve(*[429] * (T.RETRIES + 1))
        with self.assertRaises(T.TemplateError) as cm:
            T.call_claude("s", [], "m")
        self.assertIn("429", str(cm.exception))
        self.assertEqual(self.calls, T.RETRIES + 1)

    def test_the_log_gets_each_replys_usage(self):
        with tempfile.TemporaryDirectory() as d:
            os.environ["PROVOST_LLM_LOG"] = os.path.join(d, "log")
            self.serve(self.REPLY)
            T.call_claude("s", [], "m", purpose="learn", tool="disks")
            rec = json.loads(open(os.environ["PROVOST_LLM_LOG"]).read())
        self.assertEqual((rec["purpose"], rec["tool"], rec["usage"]["output_tokens"]), ("learn", "disks", 2))


class Repair(FakeAPI, unittest.TestCase):
    """A stored template that meets a kind of line it has not seen goes back
    to Claude once, and the extension is kept only if it still reads the
    captures the template was written from."""
    NEW = LINES[:7] + ["sdb1    2T     -", "Health:  degraded", "free text no one matches"]
    STORED = dict(TPL, skip=TPL["skip"] + ["^free text"], examples=["\n".join(LINES)])
    WIDER = dict(STORED, blocks=[dict(TPL["blocks"][0], line="^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT])\\s+(?P<mount>/.*|-)$"),
                                 TPL["blocks"][1]])

    def test_a_kind_is_the_first_word_and_the_shape_of_the_rest(self):
        self.assertEqual(T._kind("eth0   up  1500"), T._kind("eth12 up 9000"))
        self.assertEqual(T._kind("-----"), T._kind("----------"))
        self.assertEqual(T._kind("Volumes on host alpha"), T._kind("Volumes on host beta-2"))
        self.assertNotEqual(T._kind("WARNING: disk full"), T._kind("INFO: disk full"))
        self.assertNotEqual(T._kind("+ExecStart=/usr/bin/x"), T._kind("6 overridden files found."))

    def test_misses_are_only_kinds_the_examples_did_not_show(self):
        self.assertEqual(T.misses(self.STORED, LINES), ([], []))
        self.assertEqual(T.misses(self.STORED, self.NEW), ([7], []))     # "Health:" is a kv line: read
        # a skip rule that swallows a new kind of line is a miss too...
        swallow = dict(self.STORED, skip=self.STORED["skip"] + ["^sdb"])
        self.assertEqual(T.misses(swallow, self.NEW), ([], [7]))
        # ...but only against examples: with none, every skip is new, and
        # only unread lines count
        self.assertEqual(T.misses(dict(swallow, examples=[]), self.NEW), ([], []))

    def test_an_extension_that_reads_the_new_lines_is_kept_with_the_capture(self):
        self.fake(json.dumps({k: v for k, v in self.WIDER.items() if k != "examples"}))
        t = T.repair(self.STORED, self.NEW, "disks")
        self.assertEqual(T.misses(t, self.NEW), ([], []))
        self.assertEqual(t["examples"], ["\n".join(LINES), "\n".join(self.NEW)])
        sent = self.calls[0][-1]["content"]
        self.assertIn("7 |sdb1    2T     -", sent)            # the unread line, numbered
        self.assertIn("Earlier capture 1", sent)             # the capture it was written from
        self.assertNotIn('"examples"', sent)                 # not the template's own copy of it

    def test_an_extension_that_loses_an_earlier_line_gets_one_more_try_then_is_refused(self):
        narrow = dict(self.WIDER, blocks=self.WIDER["blocks"][:1])     # drops the status kv
        self.fake(json.dumps(narrow), json.dumps(narrow))
        with self.assertRaises(T.TemplateError) as cm:
            T.repair(self.STORED, self.NEW, "disks")
        self.assertIn("no longer reads", str(cm.exception))
        self.assertIn("Status: ok", self.calls[1][-1]["content"])

    def test_an_unchanged_reply_is_accepted_and_the_capture_remembered(self):
        swallow = dict(self.STORED, skip=self.STORED["skip"] + ["^sdb"])
        self.fake(json.dumps(swallow))
        t = T.repair(swallow, self.NEW, "disks")
        self.assertEqual(T.misses(t, self.NEW), ([], []))    # sdb1 is now a known skip kind
        self.assertEqual(len(t["examples"]), 2)

    def test_examples_are_capped_keeping_the_first(self):
        t = dict(self.STORED, examples=["a", "b", "c"])
        self.fake(json.dumps(self.WIDER))
        ex = T.repair(t, self.NEW, "disks")["examples"]
        self.assertEqual(ex, ["a", "c", "\n".join(self.NEW)])


if __name__ == "__main__":
    unittest.main()
