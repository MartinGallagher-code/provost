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
        for bad, why in ((dict(TPL, format=2), "format-1"), (dict(TPL, blocks=[]), "at least one"),
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


class Learn(unittest.TestCase):
    def setUp(self):
        self.calls, self._orig = [], T.call_claude

    def tearDown(self):
        T.call_claude = self._orig

    def fake(self, *replies):
        replies = list(replies)

        def call(system, messages, model, **kw):
            self.calls.append(messages)
            return replies.pop(0)
        T.call_claude = call

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


if __name__ == "__main__":
    unittest.main()
