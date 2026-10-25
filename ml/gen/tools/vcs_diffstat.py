"""`diffstat` on a patch: ` path | N +++---` per file (histogram is
decoration), binary entries, and the `N files changed, ...` summary."""
from lib import Doc, fake

TOOL = "diffstat"


def generate(rng):
    d = Doc()
    width = rng.choice([80, 80, 72, 100])
    files = []
    for _ in range(rng.randint(1, 15)):
        p = rng.choice(["", "src/", "lib/", "doc/", "tests/", "include/linux/", "a/b/c/"]) + \
            rng.choice([fake.word(rng), fake.name(rng, "_")]) + rng.choice([".c", ".h", ".py", ".md", "", ".png", ".rs"])
        if p.endswith(".png") and rng.random() < .7:
            files.append((p, None, None))
            continue
        ins = rng.choice([0, rng.randint(0, 9), rng.randint(0, 200)])
        dele = rng.choice([0, rng.randint(0, 9), rng.randint(0, 120)])
        if ins + dele == 0:
            ins = 1
        files.append((p, ins, dele))
    pw = max(len(p) for p, _, _ in files)
    nw = max(len(str((i or 0) + (x or 0))) for _, i, x in files)
    nw = max(nw, rng.choice([1, 3, 5]))
    room = width - pw - nw - 6
    mx = max((i or 0) + (x or 0) for _, i, x in files) or 1
    for p, i, x in files:
        if i is None:
            d.line(f" {p.ljust(pw)} | binary", "row", [p, "binary"])
            continue
        tot = i + x
        scale = min(1.0, room / mx)
        bar = "+" * int(round(i * scale)) + "-" * int(round(x * scale))
        n = str(tot)
        d.line(f" {p.ljust(pw)} | {n.rjust(nw)} {bar}".rstrip(), "row", [p, n])
    ti = sum(i or 0 for _, i, _ in files)
    tx = sum(x or 0 for _, _, x in files)
    nf = len(files)
    parts = [f"{nf} file{'s' if nf != 1 else ''} changed"]
    if ti or rng.random() < .3:
        parts.append(f"{ti} insertion{'s' if ti != 1 else ''}(+)")
    if tx or rng.random() < .3:
        parts.append(f"{tx} deletion{'s' if tx != 1 else ''}(-)")
    if rng.random() < .1:
        m = rng.randint(1, nf)
        parts.append(f"{m} modification{'s' if m != 1 else ''}(!)")
    d.line(" " + ", ".join(parts), "row", parts)
    return d
