"""Tarsnap `--print-stats` (alone, or after -c/-d) and `--list-archives -v`:
a right-aligned size table with an unnamed first column and two-word headers,
optionally humanized; or tab-separated archive name + timestamp rows."""
from lib import Doc, fake

TOOL = "tarsnap-print-stats"


def _num(n, human):
    if not human:
        return str(n)
    for u in ["B", "kB", "MB", "GB", "TB", "PB"]:
        if n < 1000:
            return f"{n:.1f} {u}" if u != "B" and n < 100 else f"{int(n)} {u}"
        n /= 1000
    return f"{n:.0f} EB"


def _name(rng):
    host = rng.choice([fake.word(rng), fake.host(rng).split(".")[0]])
    what = rng.choice(["home", "etc", "www", "db", "full", "daily", "weekly", fake.word(rng)])
    y, m, dd = rng.randint(2018, 2026), rng.randint(1, 12), rng.randint(1, 28)
    return rng.choice([f"{host}-{what}-{y}{m:02d}{dd:02d}", f"{what}-{y}-{m:02d}-{dd:02d}_{rng.randint(0, 23):02d}-{rng.randint(0, 59):02d}",
                       f"{host}.{what}.{y}{m:02d}{dd:02d}.{rng.randint(0, 235959):06d}"])


def generate(rng):
    d = Doc()
    if rng.random() < .25:
        rows = []
        for _ in range(rng.randint(2, 15)):
            y, m, dd = rng.randint(2018, 2026), rng.randint(1, 12), rng.randint(1, 28)
            ts = f"{y}-{m:02d}-{dd:02d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
            name = _name(rng)
            if rng.random() < .3:
                cmd = f"tarsnap -c -f {name} " + " ".join(fake.path(rng) for _ in range(rng.randint(1, 3)))
                d.line(f"{name}\t{ts}\t{cmd}", "row", [name, ts, cmd])
            else:
                d.line(f"{name}\t{ts}", "row", [name, ts])
        return d
    human = rng.random() < .4
    mode = rng.choice(["stats", "create", "create", "delete"])
    if mode == "create" and rng.random() < .6:
        d.skip("tarsnap: Removing leading '/' from member names")
    total = rng.randint(10 ** 7, 10 ** 13)
    comp = int(total * rng.uniform(0.3, 0.8))
    uniq = int(total * rng.uniform(0.01, 0.3))
    ucomp = int(uniq * rng.uniform(0.3, 0.8))
    rows = [("All archives", total, comp), ("  (unique data)", uniq, ucomp)]
    if mode == "create":
        arch = int(total * rng.uniform(0.001, 0.2))
        new = int(arch * rng.uniform(0, 0.3))
        rows += [("This archive", arch, int(arch * rng.uniform(0.3, 0.8))), ("New data", new, int(new * rng.uniform(0.3, 0.8)))]
    elif mode == "delete":
        arch = int(total * rng.uniform(0.001, 0.2))
        rows += [("This archive", arch, int(arch * rng.uniform(0.3, 0.8))),
                 ("Deleted data", int(arch * 0.1), int(arch * 0.05))]
    w = rng.choice([32, 39, 40])
    vals = [(_num(a, human), _num(b, human)) for _, a, b in rows]
    w1 = max(len("Total size"), max(len(a) for a, _ in vals))
    w2 = max(len("Compressed size"), max(len(b) for _, b in vals))
    d.line(" " * w + "  " + "Total size".rjust(w1) + "  " + "Compressed size".rjust(w2), "header",
           [None, "Total size", "Compressed size"])
    for (label, _, _), (a, b) in zip(rows, vals):
        d.line(label.ljust(w) + "  " + a.rjust(w1) + "  " + b.rjust(w2), "row", [label.strip(), a, b])
    return d
