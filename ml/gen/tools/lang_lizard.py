"""`lizard src/` (cyclomatic complexity analyser): a function table, a
per-file table, a warnings block (or the no-thresholds line) and a total
summary table, each between `====` / `----` rules."""
from lib import Doc, fake

TOOL = "lizard"

FUNCS = ["parse", "main", "Lexer::next", "Parser::parse_expr", "handle_request", "__init__", "run", "encode",
         "decode_frame", "Store::get", "validate", "compute_hash", "anonymous", "(anonymous)", "render",
         "build_index", "Config::load", "tokenize", "apply_patch", "on_message"]


def generate(rng):
    d = Doc()
    langs = rng.choice([[".py"], [".c", ".h"], [".cpp", ".hpp"], [".js"], [".go"], [".java"], [".py", ".js"]])
    files = []
    for _ in range(rng.randint(1, 7)):
        fn = rng.choice(["src", "lib", "pkg/" + fake.word(rng), "app", "internal/" + fake.word(rng)]) + "/" + \
            rng.choice([fake.word(rng), fake.name(rng, "_")]) + rng.choice(langs)
        funcs = []
        line = rng.randint(1, 30)
        for _ in range(rng.randint(0, 8)):
            nloc = rng.choice([rng.randint(1, 20), rng.randint(1, 80), rng.randint(50, 300)])
            ccn = max(1, min(nloc, rng.choice([1, 1, 2, 3, rng.randint(1, 12), rng.randint(10, 40)])))
            length = nloc + rng.randint(0, nloc // 3 + 1)
            funcs.append([nloc, ccn, nloc * rng.randint(4, 12), rng.randint(0, 6), length,
                          f"{rng.choice(FUNCS)}@{line}-{line + length - 1}@{fn}"])
            line += length + rng.randint(1, 20)
        files.append((fn, funcs))
    allf = [f for _, fs in files for f in fs]
    fhead = "  NLOC    CCN   token  PARAM  length  location  "
    fcells = ["NLOC", "CCN", "token", "PARAM", "length", "location"]

    def ftable(rows):
        d.skip("=" * 48)
        d.line(fhead, "header", fcells)
        d.skip("-" * 48)
        for r in rows:
            d.line("%8d%7d%8d%7d%8d %s" % tuple(r), "row", [str(x) for x in r])

    ftable(allf)
    d.skip(f"{len(files)} file analyzed.")
    d.skip("=" * 62)
    d.line("NLOC    Avg.NLOC  AvgCCN  Avg.Token  function_cnt    file", "header",
           ["NLOC", "Avg.NLOC", "AvgCCN", "Avg.Token", "function_cnt", "file"])
    d.skip("-" * 62)
    for fn, fs in files:
        n = len(fs)
        tot = sum(f[0] for f in fs) + rng.randint(0, 40)
        avg = lambda i: (sum(f[i] for f in fs) / n) if n else 0.0  # noqa: E731
        vals = (tot, avg(0), avg(1), avg(2), n, fn)
        text = "%7d%10.1f%8.1f%10.1f%10d     %s" % vals
        d.line(text, "row", [str(tot), f"{vals[1]:.1f}", f"{vals[2]:.1f}", f"{vals[3]:.1f}", str(n), fn])
    d.blank()
    cond = "cyclomatic_complexity > 15 or length > 1000 or nloc > 1000000 or parameter_count > 100"
    warn = [f for f in allf if f[1] > 15]
    if warn:
        d.skip("=" * 102)
        d.section(f"!!!! Warnings ({cond}) !!!!", f"Warnings ({cond})")
        ftable(warn)
    else:
        d.skip(f"No thresholds exceeded ({cond})")
    d.skip("=" * 90)
    head = ["Total nloc", "Avg.NLOC", "AvgCCN", "Avg.token", "Fun Cnt", "Warning cnt", "Fun Rt", "nloc Rt"]
    d.line("Total nloc   Avg.NLOC  AvgCCN  Avg.token   Fun Cnt  Warning cnt   Fun Rt   nloc Rt", "header", head)
    d.skip("-" * 90)
    n = len(allf) or 1
    tot = sum(f[0] for f in allf) + rng.randint(0, 200)
    vals = (tot, sum(f[0] for f in allf) / n, sum(f[1] for f in allf) / n, sum(f[2] for f in allf) / n,
            len(allf), len(warn), len(warn) / n, (sum(f[0] for f in warn) / tot) if tot else 0.0)
    text = "%10d%11.1f%9.1f%10.1f%10d%13d%10.2f%8.2f" % vals
    cells = [str(vals[0]), f"{vals[1]:.1f}", f"{vals[2]:.1f}", f"{vals[3]:.1f}", str(vals[4]), str(vals[5]),
             f"{vals[6]:.2f}", f"{vals[7]:.2f}"]
    d.line(text, "row", cells)
    return d
