# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Building blocks for format generators: each generator imitates one tool's
output and labels every line as it writes it, so the labels are right by
construction (same format and conventions as ml/llm/GUIDE.md).

A generator is a module in ml/gen/tools/ with

    TOOL = "zpool-iostat"          # the command it imitates (family must be new: run.py --check)
    def generate(rng):             # rng: random.Random
        d = Doc()
        d.table(["NAME", "SIZE"], [[fake.word(rng), fake.size(rng)] for _ in range(rng.randint(2, 9))])
        return d

Doc methods add lines; every cell must appear verbatim in its line, in order
(run.py checks each sample with ml/llm/check.py). Stdlib only.
"""
import string


class Doc:
    def __init__(self):
        self.lines = []      # text
        self.labels = []     # {"role", "cells"}

    # -- the primitive: one line, its role and its cells -------------------
    def line(self, text, role, cells=()):
        self.lines.append(text)
        self.labels.append({"role": role, "cells": list(cells)})
        return self

    def blank(self):
        return self.line("", "blank")

    def skip(self, text):
        """Banners, rules, prose, footers: not data."""
        return self.line(text, "skip")

    def section(self, text, title=None):
        """A heading kept as a value; title defaults to the text stripped of
        common decoration."""
        t = title if title is not None else text.strip().strip("=-#[]:*").strip()
        return self.line(text, "section", [t])

    def kv(self, key, value, sep=": ", key_width=None, indent=""):
        """`key: value` (sep may be ' = ', '\\t', ' .... ', ...); key_width
        pads the key column. value may be a list for one key with several
        values (joined by two spaces)."""
        k = key.ljust(key_width) if key_width else key
        vals = value if isinstance(value, list) else [value]
        text = indent + k + sep + "  ".join(vals)
        return self.line(text, "kv", [key] + vals)

    def kvs(self, pairs, sep=": ", align=True, indent=""):
        w = max(len(k) for k, _ in pairs) if align and pairs else None
        if w and sep.strip() in (":", "="):
            # `Key:     value` (the separator hugs the key, padding after it)
            for k, v in pairs:
                text = indent + (k + sep.rstrip()).ljust(w + len(sep.rstrip())) + " " + v
                self.line(text, "kv", [k, v])
            return self
        for k, v in pairs:
            self.kv(k, v, sep, w, indent)
        return self

    def table(self, header, rows, gap=2, right=(), indent="", rule=None, header_case=None):
        """An aligned table. header: list of names (None for an unnamed
        column) or None for a headerless table; rows: lists of str or None
        (an empty cell). right: column indexes to right-align. rule: a
        character to draw a rule under the header with ('-', '=')."""
        ncol = len(header) if header else max(len(r) for r in rows)
        cols = [[(header[c] or "") if header else ""] + [(r[c] or "") if c < len(r) else "" for r in rows]
                for c in range(ncol)]
        width = [max(len(x) for x in col) for col in cols]

        def render(cells):
            out = indent
            for c in range(ncol):
                v = cells[c] or ""
                last = c == ncol - 1
                if c in right:
                    v = v.rjust(width[c])
                elif not last:
                    v = v.ljust(width[c])
                out += v + ("" if last else " " * gap)
            return out.rstrip()

        if header:
            self.line(render(header), "header", [h if h else None for h in header])
            if rule:
                self.skip(indent + (" " * gap).join(rule * w for w in width))
        for r in rows:
            r = list(r) + [None] * (ncol - len(r))
            cells = [v if v not in ("", None) else None for v in r]
            self.line(render(r), "row", cells if header else [v for v in cells if v is not None])
        return self

    def pipe_table(self, header, rows, border=True):
        """psql/mysql style: | a | b |, with +---+ rules when border."""
        ncol = len(header)
        width = [max(len(str(x or "")) for x in [header[c]] + [r[c] for r in rows]) for c in range(ncol)]
        rule = "+" + "+".join("-" * (w + 2) for w in width) + "+"

        def render(cells):
            body = " | ".join((cells[c] or "").ljust(width[c]) for c in range(ncol))
            return ("| " + body + " |") if border else body

        if border:
            self.skip(rule)
        self.line(render(header), "header", list(header))
        self.skip(rule if border else "-+-".join("-" * w for w in width))
        for r in rows:
            self.line(render(r), "row", [v if v else None for v in r])
        if border:
            self.skip(rule)
        return self

    def label(self):
        return {"lines": [{"n": j, **lab} for j, lab in enumerate(self.labels)]}


class fake:
    """Random values that look like real tool output."""
    WORDS = ("alpha beta gamma delta web api db cache queue worker auth billing search "
             "media mail gateway proxy edge core data log metrics batch stream backup "
             "frontend backend ingest report sync admin node agent store").split()
    USERS = "root alice bob carol dave erin frank grace www-data postgres nobody deploy svc".split()
    STATES = "running stopped active inactive failed pending ok degraded online offline up down".split()

    @staticmethod
    def word(rng):
        return rng.choice(fake.WORDS)

    @staticmethod
    def name(rng, sep="-"):
        return sep.join([fake.word(rng), fake.word(rng)] + ([str(rng.randint(1, 99))] if rng.random() < .5 else []))

    @staticmethod
    def user(rng):
        return rng.choice(fake.USERS)

    @staticmethod
    def state(rng):
        return rng.choice(fake.STATES)

    @staticmethod
    def num(rng, lo=0, hi=100000):
        return str(rng.randint(lo, hi))

    @staticmethod
    def flt(rng, lo=0.0, hi=100.0, dp=2):
        return f"{rng.uniform(lo, hi):.{dp}f}"

    @staticmethod
    def pct(rng, dp=0):
        return f"{rng.uniform(0, 100):.{dp}f}%"

    @staticmethod
    def size(rng, style="human"):
        n = rng.choice([rng.uniform(1, 999), rng.uniform(1, 99), rng.uniform(1, 9)])
        if style == "bytes":
            return str(int(n * rng.choice([1, 1024, 1024 ** 2])))
        unit = rng.choice(["K", "M", "G", "T"] if style == "human" else ["KiB", "MiB", "GiB", "TiB", "kB", "MB", "GB"])
        return (f"{n:.1f}" if n < 10 else f"{int(n)}") + unit

    @staticmethod
    def ip(rng, v6=False):
        if v6:
            return "fd00:" + ":".join(f"{rng.randint(0, 65535):x}" for _ in range(3)) + "::" + f"{rng.randint(1, 255):x}"
        return f"{rng.choice([10, 172, 192])}.{rng.randint(0, 255)}.{rng.randint(0, 255)}.{rng.randint(1, 254)}"

    @staticmethod
    def port(rng):
        return str(rng.choice([22, 53, 80, 443, 3306, 5432, 6379, 8080, 9090, rng.randint(1024, 65535)]))

    @staticmethod
    def mac(rng):
        return ":".join(f"{rng.randint(0, 255):02x}" for _ in range(6))

    @staticmethod
    def hexid(rng, n=12):
        return "".join(rng.choice("0123456789abcdef") for _ in range(n))

    @staticmethod
    def uuid(rng):
        h = fake.hexid(rng, 32)
        return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"

    @staticmethod
    def version(rng):
        return f"{rng.randint(0, 12)}.{rng.randint(0, 30)}.{rng.randint(0, 40)}"

    @staticmethod
    def path(rng, root="/"):
        parts = [rng.choice(["var", "opt", "srv", "home", "etc", "usr", "data", "mnt"])]
        parts += [fake.word(rng) for _ in range(rng.randint(1, 3))]
        return root + "/".join(parts)

    @staticmethod
    def host(rng):
        return f"{fake.word(rng)}-{rng.randint(1, 30):02d}.{rng.choice(['local', 'internal', 'example.com', 'lan'])}"

    @staticmethod
    def date(rng, fmt="iso"):
        y, m, d = rng.randint(2019, 2026), rng.randint(1, 12), rng.randint(1, 28)
        H, M, S = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
        mon = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()[m - 1]
        return {
            "iso": f"{y}-{m:02d}-{d:02d}T{H:02d}:{M:02d}:{S:02d}Z",
            "datetime": f"{y}-{m:02d}-{d:02d} {H:02d}:{M:02d}:{S:02d}",
            "date": f"{y}-{m:02d}-{d:02d}",
            "syslog": f"{mon} {d:2d} {H:02d}:{M:02d}:{S:02d}",
            "ls": f"{mon} {d:2d} {H:02d}:{M:02d}",
            "time": f"{H:02d}:{M:02d}:{S:02d}",
            "us": f"{m:02d}/{d:02d}/{y}",
            "rfc": f"{['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d % 7]}, {d:02d} {mon} {y} {H:02d}:{M:02d}:{S:02d} GMT",
        }[fmt]

    @staticmethod
    def ago(rng):
        n = rng.randint(1, 59)
        return rng.choice([f"{n} minutes ago", f"{n % 24 + 1} hours ago", f"{n % 30 + 1} days ago",
                           f"{n}s", f"{n}m", f"{n % 24 + 1}h", f"{n % 30 + 1}d"])

    @staticmethod
    def token(rng, n=8):
        return "".join(rng.choice(string.ascii_lowercase + string.digits) for _ in range(n))
