"""`lizard` cyclomatic-complexity report: a per-function table, a per-file
table, an optional warnings table, and the multi-word-header totals line."""
from lib import Doc, fake

TOOL = "lizard"

FUNCS = ["main", "parse_args", "Server::handle", "read_config", "lambda", "__init__", "render",
         "Parser::parse_expression", "compute_checksum", "on_message", "validate", "toJSON",
         "worker_loop", "TokenStream::next_token_or_eof"]
EXTS = [".c", ".cpp", ".py", ".js", ".go", ".java", ".rs", ".swift", ".ts"]
LIMIT = "(cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100)"


def generate(rng):
    d = Doc()
    files = []
    for _ in range(rng.randint(1, 5)):
        p = rng.choice(["./", "src/", "./lib/", "pkg/" + fake.word(rng) + "/"]) + fake.word(rng) + rng.choice(EXTS)
        files.append(p)
    hdr = "  NLOC    CCN   token  PARAM  length  location  "
    cols = ["NLOC", "CCN", "token", "PARAM", "length", "location"]
    d.skip("=" * 48)
    d.line(hdr, "header", cols)
    d.skip("-" * 48)
    funcs = []
    for f in files:
        line = 1
        for _ in range(rng.randint(1, 6)):
            nloc = rng.randint(1, 60) if rng.random() < .9 else rng.randint(100, 1300)
            ccn = rng.randint(1, 8) if rng.random() < .85 else rng.randint(16, 40)
            tok = nloc * rng.randint(4, 12)
            par = rng.randint(0, 6)
            length = nloc + rng.randint(0, 20)
            start = line + rng.randint(1, 20)
            line = start + length
            loc = f"{rng.choice(FUNCS)}@{start}-{line}@{f}"
            vals = [str(nloc), str(ccn), str(tok), str(par), str(length)]
            funcs.append((vals, loc, f))
            d.line("".join(v.rjust(8 if i == 0 else 7) for i, v in enumerate(vals)) + " " + loc, "row", vals + [loc])
    d.skip(f"{len(files)} file analyzed.")
    d.skip("=" * 62)
    d.line("NLOC    Avg.NLOC  AvgCCN  Avg.token  function_cnt    file", "header",
           ["NLOC", "Avg.NLOC", "AvgCCN", "Avg.token", "function_cnt", "file"])
    d.skip("-" * 62)
    tn, tc, tt, warn = 0, 0, 0, []
    for f in files:
        fs = [v for v, _, ff in funcs if ff == f]
        n = sum(int(v[0]) for v in fs) + rng.randint(0, 15)
        an = sum(int(v[0]) for v in fs) / len(fs)
        ac = sum(int(v[1]) for v in fs) / len(fs)
        at = sum(int(v[2]) for v in fs) / len(fs)
        tn, tc, tt = tn + n, tc + ac * len(fs), tt + at * len(fs)
        cells = [str(n), f"{an:.1f}", f"{ac:.1f}", f"{at:.1f}", str(len(fs))]
        d.line(f"{cells[0]:>7}{cells[1]:>10}{cells[2]:>8}{cells[3]:>11}{cells[4]:>10}     {f}", "row", cells + [f])
    warn = [(v, loc) for v, loc, _ in funcs if int(v[1]) > 15 or int(v[0]) > 1000]
    d.blank()
    if warn:
        d.skip("=" * 111)
        d.skip(f"!!!! Warnings {LIMIT} !!!!")
        d.skip("=" * 111)
        d.line(hdr, "header", cols)
        d.skip("-" * 48)
        for vals, loc in warn:
            d.line("".join(v.rjust(8 if i == 0 else 7) for i, v in enumerate(vals)) + " " + loc, "row", vals + [loc])
    else:
        d.skip("=" * 111)
        d.skip(f"No thresholds exceeded {LIMIT}")
    nf = len(funcs)
    d.skip("=" * 90)
    d.line("Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt", "header",
           ["Total nloc", "Avg.NLOC", "AvgCCN", "Avg.token", "Fun Cnt", "Warning cnt", "Fun Rt", "nloc Rt"])
    d.skip("-" * 90)
    wn = sum(int(v[0]) for v, _ in warn)
    cells = [str(tn), f"{sum(int(v[0]) for v, _, _ in funcs) / nf:.1f}", f"{tc / nf:.1f}", f"{tt / nf:.1f}",
             str(nf), str(len(warn)), f"{len(warn) / nf:.2f}", f"{wn / max(tn, 1):.2f}"]
    w = [10, 11, 8, 11, 10, 13, 9, 10]
    d.line("".join(c.rjust(w[i]) for i, c in enumerate(cells)), "row", cells)
    return d
