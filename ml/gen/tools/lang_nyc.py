"""`nyc report` / `nyc mocha` (istanbul text reporter): a dash-and-pipe
coverage table with indented directories and files, optionally followed by
the text-summary block."""
from lib import Doc, fake

TOOL = "nyc"


def _n(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s


def _pct(rng):
    return rng.choice([100.0, 100.0, 0.0, round(rng.uniform(0, 100), 2), round(rng.uniform(50, 100), 2), 50.0, 87.5])


def _uncov(rng):
    out, ln = [], rng.randint(1, 30)
    for _ in range(rng.randint(1, 6)):
        ln += rng.randint(1, 50)
        if rng.random() < .4:
            e = ln + rng.randint(1, 9)
            out.append(f"{ln}-{e}")
            ln = e
        else:
            out.append(str(ln))
    return ",".join(out)


def generate(rng):
    d = Doc()
    rows = []
    for _ in range(rng.randint(1, 4)):
        dname = rng.choice(["lib", "src", "src/utils", "src/routes", "lib/models", "server", "app/services", "."])
        files = []
        for _ in range(rng.randint(1, 6)):
            files.append((rng.choice([fake.word(rng), fake.name(rng, "_"), "index", fake.word(rng) + "." + fake.word(rng)])
                          + rng.choice([".js", ".js", ".ts", ".mjs", ".jsx"]), [_pct(rng) for _ in range(4)]))
        agg = [round(sum(f[1][i] for f in files) / len(files), 2) for i in range(4)]
        rows.append((" " + dname, agg, None))
        for fn, p in files:
            unc = None if all(x == 100 for x in p) else (_uncov(rng) if rng.random() < .9 else None)
            rows.append(("  " + fn, p, unc))
    allp = [round(sum(r[1][i] for r in rows if r[0].startswith(" ") and not r[0].startswith("  ")) /
                  max(1, sum(1 for r in rows if not r[0].startswith("  "))), 2) for i in range(4)]
    rows.insert(0, ("All files", allp, None))
    head = ["File", "% Stmts", "% Branch", "% Funcs", "% Lines", "Uncovered Line #s"]
    w0 = max(len(head[0]), max(len(r[0]) for r in rows))
    w5 = max(len(head[5]), max(len(r[2] or "") for r in rows))
    ws = [w0] + [len(h) for h in head[1:5]] + [w5]
    rule = "|".join("-" * (w + (1 if i == 0 else 2)) for i, w in enumerate(ws))
    d.skip(rule)
    d.line(head[0].ljust(w0) + " | " + " | ".join(h for h in head[1:5]) + " | " + head[5].ljust(w5) + " ", "header", head)
    d.skip(rule)
    for name, p, unc in rows:
        vals = [_n(x) for x in p]
        text = name.ljust(w0) + " | " + " | ".join(vals[i].rjust(ws[i + 1]) for i in range(4)) + " | " + (unc or "").ljust(w5) + " "
        d.line(text, "row", [name.strip()] + vals + [unc])
    d.skip(rule)
    if rng.random() < .45:
        d.blank()
        d.section("=============================== Coverage summary ===============================")
        for k in ("Statements", "Branches", "Functions", "Lines"):
            tot = rng.randint(0, 3000)
            cov = rng.randint(0, tot)
            pct = "Unknown%" if tot == 0 else f"{_n(round(100 * cov / tot, 2))}%"
            frac = f"( {cov}/{tot} )"
            d.line(f"{k.ljust(12)} : {pct} {frac}", "kv", [k, pct, frac])
        d.skip("=" * 80)
    return d
