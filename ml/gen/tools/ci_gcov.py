"""`gcov [-b] [-f] files...`: per-source blocks headed `File 'src/x.c'` (and
`Function 'name'` with -f), `Lines executed:85.71% of 14` style key/values,
`No branches` / `Creating 'x.c.gcov'` notes, missing-.gcda warnings and the
overall Lines executed total when several files are given."""
from lib import Doc

TOOL = "gcov"

SRCS = ["main.c", "util.c", "parser.c", "lexer.c", "hash.c", "buffer.c", "net/socket.c", "io/file.c",
        "list.cpp", "json.cpp", "config.cc", "crc32.c", "event.c", "timer.c", "alloc.c"]
FUNCS = ["main", "parse_args", "hash_insert", "hash_lookup", "buf_append", "buf_free", "lex_next", "json_parse",
         "sock_connect", "read_file", "crc32_update", "timer_fire", "_GLOBAL__sub_I_main", "Config::load(std::string const&)"]
HEADERS = ["/usr/include/stdio.h", "/usr/include/c++/12/bits/basic_string.h", "/usr/include/c++/12/iostream",
           "src/util.h", "include/hash.h", "/usr/include/x86_64-linux-gnu/bits/stdio2.h"]


def pct(hit, n):
    return f"{100 * hit / n:.2f}%"


def block(rng, d, kind, name, branches, gcov_file=None):
    d.section(f"{kind} '{name}'", f"'{name}'")
    n = rng.randint(1, 900)
    hit = n if rng.random() < .2 else rng.randint(0, n)
    d.line(f"Lines executed:{pct(hit, n)} of {n}", "kv", ["Lines executed", f"{pct(hit, n)} of {n}"])
    if branches:
        if rng.random() < .2:
            d.skip("No branches")
        else:
            b = rng.randint(2, 400) // 2 * 2
            bx = rng.randint(0, b)
            bt = rng.randint(0, bx)
            d.line(f"Branches executed:{pct(bx, b)} of {b}", "kv", ["Branches executed", f"{pct(bx, b)} of {b}"])
            d.line(f"Taken at least once:{pct(bt, b)} of {b}", "kv", ["Taken at least once", f"{pct(bt, b)} of {b}"])
        if rng.random() < .2:
            d.skip("No calls")
        else:
            c = rng.randint(1, 300)
            cx = rng.randint(0, c)
            d.line(f"Calls executed:{pct(cx, c)} of {c}", "kv", ["Calls executed", f"{pct(cx, c)} of {c}"])
    if gcov_file:
        d.skip(f"Creating '{gcov_file}'")
    d.blank()
    return n, hit


def generate(rng):
    d = Doc()
    branches = rng.random() < .45
    funcs = rng.random() < .25
    prefix = rng.choice(["", "src/", "../src/", "/home/user/proj/src/"])
    sources = rng.sample(SRCS, rng.randint(1, 5))
    tot_n = tot_h = 0
    seen = set()
    for src in sources:
        path = prefix + src
        if rng.random() < .1:
            obj = rng.choice(["build/", "CMakeFiles/app.dir/", ""]) + src.rsplit(".", 1)[0] + ".gcda"
            d.skip(f"{obj}:cannot open data file, assuming not executed")
        if funcs:
            for fn in rng.sample(FUNCS, rng.randint(1, 4)):
                block(rng, d, "Function", fn, branches)
        n, h = block(rng, d, "File", path, branches, src.split("/")[-1] + ".gcov")
        tot_n, tot_h = tot_n + n, tot_h + h
        for hdr in rng.sample(HEADERS, rng.choice([0, 0, 0, 1, 2])):
            if hdr in seen:
                continue
            seen.add(hdr)
            n, h = block(rng, d, "File", hdr, branches, hdr.split("/")[-1] + ".gcov")
            tot_n, tot_h = tot_n + n, tot_h + h
    if len(sources) > 1 and rng.random() < .7:
        d.line(f"Lines executed:{pct(tot_h, tot_n)} of {tot_n}", "kv", ["Lines executed", f"{pct(tot_h, tot_n)} of {tot_n}"])
    elif d.lines and d.lines[-1] == "":
        d.lines.pop()
        d.labels.pop()
    return d
