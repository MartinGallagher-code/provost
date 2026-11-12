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

    def test_a_value_keeps_to_its_cell(self):
        # a parser that joins a multi-line body into one value: each
        # continuation line would otherwise be a field of its own
        b = {"name": "events", "kind": "table", "lines": [0],
             "records": [{"msg": "failed", "err": "err=<\nfailed to run\n>", "pid": 7},
                         {"msg": "a\tb", "err": "", "pid": 8}]}
        self.assertEqual(T.flat_records(b), ["entry1.msg failed", "entry1.err err=< failed to run >", "entry1.pid 7",
                                             "entry2.msg a b", "entry2.err ", "entry2.pid 8", "total_entries 2"])
        self.assertEqual(T.flat_records(dict(b, kind="kv", records=[{"doc": "one\r\ntwo"}])), ["doc one  two"])

    def test_notes_keep_the_lines_set_aside_that_carry_words(self):
        ct = T.compile_template(TPL)
        self.assertEqual(T.notes(ct, LINES), [{"line": "8", "kind": "unread", "text": "free text no one matches"}])
        # a skipped line that carries a word is a note; a rule is not
        lines = LINES + ["  ===  ", "Version 2.1 (c) 2026"]
        ct = T.compile_template(dict(TPL, skip=TPL["skip"] + ["^free text", "^\\s*=+\\s*$", "^Version "]))
        self.assertEqual([(n["line"], n["kind"]) for n in T.notes(ct, lines)], [("8", "skipped"), ("10", "skipped")])
        # a parser's skipped and unread lines alike
        self.assertEqual(T.notes(T.compile_template(TPL2), NESTED),
                         [{"line": "1", "kind": "skipped", "text": "# items"},
                          {"line": "7", "kind": "unread", "text": "stray"}])

    def test_write_blocks_writes_the_notes_as_a_tidy_table(self):
        ct = T.compile_template(TPL)
        blocks = T.apply(ct, LINES)[0]
        with tempfile.TemporaryDirectory() as d:
            T.write_blocks(blocks, LINES, d, "disks", T.notes(ct, LINES))
            with open(os.path.join(d, "notes.tsv"), encoding="utf-8") as fh:
                self.assertEqual(fh.read(), "line\tkind\ttext\n8\tunread\tfree text no one matches\n")
            T.write_blocks(blocks, LINES, d, "disks")          # none this time: no stale notes
            self.assertFalse(os.path.exists(os.path.join(d, "notes.tsv")))

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


PASS = json.dumps({"verdict": "PASS"})


class FakeAPI:
    def setUp(self):
        self.calls, self.purposes, self._orig = [], [], T.call_claude

    def tearDown(self):
        T.call_claude = self._orig

    def fake(self, *replies):
        """Each call gets the next reply; an exception is raised instead."""
        replies = list(replies)

        def call(system, messages, model, **kw):
            self.calls.append([dict(m) for m in messages])
            self.purposes.append(kw.get("purpose"))
            r = replies.pop(0)
            if isinstance(r, Exception):
                raise r
            return r
        self.purposes = []
        T.call_claude = call


class Learn(FakeAPI, unittest.TestCase):

    def test_a_template_that_misses_lines_gets_one_more_try(self):
        poor = dict(TPL, blocks=TPL["blocks"][:1])         # no status block: 4/7
        good = dict(TPL, skip=TPL["skip"] + ["^free text"])
        self.fake(json.dumps(poor), "```json\n" + json.dumps(good) + "\n```", json.dumps(good), PASS)
        t = T.learn(LINES, "disks")
        self.assertEqual(t["blocks"][1]["name"], "status")
        self.assertEqual(self.purposes, ["learn", "learn", "audit", "judge"])   # the third: its skip audit
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
        good = json.dumps(dict(TPL, skip=TPL["skip"] + ["^free text"]))
        self.fake(good, good, PASS)
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
        # a template from before the skip audit, with no examples: nothing it
        # sets aside has been judged, so every line it sets aside that
        # carries words is a miss (the rule line, decoration, never is)
        self.assertEqual(T.misses(dict(swallow, examples=[]), self.NEW), ([], [7, 9]))
        # judged decoration, a kind is not a miss again
        judged = dict(swallow, examples=[], decoration=[T._kind("free text no one matches")])
        self.assertEqual(T.misses(judged, self.NEW), ([], [7]))

    def test_an_extension_that_reads_the_new_lines_is_kept_with_the_capture(self):
        self.fake(json.dumps({k: v for k, v in self.WIDER.items() if k != "examples"}), PASS)
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
        self.fake(json.dumps(swallow), PASS)
        t = T.repair(swallow, self.NEW, "disks")
        self.assertEqual(T.misses(t, self.NEW), ([], []))    # sdb1 is now a known skip kind
        self.assertEqual(len(t["examples"]), 2)

    def test_examples_are_capped_keeping_the_first(self):
        t = dict(self.STORED, examples=["a", "b", "c"])
        self.fake(json.dumps(self.WIDER), PASS)
        ex = T.repair(t, self.NEW, "disks")["examples"]
        self.assertEqual(ex, ["a", "c", "\n".join(self.NEW)])


class SkipAudit(FakeAPI, unittest.TestCase):
    """A skipped line is not covered for free: one with no letter or digit
    is decoration; one that carries a word or a number is set aside, and
    covered only once Claude has judged its kind decoration."""
    # skips the status lines and the stray prose; reads the disks table
    ASIDE = dict(TPL, skip=["^-+$", "^[A-Z][a-z]+:", "^free text"], blocks=TPL["blocks"][:1])
    READ_STATUS = dict(TPL, skip=["^-+$", "^free text"])     # what a good audit reply looks like

    def test_a_skipped_line_is_decoration_judged_or_not(self):
        a = T.audit(dict(self.ASIDE, decoration=[]), LINES)
        self.assertEqual((sorted(a["decoration"]), sorted(a["judged"]), sorted(a["unjudged"])), ([4], [], [0, 1, 7]))
        self.assertAlmostEqual(T.coverage(a), 4 / 7)          # header, two rows and the rule
        judged = dict(self.ASIDE, decoration=[T._kind("free text no one matches")])
        a = T.audit(judged, LINES)
        self.assertEqual((sorted(a["judged"]), sorted(a["unjudged"])), ([7], [0, 1]))
        self.assertAlmostEqual(T.coverage(a), 5 / 7)

    def test_a_template_from_before_the_audit_trusts_what_its_examples_set_aside(self):
        legacy = dict(self.ASIDE, examples=["\n".join(LINES)])   # no "decoration" record
        self.assertEqual(T.audit(legacy, LINES)["unjudged"], set())
        self.assertEqual(T.misses(legacy, LINES), ([], []))
        # ...but not a kind its examples never set aside
        self.assertEqual(T.misses(legacy, LINES + ["Health: degraded"]), ([], [8]))

    def test_find_does_not_count_set_aside_lines_as_covered(self):
        with tempfile.TemporaryDirectory() as d:
            for name, t in (("a-skips.json", dict(self.ASIDE, decoration=[])),
                            ("b-reads.json", dict(self.READ_STATUS, decoration=[]))):
                with open(os.path.join(d, name), "w") as fh:
                    json.dump(t, fh)
            # both "cover" 100% if a skipped line counted; only b reads the status
            path, score = T.find(LINES, [d])
        self.assertEqual(os.path.basename(path), "b-reads.json")
        self.assertAlmostEqual(score, 6 / 7)

    def test_learn_shows_what_it_sets_aside_once_and_keeps_a_reply_that_reads_it(self):
        self.fake(json.dumps(self.ASIDE), json.dumps(self.READ_STATUS), PASS)
        t = T.learn(LINES, "disks")
        self.assertEqual(self.purposes, ["learn", "audit", "judge"])
        ask = self.calls[1][-1]["content"]
        self.assertIn("sets aside 3 line(s) that carry words or numbers, as decoration (skip): 3 kind(s)", ask)
        self.assertIn("0 |Status: ok\n    (1 line of this kind)", ask)       # one line per kind, with a count
        self.assertIn("7 |free text no one matches\n    (1 line of this kind)", ask)
        self.assertEqual([b["name"] for b in t["blocks"]], ["disks", "status"])
        self.assertEqual(t["decoration"], [T._kind("free text no one matches")])   # judged: shown, still skipped
        self.assertEqual(T.audit(t, LINES)["unjudged"], set())

    def test_an_audit_reply_that_reads_less_is_not_kept_and_nothing_is_judged(self):
        worse = dict(self.ASIDE, skip=self.ASIDE["skip"] + ["^sda"])          # now skips a data row
        self.fake(json.dumps(self.ASIDE), json.dumps(worse), PASS)
        t = T.learn(LINES, "disks")
        self.assertEqual(t["skip"], self.ASIDE["skip"])
        self.assertEqual(t["decoration"], [])
        self.assertEqual(sorted(T.audit(t, LINES)["unjudged"]), [0, 1, 7])     # counted as unread

    def test_an_audit_that_cannot_be_had_leaves_the_template_unjudged(self):
        self.fake(json.dumps(self.ASIDE), T.TemplateError("the API answered 529"), PASS)
        t = T.learn(LINES, "disks")
        self.assertEqual((t["decoration"], t["examples"]), ([], ["\n".join(LINES)]))

    def test_a_template_that_sets_nothing_aside_is_not_audited(self):
        self.fake(json.dumps(TPL), PASS)                                      # skips only the rule
        t = T.learn(LINES[:7], "disks")                                       # no prose line
        self.assertEqual((self.purposes, t["decoration"]), (["learn", "judge"], []))

    def test_many_lines_of_one_kind_are_shown_once_with_their_count(self):
        lines = LINES[:7] + [f"note {i}: kept for reference" for i in range(5)]
        self.fake(json.dumps(dict(TPL, skip=["^-+$", "^note "])), json.dumps(dict(TPL, skip=["^-+$", "^note "])), PASS)
        t = T.learn(lines, "disks")
        ask = self.calls[1][-1]["content"]
        self.assertIn("7 |note 0: kept for reference\n    (5 lines of this kind)", ask)
        self.assertNotIn("8 |note 1", ask)
        self.assertEqual(t["decoration"], [T._kind("note 0: kept for reference")])

    def test_a_new_kind_set_aside_is_a_miss_and_repair_judges_it(self):
        stored = dict(TPL, skip=["^-+$", "^free text", "^Health:"], decoration=[T._kind("free text no one matches")],
                      examples=["\n".join(LINES)])
        new = LINES + ["Health:  degraded"]
        self.assertEqual(T.misses(stored, new), ([], [8]))
        self.fake(json.dumps(T._bare(stored)), PASS)                          # unchanged: decoration after all
        t = T.repair(stored, new, "disks")
        ask = self.calls[0][-1]["content"]
        self.assertIn("8 |Health:  degraded\n    (1 line of this kind)", ask)
        self.assertNotIn('"decoration"', ask)                                 # provost's record, not a pattern
        self.assertIn(T._kind("Health:  degraded"), t["decoration"])
        self.assertEqual(T.misses(t, new), ([], []))

    def test_a_skip_share_far_above_the_earlier_captures_is_a_miss(self):
        stored = dict(TPL, skip=["^-+$", "^free text"], decoration=[T._kind("free text no one matches")],
                      examples=["\n".join(LINES)])                            # 1 of 7 set aside
        flood = LINES[:7] + ["free text no one matches"] * 5                  # 5 of 11
        self.assertEqual(T.misses(stored, flood)[1], [7, 8, 9, 10, 11])
        self.assertEqual(T.misses(stored, LINES[:7] + ["free text no one matches"] * 2)[1], [])   # under the floor

    def test_apply_prints_the_audit(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory() as d:
            tp, ip = os.path.join(d, "t.json"), os.path.join(d, "in.txt")
            with open(tp, "w") as fh:
                json.dump(dict(self.ASIDE, decoration=[T._kind("free text no one matches")]), fh)
            with open(ip, "w") as fh:
                fh.write("\n".join(LINES) + "\n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(T.main(["apply", tp, ip]), 0)
            # blocks, coverage, skipped, decoration, judged, not judged, read, unread, format
            self.assertEqual(out.getvalue().split(), ["1", "71", "4", "1", "1", "2", "3", "0", "1"])
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                T.main(["audit", tp, ip])
        self.assertIn("4 skipped: 1 decoration, 1 set aside of a kind judged decoration, 2 set aside of a kind not "
                      "judged (counted as unread); coverage 71%", out.getvalue())
        self.assertIn("0 |Status: ok\n    (1 line of this kind)", out.getvalue())


class EarlierCaptures(FakeAPI, unittest.TestCase):
    """An extension must still read every capture the template was written
    from, not only the examples it keeps (the first and the latest)."""
    NEW = Repair.NEW
    WIDER = Repair.WIDER

    def test_an_extension_is_checked_against_captures_beyond_its_examples(self):
        stored = dict(Repair.STORED, examples=["\n".join(LINES)])
        # a capture it was written from, no longer among its examples, with
        # a mount on a path with a space: WIDER's mount pattern reads it, a
        # narrower one would not
        older = "\n".join(LINES[:5] + ["sdc1    10G    /mnt/old disk"])
        narrow = dict(self.WIDER, blocks=[dict(self.WIDER["blocks"][0],
                                               line="^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT])\\s+(?P<mount>/\\S*|-)$"),
                                          self.WIDER["blocks"][1]])
        self.fake(json.dumps(T._bare(narrow)), json.dumps(T._bare(narrow)))
        with self.assertRaises(T.TemplateError) as cm:
            T.repair(stored, self.NEW, "disks", earlier=[older])
        self.assertIn("another capture it was written from (1 of 1, not shown above) it no longer reads",
                      str(cm.exception))
        self.assertNotIn("/mnt/old disk", self.calls[0][-1]["content"])       # checked, not sent
        self.assertIn("5 |sdc1    10G    /mnt/old disk", self.calls[1][-1]["content"])   # but named when lost
        # the wider extension reads it: kept, the capture added to its examples
        self.fake(json.dumps(T._bare(self.WIDER)), PASS)
        t = T.repair(stored, self.NEW, "disks", earlier=[older, "\n".join(LINES)])
        self.assertEqual(t["examples"], ["\n".join(LINES), "\n".join(self.NEW)])

    def test_the_cli_reads_them_from_files(self):
        with tempfile.TemporaryDirectory() as d:
            paths = {k: os.path.join(d, k) for k in ("t.json", "new.txt", "older.txt", "out.json")}
            with open(paths["t.json"], "w") as fh:
                json.dump(Repair.STORED, fh)
            with open(paths["new.txt"], "w") as fh:
                fh.write("\n".join(self.NEW) + "\n")
            with open(paths["older.txt"], "w") as fh:
                fh.write("\n".join(LINES[:5] + ["sdc1    10G    /mnt/old disk"]) + "\n")
            self.fake(json.dumps(T._bare(self.WIDER)), PASS)
            import contextlib
            import io
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = T.main(["repair", paths["t.json"], paths["new.txt"], "--out", paths["out.json"],
                             "--earlier", paths["older.txt"]])
            self.assertEqual((rc, out.getvalue()), (0, "extended\na review passed it\n"))
            self.assertEqual(len(T.load(paths["out.json"])["examples"]), 2)


class Judge(FakeAPI, unittest.TestCase):
    """After learn and after repair one more call reviews what the template
    makes of the capture: PASS, or a list of structural fixes fed back to the
    writer once. The revision is kept only if it holds; nothing the review
    does can cost the template."""
    GOOD = dict(TPL, skip=TPL["skip"] + ["^free text"])
    # a table that keeps the mount, but not the device's parent: the fix
    # the judge asks for adds a column (still reads every line)
    FIXED = dict(GOOD, blocks=[dict(TPL["blocks"][0], line="^(?P<name>(?P<disk>[a-z]+)\\d+)\\s+(?P<size>[\\d.]+[KMGT])\\s+(?P<mount>/.*)$"),
                               TPL["blocks"][1]])
    FIX = json.dumps({"verdict": "FIX", "fixes": ["add a disk column: sda1 and sda2 are partitions of sda"]})

    def test_show_lays_out_the_tables_and_the_lines_set_aside(self):
        out = T.show(self.GOOD, LINES)
        self.assertIn("Table 1: disks (table, 2 rows, read from lines 3, 5-6)", out)
        self.assertIn("name\tsize\tMounted_on\nsda1\t40G\t/boot\nsda2\t1.2T\t/data disk", out)
        self.assertIn("Table 2: status (kv, 2 rows, read from lines 0-1)", out)
        self.assertIn("key\tvalue\nStatus\tok\nUptime\t3 days", out)
        self.assertIn("4 |-------------------    [skipped as decoration]", out)
        self.assertIn("7 |free text no one matches    [skipped as decoration]", out)
        self.assertIn("unread", T.show(TPL, LINES))

    def test_show_caps_the_rows_it_lists(self):
        lines = ["NAME SIZE MOUNTED ON"] + [f"sd{i} 1G /m{i}" for i in range(T.JUDGE_ROWS + 5)]
        out = T.show(TPL, lines)
        self.assertIn(f"sd{T.JUDGE_ROWS - 1}\t1G", out)
        self.assertNotIn(f"sd{T.JUDGE_ROWS}\t1G", out)
        self.assertIn("... and 5 more", out)

    def test_ranges(self):
        self.assertEqual(T._ranges([9, 3, 4, 5, 11, 12]), "3-5, 9, 11-12")
        self.assertEqual(T._ranges([]), "")

    def test_a_pass_is_recorded_and_nothing_else_changes(self):
        self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD), PASS)
        t = T.learn(LINES, "disks")
        self.assertEqual(t["judge"], {"verdict": "PASS"})
        self.assertEqual(T._bare(t), self.GOOD)
        self.assertEqual(self.purposes, ["learn", "audit", "judge"])
        sent = self.calls[2][-1]["content"]
        self.assertIn("6 |sda2    1.2T   /data disk", sent)            # the capture, numbered
        self.assertIn("Table 1: disks", sent)                            # what the template makes of it
        self.assertNotIn('"examples"', sent)
        self.assertEqual(T.review_summary(t), "a review passed it")

    def test_fixes_are_fed_back_once_and_a_revision_that_holds_is_kept(self):
        self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD), self.FIX, json.dumps(self.FIXED))
        t = T.learn(LINES, "disks")
        self.assertEqual(self.purposes, ["learn", "audit", "judge", "revise"])
        self.assertIn("1. add a disk column", self.calls[3][-1]["content"])
        self.assertEqual(t["blocks"][0]["line"], self.FIXED["blocks"][0]["line"])
        self.assertEqual(t["judge"], {"verdict": "FIX", "fixes": ["add a disk column: sda1 and sda2 are partitions of sda"],
                                      "applied": True})
        self.assertEqual(t["examples"], ["\n".join(LINES)])
        self.assertEqual(t["tool"], "disks")
        self.assertEqual(t["decoration"], [T._kind("free text no one matches")])   # the skip audit's, kept
        self.assertEqual(T.review_summary(t), "revised after a review asked for 1 fix")
        recs = T.apply(t, LINES)[0][0]["records"]
        self.assertEqual(recs[1], {"name": "sda2", "disk": "sda", "size": "1.2T", "Mounted_on": "/data disk"})

    def test_a_revision_that_reads_less_gets_one_more_try_then_the_template_stays(self):
        narrow = dict(self.FIXED, blocks=self.FIXED["blocks"][:1])     # drops the status lines
        self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD), self.FIX, json.dumps(narrow), json.dumps(narrow))
        t = T.learn(LINES, "disks")
        self.assertEqual(self.purposes, ["learn", "audit", "judge", "revise", "revise"])
        self.assertIn("falls short", self.calls[4][-1]["content"])
        self.assertEqual(T._bare(t), self.GOOD)                          # kept as it was
        self.assertFalse(t["judge"]["applied"])
        self.assertIn("covers 71%", t["judge"]["why"])
        self.assertIn("a review asked for 1 fix that did not hold", T.review_summary(t))

    def test_a_failed_review_never_costs_the_template(self):
        for bad in ("not json", json.dumps({"verdict": "MAYBE"}), json.dumps({"verdict": "FIX", "fixes": []})):
            self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD), bad)
            t = T.learn(LINES, "disks")
            self.assertEqual(T._bare(t), self.GOOD)
            self.assertEqual(t["judge"]["verdict"], "none")
            self.assertTrue(T.review_summary(t).startswith("not reviewed: "))

    def test_the_api_failing_on_the_review_keeps_the_template(self):
        replies = [json.dumps(self.GOOD), json.dumps(self.GOOD)]

        def call(system, messages, model, **kw):
            if kw.get("purpose") == "judge":
                raise T.TemplateError("the API answered 529: busy")
            return replies.pop(0)
        T.call_claude = call
        t = T.learn(LINES, "disks")
        self.assertEqual(t["judge"], {"verdict": "none", "why": "the API answered 529: busy"})

    def test_fixes_are_capped(self):
        many = json.dumps({"verdict": "FIX", "fixes": [f"fix {i}" for i in range(9)] + ["", 3]})
        self.assertEqual(T._verdict(many), ("FIX", [f"fix {i}" for i in range(T.MAX_FIXES)]))

    def test_no_review_when_asked(self):
        self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD))
        t = T.learn(LINES, "disks", review=False)
        self.assertNotIn("judge", t)
        self.assertEqual(self.purposes, ["learn", "audit"])

    def test_after_repair_a_revision_must_still_read_the_earlier_captures(self):
        stored = dict(Repair.STORED)
        wider = {k: v for k, v in Repair.WIDER.items() if k != "examples"}
        narrow = dict(wider, blocks=wider["blocks"][:1], skip=wider["skip"] + ["^[A-Z][a-z]+:"])
        self.fake(json.dumps(wider), self.FIX, json.dumps(narrow), json.dumps(narrow))
        t = T.repair(stored, Repair.NEW, "disks")
        self.assertEqual(self.purposes, ["repair", "judge", "revise", "revise"])
        self.assertIn("Earlier capture 1", self.calls[2][-1]["content"])
        self.assertIn("on earlier capture 1 it no longer reads 2 line(s)", t["judge"]["why"])
        self.assertEqual(T._bare(t), wider)                              # the repair, kept
        self.assertEqual(t["examples"], ["\n".join(LINES), "\n".join(Repair.NEW)])

    def test_after_repair_a_revision_must_still_read_the_captures_beyond_its_examples(self):
        # the skip audit's ledger captures (--earlier) are checked, not sent,
        # by the judge's revision as by the repair
        stored = dict(Repair.STORED, examples=["\n".join(LINES)])
        older = "\n".join(LINES[:5] + ["sdc1    10G    /mnt/old disk"])
        wider = T._bare(Repair.WIDER)
        narrow = dict(wider, blocks=[dict(wider["blocks"][0],
                                          line="^(?P<name>\\S+)\\s+(?P<size>[\\d.]+[KMGT])\\s+(?P<mount>/\\S*|-)$"),
                                     wider["blocks"][1]])
        self.fake(json.dumps(wider), self.FIX, json.dumps(narrow), json.dumps(narrow))
        t = T.repair(stored, Repair.NEW, "disks", earlier=[older])
        self.assertEqual(self.purposes, ["repair", "judge", "revise", "revise"])
        self.assertNotIn("/mnt/old disk", self.calls[2][-1]["content"])
        self.assertIn("another capture it was written from (1 of 1, not shown above) it no longer reads",
                      t["judge"]["why"])
        self.assertEqual(T._bare(t), wider)                              # the repair, kept
        self.assertIn("decoration", t)

    def test_a_stored_verdict_is_not_sent_or_taken_back(self):
        stored = dict(self.GOOD, judge={"verdict": "PASS"}, examples=["\n".join(LINES)])
        self.fake(json.dumps(dict(self.GOOD, judge={"verdict": "PASS"})), PASS)
        t = T.repair(stored, Repair.NEW, "disks")
        self.assertNotIn('"judge"', self.calls[0][-1]["content"])
        self.assertNotIn('"judge"', self.calls[1][-1]["content"])
        self.assertEqual(t["judge"], {"verdict": "PASS"})

    def test_the_cli_prints_what_happened_and_the_review(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory() as d:
            inp, out = os.path.join(d, "in.txt"), os.path.join(d, "t.json")
            with open(inp, "w") as fh:
                fh.write("\n".join(LINES) + "\n")
            self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD), self.FIX, json.dumps(self.FIXED))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                self.assertEqual(T.main(["learn", inp, "--out", out, "--tool", "disks"]), 0)
            self.assertEqual(buf.getvalue(), "learned\nrevised after a review asked for 1 fix\n")
            self.assertTrue(T.load(out)["judge"]["applied"])
            # --no-judge: one call, no verdict
            self.fake(json.dumps(self.GOOD), json.dumps(self.GOOD))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                self.assertEqual(T.main(["learn", inp, "--out", out, "--no-judge"]), 0)
            self.assertEqual((buf.getvalue(), self.purposes), ("learned\n", ["learn", "audit"]))
            self.assertNotIn("judge", T.load(out))
            # judge: a stored template reviewed on its own capture
            self.fake(PASS)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                self.assertEqual(T.main(["judge", out, inp, "--out", out + "2"]), 0)
            self.assertEqual(buf.getvalue(), "reviewed\na review passed it\n")
            self.assertEqual(T.load(out + "2")["judge"], {"verdict": "PASS"})
            self.assertEqual(T.load(out + "2")["examples"], ["\n".join(LINES)])


if __name__ == "__main__":
    unittest.main()
