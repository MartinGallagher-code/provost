"""`gcovr` text report: a dashed banner with the report title and Directory,
then a File/Lines/Exec/Cover/Missing table (or Branches/Taken with -b), long
file names wrapped onto their own line, and a TOTAL row."""
from lib import Doc, fake

TOOL = "gcovr"

DIRS = ["src", "lib", "src/core", "src/net", "include", "tests", "src/util", "third_party/zlib", "app"]
STEMS = ["main", "util", "parser", "config", "buffer", "socket", "hash", "log", "thread_pool",
         "string_view", "allocator", "json_reader", "http_client", "crc32", "inflate", "cli"]


def missing(rng, n):
    if n == 0 or rng.random() < .15:
        return None
    out, line = [], rng.randint(1, 20)
    for _ in range(rng.randint(1, 7)):
        if rng.random() < .4:
            span = rng.randint(1, 12)
            out.append(f"{line}-{line + span}")
            line += span
        else:
            out.append(str(line))
        line += rng.randint(2, 40)
    return ",".join(out)


def generate(rng):
    d = Doc()
    rule = "-" * 78
    branches = rng.random() < .3
    root = rng.choice(["/home/user/project", "/builds/ci/libfoo", "/src", "/github/workspace", "..", "."])
    d.skip(rule)
    d.skip("GCC Code Coverage Report".center(78).rstrip())
    d.kv("Directory", root)
    d.skip(rule)
    c1, c2 = ("Branches", "Taken") if branches else ("Lines", "Exec")
    d.line("File".ljust(40) + c1.rjust(8) + c2.rjust(8) + "Cover".rjust(6) + "   Missing",
           "header", ["File", c1, c2, "Cover", "Missing"])
    d.skip(rule)
    tot_n = tot_x = 0
    ext = rng.choice([".c", ".cpp", ".cc"])
    for _ in range(rng.randint(2, 14)):
        name = f"{rng.choice(DIRS)}/{rng.choice(STEMS)}{rng.choice([ext, ext, '.h', '.hpp'])}"
        if rng.random() < .12:
            name = f"{rng.choice(DIRS)}/{rng.choice(STEMS)}/{rng.choice(STEMS)}_{rng.choice(STEMS)}_impl{ext}"
        n = rng.randint(0, 900)
        x = rng.randint(0, n) if rng.random() < .8 else n
        cover = "--" if n == 0 else f"{100 * x // n}%"
        miss = missing(rng, n - x)
        tot_n, tot_x = tot_n + n, tot_x + x
        stats = str(n).rjust(8) + str(x).rjust(8) + cover.rjust(6) + ("   " + miss if miss else "")
        if len(name) > 40:
            # gcovr puts an over-long name on its own line and the numbers below it
            d.line(name, "row", [name, None, None, None, None])
            d.line(" " * 40 + stats, "cont", [str(n), str(x), cover] + ([miss] if miss else []))
        else:
            d.line(name.ljust(40) + stats, "row", [name, str(n), str(x), cover, miss])
    d.skip(rule)
    cover = "--" if tot_n == 0 else f"{100 * tot_x // tot_n}%"
    d.line("TOTAL".ljust(40) + str(tot_n).rjust(8) + str(tot_x).rjust(8) + cover.rjust(6), "row",
           ["TOTAL", str(tot_n), str(tot_x), cover, None])
    d.skip(rule)
    if rng.random() < .35:  # --print-summary
        pct = f"{100 * tot_x / tot_n:.1f}%" if tot_n else "0.0%"
        d.kv("lines" if not branches else "branches", f"{pct} ({tot_x} out of {tot_n})")
        if not branches and rng.random() < .6:
            b = rng.randint(0, 400)
            bx = rng.randint(0, b)
            d.kv("functions", f"{fake.flt(rng, 30, 100, 1)}% ({rng.randint(1, 90)} out of {rng.randint(90, 120)})")
            d.kv("branches", f"{100 * bx / b:.1f}% ({bx} out of {b})" if b else "0.0% (0 out of 0)")
    return d
