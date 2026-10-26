"""`kernprof -l -v script.py` (line_profiler): timer unit, then per function a
small key/value block and a `Line #  Hits  Time ...` table whose source-line
rows leave the timing columns empty."""
from lib import Doc, fake

TOOL = "kernprof"

BODIES = [
    ["@profile", "def {f}({a}):", "    total = 0", "    for i in range({a}):", "        total += i * i", "    return total"],
    ["@profile", "def {f}(self, rows):", "    out = []", "", "    for row in rows:", "        if not row:",
     "            continue", "        out.append(self.parse(row))", "    self.cache.update(out)", "    return out"],
    ["@profile", "def {f}(path):", "    with open(path) as fh:", "        data = json.load(fh)",
     "    df = pd.DataFrame(data[\"items\"])", "    df = df[df.price > 0]", "    # normalise",
     "    df[\"price\"] = df.price / df.price.max()", "    return df.groupby(\"sku\").sum()"],
    ["def {f}(items, key=None):", "    seen = set()", "    for x in items:", "        k = key(x) if key else x",
     "        if k in seen:", "            continue", "        seen.add(k)", "        yield x"],
]
FNAMES = ["compute", "load_rows", "parse_batch", "dedupe", "process", "transform", "score_all", "build_index"]


def generate(rng):
    d = Doc()
    script = rng.choice(["app.py", "bench.py", "profile_me.py", f"{fake.word(rng)}.py"])
    if rng.random() < .7:
        d.skip(f"Wrote profile results to {script}.lprof")
    unit = rng.choice(["1e-06 s", "1e-06 s", "1e-09 s", "1e-07 s"])
    d.kv("Timer unit", unit)
    d.blank()
    for _ in range(rng.randint(1, 3)):
        body = rng.choice(BODIES)
        fn = rng.choice(FNAMES)
        start = rng.randint(1, 300)
        total = rng.uniform(.0001, 40)
        d.kv("Total time", f"{total:.6g} s" if rng.random() < .5 else f"{total:.5f} s")
        d.kv("File", rng.choice([script, f"/home/{fake.user(rng)}/src/{script}", f"src/{fake.word(rng)}/{script}"]))
        d.line(f"Function: {fn} at line {start}", "kv", ["Function", f"{fn} at line {start}"])
        d.blank()
        head = ["Line #", "Hits", "Time", "Per Hit", "% Time", "Line Contents"]
        hl = "%6s %9s %12s %8s %8s  %-s" % tuple(head)
        d.line(hl, "header", head)
        d.skip("=" * len(hl))
        for j, src in enumerate(body):
            src = src.format(f=fn, a=rng.choice(["n", "count", "size"]))
            ln = str(start + j)
            timed = src.strip() and not src.lstrip().startswith(("@", "def ", "#"))
            if timed:
                hits = rng.choice([1, 1, rng.randint(2, 500000)])
                t = hits * rng.uniform(.05, 20)
                hs, ts, ph = str(hits), f"{t:.1f}", f"{t / hits:.1f}"
                pct = f"{min(100.0, 100 * t / (total * 1e6)):.1f}" if rng.random() < .9 else "0.0"
                d.line("%6s %9s %12s %8s %8s  %-s" % (ln, hs, ts, ph, pct, src), "row",
                       [ln, hs, ts, ph, pct, src.strip()])
            else:
                text = ("%6s %9s %12s %8s %8s  %-s" % (ln, "", "", "", "", src)).rstrip()
                d.line(text, "row", [ln, None, None, None, None, src.strip() or None])
        d.blank()
        d.blank()
    return d
