#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Generate synthetic labelled examples for the layout model.

Random tables and key/value records are printed in the layouts command-line
tools use (aligned columns, pipe and box tables, CSV, key: value blocks,
sectioned tables, wrapped rows, logs, plain lists), with banners, rules and
footers around them. Every label is exact because we made the text.

The corpus (corpus_labels.py) says what real tools look like; this covers the
combinations the corpus is thin on, e.g. values with spaces in aligned
columns, which is where the generic parsers go wrong.

Stdlib only, deterministic for a given --seed. Usage:
    python3 ml/synth.py [-n 4000] [--seed 1] [-o ml/data/synth.jsonl]
"""
import argparse
import json
import os
import random
import string

# --------------------------------------------------------------------------
# values
WORDS = ("alpha beta gamma delta api web db cache worker queue node main dev prod "
         "stage backup nginx redis postgres kafka eth0 wlan0 lo docker0 br0 sda "
         "sdb nvme0n1 root admin www-data alice bob carol daemon systemd cron sshd "
         "active inactive running stopped failed ok warn error enabled disabled "
         "up down yes no true false none auto manual static dynamic").split()
PHRASES = ["Little Endian", "not available", "in use", "Ready to serve", "no such file",
           "up to date", "Not configured", "auto mode", "out of sync", "never",
           "Permission denied", "link up", "full duplex", "read only", "on battery",
           "partially degraded", "waiting for lock", "2 days ago", "about an hour"]
HEADERS = ("NAME ID STATUS STATE TYPE SIZE USED AVAIL USE% MOUNT PID USER CPU MEM "
           "TIME COMMAND PORT PROTO ADDRESS HOST IMAGE CREATED AGE READY RESTARTS "
           "VERSION DEVICE MODEL VENDOR LABEL UUID PATH OWNER GROUP MODE COUNT TOTAL "
           "FREE SHARED RX TX ERRORS DROPPED LATENCY RATE ZONE REGION NODE ROLE "
           "SCORE PRIORITY WEIGHT TARGET SOURCE DEST REASON MESSAGE UPDATED").split()
MULTI_HEADERS = ["Mounted on", "Last seen", "IP address", "Start time", "Exit code",
                 "Disk size", "Free space", "Last sample", "Local Address", "Peer Address",
                 "Full name", "Next run", "Last run", "Block size", "Mem usage"]
KEYS = ("Name Version Status Architecture Maintainer Description Size Uptime "
        "Kernel Hostname Model Serial Firmware Driver Speed Duplex Address Gateway "
        "Netmask Owner Created Modified Checksum Type Mode Path Source Target "
        "Priority Count Total Free Used Available Capacity Temperature Voltage "
        "Health Location Region Zone Image Command Restart Policy Memory CPU").split()
MULTI_KEYS = ["Byte Order", "Model name", "CPU MHz", "Total commands", "Time taken",
              "Last login", "Link detected", "Wake-on", "Supported ports", "Default route",
              "Operating System", "Boot ID", "Machine ID", "Hardware Vendor", "Up since",
              "Requests per second", "Complete requests", "Failed requests"]


def r_int(rng):
    return str(rng.choice([rng.randint(0, 9), rng.randint(0, 999), rng.randint(0, 99999),
                           rng.randint(0, 10 ** 9)]))


def r_value(rng, kind):
    if kind == "int":
        return r_int(rng)
    if kind == "float":
        return f"{rng.uniform(0, 1000):.{rng.choice([1, 2, 3])}f}"
    if kind == "pct":
        return f"{rng.randint(0, 100)}%"
    if kind == "size":
        return f"{rng.choice([rng.randint(1, 999), round(rng.uniform(0.1, 99), 1)])}{rng.choice('KMGT')}" \
            + rng.choice(["", "", "B", "iB"])
    if kind == "sizesp":
        return f"{rng.randint(1, 99999)} {rng.choice(['kB', 'MiB', 'GB', 'bytes'])}"
    if kind == "time":
        return f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
    if kind == "date":
        return f"20{rng.randint(10, 29)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}"
    if kind == "datetime":
        mon = rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())
        return f"{mon} {rng.randint(1, 28)} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}"
    if kind == "ip":
        return ".".join(str(rng.randint(1, 254)) for _ in range(4))
    if kind == "ipport":
        return r_value(rng, "ip") + f":{rng.randint(1, 65535)}"
    if kind == "cidr":
        return r_value(rng, "ip") + f"/{rng.choice([8, 16, 24, 32])}"
    if kind == "mac":
        return ":".join(f"{rng.randint(0, 255):02x}" for _ in range(6))
    if kind == "hex":
        return "0x" + "".join(rng.choice("0123456789abcdef") for _ in range(rng.choice([4, 8])))
    if kind == "uuid":
        h = lambda n: "".join(rng.choice("0123456789abcdef") for _ in range(n))  # noqa: E731
        return f"{h(8)}-{h(4)}-{h(4)}-{h(4)}-{h(12)}"
    if kind == "path":
        return "/" + "/".join(rng.choice(WORDS) for _ in range(rng.randint(1, 4)))
    if kind == "word":
        return rng.choice(WORDS)
    if kind == "ident":
        return rng.choice(WORDS) + rng.choice(["-", "_", "."]) + rng.choice(WORDS + [r_int(rng)])
    if kind == "version":
        return ".".join(str(rng.randint(0, 20)) for _ in range(rng.choice([2, 3]))) \
            + rng.choice(["", "", "-1", "-r2", "~beta"])
    if kind == "phrase":
        return rng.choice(PHRASES)
    if kind == "command":
        return " ".join([rng.choice(["/usr/bin/", "", "./"]) + rng.choice(WORDS)] +
                        [rng.choice(["-v", "--port", str(rng.randint(1, 9000)), rng.choice(WORDS),
                                     "-c", "/etc/" + rng.choice(WORDS) + ".conf"])
                         for _ in range(rng.randint(0, 4))])
    if kind == "freetext":
        return " ".join(rng.choice(WORDS + PHRASES) for _ in range(rng.randint(1, 6)))
    if kind == "dash":
        return rng.choice(["-", "--", "n/a", "<none>", "*"])
    raise ValueError(kind)


ATOMIC = ["int", "int", "float", "pct", "size", "time", "date", "ip", "ipport", "cidr",
          "mac", "hex", "uuid", "path", "word", "word", "ident", "version"]
SPACED = ["phrase", "datetime", "sizesp", "command", "freetext"]


class Doc:
    """Lines plus their labels, built up together so offsets stay exact."""

    def __init__(self):
        self.lines, self.roles, self.starts = [], [], []

    def add(self, line, role, starts=None):
        line = line.rstrip(" ")
        self.lines.append(line)
        self.roles.append("blank" if not line.strip() else role)
        self.starts.append(starts)

    def blank(self, rng, p=1.0):
        if rng.random() < p:
            self.add("", "blank")


def schema(rng, ncols, allow_spaced=True):
    names = rng.sample(HEADERS, ncols)
    kinds = []
    for k in range(ncols):
        if allow_spaced and rng.random() < 0.18:
            kinds.append(rng.choice(SPACED))
        else:
            kinds.append(rng.choice(ATOMIC))
        if rng.random() < 0.12:
            names[k] = rng.choice(MULTI_HEADERS).upper() if rng.random() < 0.5 \
                else rng.choice(MULTI_HEADERS)
    case = rng.choice(["upper", "upper", "title", "lower"])
    names = [n.upper() if case == "upper" else n.title() if case == "title" else n.lower()
             for n in names]
    if len(set(names)) < ncols:
        names = [f"{n}{k}" if names.count(n) > 1 else n for k, n in enumerate(names)]
    return names, kinds


def table(rng, ncols, nrows, allow_spaced=True, dash_p=0.05):
    names, kinds = schema(rng, ncols, allow_spaced)
    if allow_spaced and rng.random() < 0.25:
        kinds[-1] = rng.choice(["command", "phrase", "freetext"])
    rows = [[r_value(rng, "dash") if rng.random() < dash_p else r_value(rng, k) for k in kinds]
            for _ in range(nrows)]
    return names, kinds, rows


def numeric(kind):
    return kind in ("int", "float", "pct", "size", "sizesp")


# --------------------------------------------------------------------------
# layouts
def aligned_line(cells, widths, gaps, right):
    """Cells laid out on fixed column positions; a cell wider than its column
    pushes the rest right with one space (as ps, netstat and /proc do)."""
    line, starts, col = "", [], 0
    for k, c in enumerate(cells):
        w = widths[k]
        floor = len(line) + 1 if line else 0
        start = max(col + w - len(c), floor) if right[k] else max(col, floor)
        line += " " * (start - len(line))
        starts.append(len(line))
        line += c
        col += w + gaps[k]
    return line, starts


def emit_aligned(rng, doc, names, kinds, rows, header=True, rule=None, indent=0, wrap=False,
                 ragged=None):
    widths = [max(len(names[k]) if header else 0, *(len(r[k]) for r in rows)) for k in range(len(names))]
    if ragged if ragged is not None else rng.random() < 0.2:
        # columns sized for the typical cell, not the longest: long cells overflow
        widths = [max(len(names[k]) if header else 1,
                      sorted(len(r[k]) for r in rows)[len(rows) // 2]) for k in range(len(names))]
    gaps = [rng.choice([1, 2, 2, 3, 4]) for _ in names] if rng.random() < 0.5 \
        else [rng.choice([1, 2, 3])] * len(names)
    right = [numeric(k) and rng.random() < 0.6 for k in kinds]
    pre = " " * indent
    if header:
        hl, hs = aligned_line(names, widths, gaps, [False] * len(names))
        doc.add(pre + hl, "header", [s + indent for s in hs])
        if rule == "dashes":
            parts = ["-" * w for w in widths]
            doc.add(pre + "".join(p + " " * gaps[k] for k, p in enumerate(parts)).rstrip(), "skip")
        elif rule == "full":
            doc.add(pre + rng.choice("-=") * len(hl.rstrip()), "skip")
    last_start = sum(widths[:-1]) + sum(gaps[:-1])
    for r in rows:
        cells = list(r)
        tail = None
        if wrap and len(names) > 1 and rng.random() < 0.3:
            extra = " ".join(rng.choice(WORDS) for _ in range(rng.randint(3, 8)))
            tail = extra
        ln, st = aligned_line(cells, widths, gaps, right)
        doc.add(pre + ln, "row", [s + indent for s in st])
        if tail:
            doc.add(" " * (indent + last_start) + tail, "cont", [indent + last_start])


def emit_pipe(rng, doc, names, rows, outer=True, md=False):
    widths = [max(len(names[k]), *(len(r[k]) for r in rows)) for k in range(len(names))]

    def line(cells):
        s, st = ("| " if outer else ""), []
        for k, c in enumerate(cells):
            st.append(len(s))
            s += c.ljust(widths[k])
            s += " | " if k + 1 < len(cells) else (" |" if outer else "")
        return s, st
    hl, hs = line(names)
    doc.add(hl, "header", hs)
    sep = "|" if outer else ""
    if md:
        doc.add(sep + "|".join("-" * (w + 2) for w in widths) + sep, "skip")
    else:
        doc.add(("+" if outer else "") + "+".join("-" * (w + 2) for w in widths) + ("+" if outer else ""), "skip")
    for r in rows:
        ln, st = line(r)
        doc.add(ln, "row", st)


def emit_box(rng, doc, names, rows, unicode=True):
    widths = [max(len(names[k]), *(len(r[k]) for r in rows)) for k in range(len(names))]
    V, H = ("│", "─") if unicode else ("|", "-")
    corners = ("┌┬┐", "├┼┤", "└┴┘") if unicode else ("+++",) * 3

    def rule(c):
        return c[0] + c[1].join(H * (w + 2) for w in widths) + c[2]

    def line(cells):
        s, st = V + " ", []
        for k, c in enumerate(cells):
            st.append(len(s))
            s += c.ljust(widths[k]) + " " + V + (" " if k + 1 < len(cells) else "")
        return s, st
    doc.add(rule(corners[0]), "skip")
    hl, hs = line(names)
    doc.add(hl, "header", hs)
    doc.add(rule(corners[1]), "skip")
    for r in rows:
        ln, st = line(r)
        doc.add(ln, "row", st)
    doc.add(rule(corners[2]), "skip")


def emit_delimited(rng, doc, names, rows, delim, header=True):
    def line(cells):
        s, st = "", []
        for k, c in enumerate(cells):
            if delim in c or (delim == "," and rng.random() < 0.05):
                c = '"' + c + '"'
            st.append(len(s) + (1 if c.startswith('"') else 0))
            s += c
            if k + 1 < len(cells):
                s += delim
        return s, st
    if header:
        hl, hs = line(names)
        doc.add(hl, "header", hs)
    for r in rows:
        ln, st = line(r)
        doc.add(ln, "row", st)


def emit_kv(rng, doc, n, sep=None, align=None, indent=0, keys=None):
    sep = sep or rng.choice([": ", ":", " = ", "=", ":\t", "  "])
    align = rng.random() < 0.6 if align is None else align
    keys = keys or [rng.choice(MULTI_KEYS) if rng.random() < 0.3 else rng.choice(KEYS)
                    for _ in range(n)]
    seen, uniq = set(), []
    for k in keys:
        if k not in seen:
            seen.add(k)
            uniq.append(k)
    keys = uniq
    width = max(len(k) for k in keys)
    dots = sep == "  " and rng.random() < 0.3
    for k in keys:
        v = r_value(rng, rng.choice(ATOMIC + SPACED + ["phrase"]))
        pre = " " * indent
        if dots:
            line = pre + k + " " + "." * (width - len(k) + 3) + " "
        elif sep.strip():
            line = pre + k + sep.rstrip()
            line += " " * ((width - len(k) + 1) if align else 0) + (" " if sep.endswith(" ") or align else "")
            if sep.endswith("\t"):
                line = pre + k + sep
        else:
            line = pre + k + " " * max(2, width - len(k) + 2)
        doc.add(line + v, "kv", [indent, len(line)])


def banner(rng):
    return rng.choice([
        lambda: f"{rng.choice(WORDS).title()} {r_value(rng, 'version')} report generated {r_value(rng, 'date')}",
        lambda: f"==> {r_value(rng, 'path')} <==",
        lambda: "Listing... Done",
        lambda: f"Last login: {r_value(rng, 'datetime')} from {r_value(rng, 'ip')}",
        lambda: f"Showing {rng.randint(1, 99)} of {rng.randint(100, 999)} results",
        lambda: "WARNING: " + rng.choice(PHRASES).lower() + ", output may be incomplete",
        lambda: f"$ {rng.choice(WORDS)} {rng.choice(['list', 'status', 'show', 'ls'])}",
    ])()


def footer(rng):
    return rng.choice([
        lambda: f"Total: {r_int(rng)}",
        lambda: f"{rng.randint(1, 99)} rows in set ({rng.uniform(0, 2):.2f} sec)",
        lambda: f"({rng.randint(1, 99)} rows)",
        lambda: f"{rng.randint(1, 99)} packages can be upgraded.",
        lambda: "Done.",
        lambda: f"Use '{rng.choice(WORDS)} --help' for more information.",
    ])()


def section_title(rng):
    name = rng.choice([rng.choice(WORDS), r_value(rng, "ident"), rng.choice(PHRASES)])
    return rng.choice([f"== {name} ==", f"{name}:", f"[{name}]", f"--- {name} ---",
                       f"{name.upper()}", f"Section: {name}" if rng.random() < 0.2 else f"# {name}"])


# --------------------------------------------------------------------------
# documents
def d_aligned(rng, doc):
    names, kinds, rows = table(rng, rng.randint(2, 9), rng.randint(1, 20))
    emit_aligned(rng, doc, names, kinds, rows, header=rng.random() < 0.9,
                 rule=rng.choice([None, None, "dashes", "full"]), indent=rng.choice([0, 0, 0, 1, 2]))


def d_headerless(rng, doc):
    names, kinds, rows = table(rng, rng.randint(2, 7), rng.randint(2, 15), allow_spaced=False)
    emit_aligned(rng, doc, names, kinds, rows, header=False)


def d_wrapped(rng, doc):
    names, kinds, rows = table(rng, rng.randint(3, 6), rng.randint(3, 12))
    emit_aligned(rng, doc, names, kinds, rows, wrap=True)


def d_pipe(rng, doc):
    names, kinds, rows = table(rng, rng.randint(2, 7), rng.randint(1, 12))
    emit_pipe(rng, doc, names, rows, outer=rng.random() < 0.7, md=rng.random() < 0.5)


def d_box(rng, doc):
    names, kinds, rows = table(rng, rng.randint(2, 6), rng.randint(1, 10))
    emit_box(rng, doc, names, rows, unicode=rng.random() < 0.6)


def d_delim(rng, doc):
    names, kinds, rows = table(rng, rng.randint(2, 8), rng.randint(1, 15))
    emit_delimited(rng, doc, names, rows, rng.choice([",", ",", ";", "\t", "|"]),
                   header=rng.random() < 0.85)


def d_kv(rng, doc):
    emit_kv(rng, doc, rng.randint(2, 18), indent=rng.choice([0, 0, 2, 4]))


def d_blocks(rng, doc):
    keys = [rng.choice(MULTI_KEYS) if rng.random() < 0.3 else rng.choice(KEYS)
            for _ in range(rng.randint(2, 7))]
    sep, align, titled = rng.choice([": ", " = ", ":"]), rng.random() < 0.5, rng.random() < 0.5
    for b in range(rng.randint(2, 5)):
        if titled:
            doc.add(section_title(rng), "section")
        emit_kv(rng, doc, len(keys), sep=sep, align=align, indent=2 if titled and rng.random() < 0.5 else 0,
                keys=keys)
        doc.blank(rng)


def d_sections(rng, doc):
    ncols = rng.randint(2, 6)
    names, kinds = schema(rng, ncols)
    for s in range(rng.randint(2, 4)):
        doc.add(section_title(rng), "section")
        rows = [[r_value(rng, k) for k in kinds] for _ in range(rng.randint(1, 6))]
        emit_aligned(rng, doc, names, kinds, rows, header=rng.random() < 0.8)
        doc.blank(rng, 0.8)


def d_kv_then_table(rng, doc):
    emit_kv(rng, doc, rng.randint(2, 6))
    doc.blank(rng)
    names, kinds, rows = table(rng, rng.randint(2, 6), rng.randint(2, 10))
    emit_aligned(rng, doc, names, kinds, rows, rule=rng.choice([None, "dashes"]))


def d_list(rng, doc):
    kind = rng.choice(["path", "ident", "ip", "cidr", "word", "version", "uuid"])
    indent = rng.choice([0, 0, 2, 4])
    bullet = rng.choice(["", "", "- ", "* ", "  "])
    for _ in range(rng.randint(2, 20)):
        doc.add(" " * indent + bullet + r_value(rng, kind), "row", [indent + len(bullet)])


def d_inline_kv(rng, doc):
    """`name: k=v k2="v 2", ...` lines: the fields are the values (and the
    leading name), as the corpus goldens for blkid / ovs-ofctl have them."""
    keys = rng.sample(KEYS, rng.randint(2, 6))
    keys = [k.lower() if rng.random() < 0.5 else k.upper() for k in keys]
    named, quote, sep = rng.random() < 0.5, rng.random() < 0.4, rng.choice([" ", ", ", " "])
    for _ in range(rng.randint(2, 12)):
        line, st = "", []
        if named:
            st.append(0)
            line = r_value(rng, rng.choice(["path", "ident", "word"])) + ": "
        for n, k in enumerate(keys):
            if rng.random() < 0.15:
                continue
            v = r_value(rng, rng.choice(ATOMIC + (["phrase"] if quote else [])))
            if line and not line.endswith(": "):
                line += sep
            line += k + "="
            if quote:
                line += '"'
            st.append(len(line))
            line += v + ('"' if quote else "")
        doc.add(line, "row", st)


def d_log(rng, doc):
    style = rng.choice(["iso", "bracket", "syslog", "prefix"])
    for _ in range(rng.randint(3, 15)):
        msg = " ".join(rng.choice(WORDS + PHRASES) for _ in range(rng.randint(2, 7)))
        lvl = rng.choice(["INFO", "WARN", "ERROR", "DEBUG"])
        if style == "iso":
            ts = r_value(rng, "date") + " " + r_value(rng, "time")
            line = f"{ts} {lvl} {msg}"
            doc.add(line, "row", [0, len(ts) + 1, len(ts) + len(lvl) + 2])
        elif style == "bracket":
            tag = rng.choice(WORDS)
            line = f"[{tag}] {msg}"
            doc.add(line, "row", [1, len(tag) + 3])
        elif style == "prefix":
            ts, comp = r_value(rng, "time"), rng.choice(WORDS).title() + rng.choice(["", "Caller", "Engine"])
            head = f"{lvl:<5} {ts} "
            doc.add(f"{head}{comp} - {msg}", "row", [0, len(lvl) + 1 + (5 - len(lvl) if len(lvl) < 5 else 0),
                                                     len(head), len(head) + len(comp) + 3])
        else:
            ts, host, prog = r_value(rng, "datetime") + ":" + f"{rng.randint(0, 59):02d}", \
                rng.choice(WORDS), rng.choice(WORDS)
            head = f"{ts} {host} {prog}[{rng.randint(1, 99999)}]: "
            doc.add(head + msg, "row", [0, len(ts) + 1, len(ts) + len(host) + 2, len(head)])


DOCS = [(d_aligned, 26), (d_headerless, 6), (d_wrapped, 6), (d_pipe, 7), (d_box, 6),
        (d_delim, 8), (d_kv, 12), (d_blocks, 8), (d_sections, 7), (d_kv_then_table, 5),
        (d_list, 4), (d_log, 6), (d_inline_kv, 4)]


def example(rng, k):
    fn = rng.choices([d for d, _ in DOCS], weights=[w for _, w in DOCS])[0]
    doc = Doc()
    if rng.random() < 0.3:
        doc.add(banner(rng), "skip")
        doc.blank(rng, 0.6)
    fn(rng, doc)
    if rng.random() < 0.25:
        doc.blank(rng, 0.5)
        doc.add(footer(rng), "skip")
    while doc.lines and not doc.lines[-1].strip():
        for a in (doc.lines, doc.roles, doc.starts):
            a.pop()
    return {"name": f"synth-{k:05d}", "source": "synth", "style": fn.__name__[2:],
            "lines": doc.lines, "roles": doc.roles, "starts": doc.starts}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("-n", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("-o", "--out", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "data", "synth.jsonl"))
    a = ap.parse_args(argv)
    rng = random.Random(a.seed)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        for k in range(a.n):
            fh.write(json.dumps(example(rng, k), ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
