"""`lcov --list` / `lcov --summary`: either a pipe-separated table with a
grouped two-line header (Lines / Functions / Branches, each Rate + Num),
[directory] section lines and a Total: row, or the dot-leader summary block."""
from lib import Doc

TOOL = "lcov"

DIRS = ["src/", "src/core/", "src/net/", "lib/", "include/", "tests/", "src/util/", "vendor/cjson/"]
STEMS = ["main", "util", "parser", "config", "buffer", "socket", "hash", "log", "pool", "queue",
         "strbuf", "list", "json", "http", "timer", "event_loop", "cli_args", "crc32"]


def rate(rng, n, hit):
    if n == 0:
        return "-"
    p = 100 * hit / n
    return "100%" if hit == n else (f"{p:.1f}%" if p >= 10 else f"{p:.2f}%" if rng.random() < .3 else f"{p:.1f}%")


def generate(rng):
    d = Doc()
    info = rng.choice(["coverage.info", "lcov.info", "build/coverage.info", "app.info", "total.info"])
    d.skip(f"Reading tracefile {info}")
    if rng.random() < .4:
        d.section("Summary coverage rate:")
        ln = rng.randint(50, 20000)
        lh = rng.randint(0, ln)
        fn = rng.randint(5, 900)
        fh = rng.randint(0, fn)
        if rng.random() < .4:  # lcov 2.x
            d.kv("source files", str(rng.randint(1, 300)), indent="  ")
        d.line(f"  lines......: {100 * lh / ln:.1f}% ({lh} of {ln} lines)", "kv",
               ["lines", f"{100 * lh / ln:.1f}% ({lh} of {ln} lines)"])
        d.line(f"  functions..: {100 * fh / fn:.1f}% ({fh} of {fn} functions)", "kv",
               ["functions", f"{100 * fh / fn:.1f}% ({fh} of {fn} functions)"])
        if rng.random() < .5:
            d.line("  branches...: no data found", "kv", ["branches", "no data found"])
        else:
            bn = rng.randint(10, 5000)
            bh = rng.randint(0, bn)
            d.line(f"  branches...: {100 * bh / bn:.1f}% ({bh} of {bn} branches)", "kv",
                   ["branches", f"{100 * bh / bn:.1f}% ({bh} of {bn} branches)"])
        return d

    files = {}
    for _ in range(rng.randint(2, 16)):
        dr = rng.choice(DIRS)
        files.setdefault(dr, set()).add(rng.choice(STEMS) + rng.choice([".c", ".c", ".h", ".cpp"]))
    has_br = rng.random() < .5
    rows = []
    for dr in sorted(files):
        for f in sorted(files[dr]):
            ln = rng.randint(0, 800)
            lh = rng.randint(0, ln)
            fn = rng.randint(0, 40) if ln else 0
            fh = rng.randint(0, fn)
            bn = rng.randint(0, 200) if has_br and ln else 0
            bh = rng.randint(0, bn)
            rows.append((dr, f, ln, lh, fn, fh, bn, bh))
    nw = max([len(r[1]) for r in rows] + [len("Filename")]) + rng.randint(0, 12)

    def stats(ln, lh, fn, fh, bn, bh):
        vals = [rate(rng, ln, lh), str(ln), rate(rng, fn, fh), str(fn), rate(rng, bn, bh), str(bn)]
        text = (vals[0].rjust(5) + vals[1].rjust(7) + "|" + vals[2].rjust(5) + vals[3].rjust(6)
                + "|" + vals[4].rjust(5) + vals[5].rjust(7))
        return text, vals

    d.line(" " * nw + "|Lines       |Functions  |Branches    ", "header", ["Lines", "Functions", "Branches"])
    d.line("Filename".ljust(nw) + "|Rate     Num|Rate    Num|Rate     Num", "header",
           ["Filename", "Rate", "Num", "Rate", "Num", "Rate", "Num"])
    d.skip("=" * (nw + 37))
    cur = None
    root = rng.choice(["/home/user/project/", "/builds/ci/app/", "/src/", "/github/workspace/", ""])
    for dr, f, ln, lh, fn, fh, bn, bh in rows:
        if dr != cur:
            cur = dr
            d.section(f"[{root}{dr}]")
        text, vals = stats(ln, lh, fn, fh, bn, bh)
        d.line(f.ljust(nw) + "|" + text, "row", [f] + vals)
    d.skip("=" * (nw + 37))
    tl = sum(r[2] for r in rows)
    th = sum(r[3] for r in rows)
    tf = sum(r[4] for r in rows)
    tfh = sum(r[5] for r in rows)
    tb = sum(r[6] for r in rows)
    tbh = sum(r[7] for r in rows)
    text, vals = stats(tl, th, tf, tfh, tb, tbh)
    d.line("Total:".rjust(nw) + "|" + text, "row", ["Total"] + vals)
    return d
