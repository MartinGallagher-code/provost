# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Hand-written parsing templates (PV-039): the time limit, `template test`
and TextFSM templates (extract/llm/template.py). Stdlib only; the TextFSM
cases that run a template skip when the optional textfsm package is not
installed (CI's python-package job installs it).

    python3 -m unittest discover -s ml/tests -v
"""
import contextlib
import io
import json
import os
import signal
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "extract", "llm"))
import template as T  # noqa: E402

NTC = os.path.join(HERE, "data", "ntc-templates")

try:
    import textfsm  # noqa: F401
    HAVE_TEXTFSM = True
except ImportError:
    HAVE_TEXTFSM = False

VOLUMES = ["Volumes on host alpha", "NAME     SIZE   USED   MOUNT", "data     500G   120G   /srv/data",
           "backup   2T     1.5T   /srv/backup", "logs     100G   80G    /var/log", "3 volumes, 1 degraded"]
VOL_TPL = {"format": 1, "tool": "volumes", "detect": "^Volumes on host ", "skip": ["^Volumes on host "],
           "blocks": [{"name": "volumes", "kind": "table", "header": "^NAME\\s+SIZE",
                       "line": "^(?P<name>\\S+)\\s+(?P<size>\\S+)\\s+(?P<used>\\S+)\\s+(?P<mount>/\\S*)$"}]}
# (a+)+$ backtracks exponentially on a's that end in anything else
SLOW_TPL = {"format": 1, "tool": "slow", "detect": "^a",
            "blocks": [{"name": "x", "kind": "table", "line": "^(?P<a>(a+)+)$"}]}
SLOW_LINES = ["a" * 4000 + "b"]
LIMIT = "0.5"


def _run(argv):
    """template.py's main(ARGV) -> (rc, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        rc = T.main(argv)
    return rc, out.getvalue(), err.getvalue()


def _write(d, name, data):
    p = os.path.join(d, name)
    with open(p, "w", encoding="utf-8") as fh:
        if isinstance(data, (dict, list)):
            json.dump(data, fh)
        else:
            fh.write(data)
    return p


class TimeLimit(unittest.TestCase):
    def setUp(self):
        p = mock.patch.dict(os.environ, {"PROVOST_TEMPLATE_TIMEOUT": LIMIT})
        p.start()
        self.addCleanup(p.stop)

    def test_the_setting(self):
        for v, want in (("", T.TIMEOUT), ("abc", T.TIMEOUT), ("0", T.TIMEOUT), ("-3", T.TIMEOUT),
                        ("2.5", 2.5), (" 7 ", 7.0)):
            with mock.patch.dict(os.environ, {"PROVOST_TEMPLATE_TIMEOUT": v}):
                self.assertEqual(T.timeout(), want, v)
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(T.timeout(), T.TIMEOUT)

    def test_a_backtracking_regex_is_declined_within_the_limit(self):
        ct = T.compile_template(SLOW_TPL)
        for f in (T.apply, T._classify):
            t0 = time.monotonic()
            with self.assertRaises(T.TemplateTimeout) as cm:
                f(ct, SLOW_LINES)
            self.assertLess(time.monotonic() - t0, float(LIMIT) + 2)
            self.assertIn("took longer than 0.5s", str(cm.exception))
            self.assertIn("PROVOST_TEMPLATE_TIMEOUT", str(cm.exception))

    def test_the_timer_is_cleared_and_the_handler_put_back(self):
        before = signal.getsignal(signal.SIGALRM)
        T.apply(T.compile_template(VOL_TPL), VOLUMES)
        with self.assertRaises(T.TemplateTimeout):
            T.apply(T.compile_template(SLOW_TPL), SLOW_LINES)
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))
        self.assertIs(signal.getsignal(signal.SIGALRM), before)
        self.assertFalse(T._LIMIT["on"])

    def test_the_outermost_limit_counts(self):
        with T.time_limit():
            self.assertTrue(T._LIMIT["on"])
            with T.time_limit():        # runs under the outer one: no new clock
                pass
            self.assertTrue(T._LIMIT["on"])
            self.assertGreater(signal.getitimer(signal.ITIMER_REAL)[0], 0)
        self.assertFalse(T._LIMIT["on"])

    def test_a_format2_parser_has_the_same_limit(self):
        tpl = {"format": 2, "tool": "spin", "detect": "^a", "parser": "def parse(l):\n    while True: pass"}
        with mock.patch.dict(os.environ, {"PROVOST_TEMPLATE_TIMEOUT": "1"}):
            t0 = time.monotonic()
            with self.assertRaises(T.TemplateTimeout) as cm:
                T.apply(T.compile_template(tpl), ["a"])
        self.assertLess(time.monotonic() - t0, 4)
        self.assertIn("ran longer than 1s", str(cm.exception))

    def test_find_passes_over_a_slow_template_and_says_why(self):
        with tempfile.TemporaryDirectory() as d:
            slow = _write(d, "slow.json", SLOW_TPL)
            _write(d, "fine.json", {"format": 1, "tool": "fine", "detect": "^a",
                                    "blocks": [{"name": "x", "kind": "table", "line": "^(?P<a>a+b)$"}]})
            declined = []
            path, score = T.find(SLOW_LINES, [d], declined)
            self.assertEqual(os.path.basename(path), "fine.json")
            self.assertEqual([p for p, _ in declined], [slow])
            self.assertIn("took longer", declined[0][1])
            # the CLI says so on stderr, a line a template
            inp = _write(d, "in.txt", SLOW_LINES[0] + "\n")
            rc, out, err = _run(["find", inp, "--dirs", d])
        self.assertEqual(rc, 0)
        self.assertTrue(out.startswith(os.path.join(d, "fine.json") + "\t"))
        self.assertEqual(err.split("\t")[:2], ["declined", slow])

    def test_a_slow_detect_pattern_is_declined_too(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "slowdetect.json", dict(VOL_TPL, detect="^(a+)+$"))
            declined = []
            self.assertEqual(T.find(SLOW_LINES, [d], declined), (None, 0.0))
        self.assertEqual(len(declined), 1)

    def test_apply_on_the_command_line_exits_2_with_why(self):
        with tempfile.TemporaryDirectory() as d:
            rc, out, err = _run(["apply", _write(d, "slow.json", SLOW_TPL), _write(d, "in.txt", SLOW_LINES[0] + "\n")])
        self.assertEqual((rc, out), (2, ""))
        self.assertIn("template: it took longer than 0.5s", err)

    def test_apply_prints_the_templates_format_last(self):
        with tempfile.TemporaryDirectory() as d:
            rc, out, _ = _run(["apply", _write(d, "v.json", VOL_TPL), _write(d, "in.txt", "\n".join(VOLUMES) + "\n")])
        self.assertEqual(rc, 0)
        self.assertEqual(out.split()[-1], "1")


class TestCommand(unittest.TestCase):
    """`template.py test` (provost template test)."""

    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(self.d, ignore_errors=True))
        self.tpl = _write(self.d, "volumes.json", VOL_TPL)
        self.cap = _write(self.d, "volumes.txt", "\n".join(VOLUMES) + "\n")

    def test_it_prints_detect_coverage_tables_and_every_unread_line(self):
        rc, out, err = _run(["test", self.tpl, self.cap])
        self.assertEqual((rc, err), (0, ""))
        self.assertIn("template   volumes.json (format 1)\n", out)
        self.assertIn("detect     line 1: Volumes on host alpha\n", out)
        self.assertIn("coverage   67% of 6 non-blank lines: 4 read, 1 skipped (0 decoration, 0 of a kind judged "
                      "decoration, 1 of a kind not judged: counted as unread), 1 unread\n", out)
        self.assertIn("table 1: volumes (table, 3 rows, read from lines 2-5)\nname\tsize\tused\tmount\n"
                      "data\t500G\t120G\t/srv/data\n", out)
        # the kind to paste into "decoration", quoted
        self.assertIn('  "Volumes a"  (1 line; line 1: Volumes on host alpha)\n', out)
        self.assertIn("unread (1):\n      6 | 3 volumes, 1 degraded\n", out)

    def test_a_judged_kind_is_decoration(self):
        tpl = _write(self.d, "v2.json", dict(VOL_TPL, decoration=["Volumes a"]))
        rc, out, _ = _run(["test", tpl, self.cap])
        self.assertIn("coverage   83% of 6 non-blank lines: 4 read, 1 skipped (0 decoration, 1 of a kind judged", out)
        self.assertNotIn("set aside, of a kind not judged", out)

    def test_the_tables_alone_are_what_expected_takes(self):
        rc, out, _ = _run(["test", "--tables", self.tpl, self.cap])
        self.assertEqual(rc, 0)
        self.assertEqual(out, "name\tsize\tused\tmount\ndata\t500G\t120G\t/srv/data\n"
                              "backup\t2T\t1.5T\t/srv/backup\nlogs\t100G\t80G\t/var/log\n")
        exp = _write(self.d, "volumes.expected.tsv", out)
        rc, out, _ = _run(["test", self.tpl, self.cap, exp])
        self.assertEqual(rc, 0)
        self.assertIn("expected   the tables match\n", out)
        # CRLF line ends and trailing blank lines in EXPECTED do not count
        with open(exp, encoding="utf-8") as fh:
            exp2 = _write(self.d, "crlf.tsv", fh.read().replace("\n", "\r\n") + "\r\n\n")
        self.assertEqual(_run(["test", self.tpl, self.cap, exp2])[0], 0)

    def test_a_difference_is_a_diff_and_exit_1(self):
        exp = _write(self.d, "bad.tsv", "name\tsize\tused\tmount\ndata\t500G\t120G\t/srv/data\n"
                                        "backup\t3T\t1.5T\t/srv/backup\nlogs\t100G\t80G\t/var/log\n")
        rc, out, _ = _run(["test", self.tpl, self.cap, exp])
        self.assertEqual(rc, 1)
        self.assertIn("expected   the tables differ (- expected, + this template):", out)
        self.assertIn("-backup\t3T\t1.5T\t/srv/backup\n+backup\t2T\t1.5T\t/srv/backup\n", out)

    def test_several_tables_are_each_under_a_mark(self):
        tpl = _write(self.d, "two.json", dict(VOL_TPL, blocks=VOL_TPL["blocks"] + [
            {"name": "summary", "kind": "kv", "line": "^(?P<value>\\d+) (?P<key>volumes), .*$"}]))
        rc, out, _ = _run(["test", "--tables", tpl, self.cap])
        self.assertEqual(out, "# table: volumes\nname\tsize\tused\tmount\ndata\t500G\t120G\t/srv/data\n"
                              "backup\t2T\t1.5T\t/srv/backup\nlogs\t100G\t80G\t/var/log\n\n"
                              "# table: summary\nkey\tvalue\nvolumes\t3\n")
        self.assertEqual(_run(["test", tpl, self.cap, _write(self.d, "two.tsv", out)])[0], 0)
        # one table may be written either way
        marked = _write(self.d, "one.tsv", "# table: volumes\n" + _run(["test", "--tables", self.tpl, self.cap])[1])
        self.assertEqual(_run(["test", self.tpl, self.cap, marked])[0], 0)

    def test_no_tables_is_exit_1(self):
        cap = _write(self.d, "other.txt", "nothing here\n")
        rc, out, _ = _run(["test", self.tpl, cap])
        self.assertEqual(rc, 1)
        self.assertIn("detect     matches none of the first 200 lines", out)
        self.assertIn("no tables: the template reads nothing from this capture", out)
        self.assertEqual(_run(["test", "--tables", self.tpl, cap])[:2], (1, ""))

    def test_no_detect_says_it_is_used_by_name_only(self):
        tpl = _write(self.d, "nodetect.json", {k: v for k, v in VOL_TPL.items() if k != "detect"})
        self.assertIn("detect     none: provost uses it only for a capture it is named for",
                      _run(["test", tpl, self.cap])[1])

    def test_past_the_time_limit_is_exit_1(self):
        with mock.patch.dict(os.environ, {"PROVOST_TEMPLATE_TIMEOUT": LIMIT}):
            rc, out, err = _run(["test", _write(self.d, "slow.json", SLOW_TPL),
                                 _write(self.d, "slow.txt", SLOW_LINES[0] + "\n")])
        self.assertEqual((rc, out), (1, ""))
        self.assertIn("slow.json cannot read this capture: it took longer than 0.5s", err)

    def test_a_template_that_cannot_be_tried_is_exit_2(self):
        bad = {"notjson.json": "{not json", "badrx.json": dict(VOL_TPL, detect="(unclosed"),
               "nokind.json": dict(VOL_TPL, blocks=[{"line": "^(?P<a>x)$"}]),
               "list.json": [1, 2]}
        for name, data in bad.items():
            rc, out, err = _run(["test", _write(self.d, name, data), self.cap])
            self.assertEqual((rc, out), (2, ""), name)
            self.assertTrue(err.startswith("template: "), name)
        self.assertEqual(_run(["test", os.path.join(self.d, "missing.json"), self.cap])[0], 2)
        self.assertEqual(_run(["test", self.tpl, os.path.join(self.d, "missing.txt")])[0], 2)
        self.assertEqual(_run(["test", self.tpl, self.cap, os.path.join(self.d, "missing.tsv")])[0], 2)


TFSM = r"""Value Required NAME (\S+)
Value SIZE (\S+)
Value List FLAGS (\w+)

Start
  ^Disks: -> Disks

Disks
  ^disk -> Continue.Record
  ^disk ${NAME} ${SIZE}
  ^\s+flag ${FLAGS}
"""
DISKS = ["Disks:", "disk sda 40G", "  flag boot", "  flag ssd", "", "disk sdb 1T\r", "  flag data", "unknown line"]


class TextFSMTemplates(unittest.TestCase):
    def test_a_textfsm_file_loads_by_its_name(self):
        with tempfile.TemporaryDirectory() as d:
            t = T.load(_write(d, "my_disks.textfsm", TFSM))
        self.assertEqual(t, {"format": "textfsm", "tool": "my_disks", "textfsm": TFSM})

    def test_without_the_package_it_says_how_to_get_it(self):
        with mock.patch.dict(sys.modules, {"textfsm": None}):
            with self.assertRaises(T.TemplateError) as cm:
                T.compile_template({"format": "textfsm", "tool": "x", "textfsm": TFSM})
        self.assertIn("pip install 'provost[textfsm]'", str(cm.exception))

    def test_claude_never_extends_or_reviews_one(self):
        t = {"format": "textfsm", "tool": "x", "textfsm": TFSM}
        for f in (T.repair, T.judge):
            with self.assertRaises(T.TemplateError) as cm:
                f(t, DISKS)
            self.assertIn("TextFSM template is not", str(cm.exception))

    def test_find_passes_it_over(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "disks.json", {"format": "textfsm", "tool": "disks", "detect": "^Disks:", "textfsm": TFSM})
            _write(d, "disks.textfsm", TFSM)
            self.assertEqual(T.find(DISKS, [d]), (None, 0.0))

    @unittest.skipUnless(HAVE_TEXTFSM, "textfsm is not installed")
    def test_it_reads_one_table_and_classifies_each_line(self):
        ct = T.compile_template({"format": "textfsm", "tool": "my disks", "textfsm": TFSM})
        blocks, (read, skip, unread) = T._measure(ct, DISKS)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]["name"], "my_disks")
        self.assertEqual(blocks[0]["records"], [{"name": "sda", "size": "40G", "flags": "boot, ssd"},
                                                {"name": "sdb", "size": "1T", "flags": "data"}])
        # a rule with a Value: read; only rules without one: skipped; none: unread
        self.assertEqual((sorted(read), sorted(skip), sorted(unread)), ([1, 2, 3, 5, 6], [0], [7]))
        self.assertEqual(T.table_rows(blocks[0]), ["name\tsize\tflags", "sda\t40G\tboot, ssd", "sdb\t1T\tdata"])

    @unittest.skipUnless(HAVE_TEXTFSM, "textfsm is not installed")
    def test_an_error_rule_declines_it(self):
        ct = T.compile_template({"format": "textfsm", "tool": "x",
                                 "textfsm": TFSM + "  ^unknown -> Error \"not a disk\"\n"})
        with self.assertRaises(T.TemplateError) as cm:
            T.apply(ct, DISKS)
        self.assertIn("its Error rule stopped it on line 8", str(cm.exception))

    @unittest.skipUnless(HAVE_TEXTFSM, "textfsm is not installed")
    def test_a_bad_textfsm_template_is_refused(self):
        with self.assertRaises(T.TemplateError) as cm:
            T.compile_template({"format": "textfsm", "tool": "x", "textfsm": "Value NAME\n\nStart\n  ^x\n"})
        self.assertIn("textfsm:", str(cm.exception))

    @unittest.skipUnless(HAVE_TEXTFSM, "textfsm is not installed")
    def test_apply_prints_its_format(self):
        with tempfile.TemporaryDirectory() as d:
            rc, out, _ = _run(["apply", _write(d, "disks.textfsm", TFSM), _write(d, "in.txt", "\n".join(DISKS) + "\n")])
        self.assertEqual(rc, 0)
        self.assertEqual(out.split()[-1], "textfsm")

    @unittest.skipUnless(HAVE_TEXTFSM, "textfsm is not installed")
    def test_ntc_templates_fixtures_parse_to_their_records(self):
        # ntc-templates' own tests: NAME.raw parsed by NAME.textfsm must give
        # NAME.yml's parsed_sample (NAME.tsv: the same records as tables)
        for name in ("cisco_ios_show_version", "cisco_ios_show_interfaces"):
            f = os.path.join(NTC, name)
            rc, out, err = _run(["test", f + ".textfsm", f + ".raw", f + ".tsv"])
            self.assertEqual((rc, err), (0, ""), name + "\n" + out)
            self.assertIn("expected   the tables match", out)

    def test_the_expected_tables_are_the_yml_records(self):
        # NAME.tsv is NAME.yml's parsed_sample, cell for cell (checked where
        # PyYAML and textfsm are both installed)
        try:
            import yaml
        except ImportError:
            self.skipTest("PyYAML is not installed")
        if not HAVE_TEXTFSM:
            self.skipTest("textfsm is not installed")
        for name in ("cisco_ios_show_version", "cisco_ios_show_interfaces"):
            f = os.path.join(NTC, name)
            with open(f + ".textfsm", encoding="utf-8") as fh:
                header = [h.lower() for h in textfsm.TextFSM(fh).header]
            with open(f + ".yml", encoding="utf-8") as fh:
                recs = yaml.safe_load(fh)["parsed_sample"]

            def cell(v):
                return ", ".join(str(x) for x in v) if isinstance(v, list) else str(v)
            want = "\t".join(header) + "\n" + "".join("\t".join(cell(r[h]) for h in header) + "\n" for r in recs)
            with open(f + ".tsv", encoding="utf-8") as fh:
                self.assertEqual(fh.read(), want, name)


if __name__ == "__main__":
    unittest.main()
