"""btrfs `compsize PATH`: a `Processed N files, ...` summary line, then a
fixed-width table of compression types with a multi-word `Disk Usage`
header; human units by default, raw bytes with -b."""
from lib import Doc, fake

TOOL = "compsize"


def _h(n, raw):
    if raw:
        return str(n)
    for u in "BKMGTPE":
        if n < 1024:
            return f"{n:.1f}{u}" if n < 10 and u != "B" else f"{int(n)}{u}"
        n /= 1024
    return f"{n:.0f}Z"


def generate(rng):
    d = Doc()
    raw = rng.random() < .25
    nfiles = rng.choice([1, rng.randint(2, 50), rng.randint(50, 500000)])
    nreg = max(1, int(nfiles * rng.uniform(0.2, 4)))
    refs = nreg + rng.randint(0, nreg)
    inline = rng.randint(0, nfiles)
    parts = [f"Processed {nfiles} file{'s' if nfiles != 1 else ''}", f"{nreg} regular extents ({refs} refs)", f"{inline} inline."]
    d.line(", ".join(parts), "row", parts)
    types = ["none"] + rng.sample(["zstd", "zlib", "lzo"], rng.choice([0, 1, 1, 2]))
    if rng.random() < .2:
        types.append("prealloc")
    rows = []
    tot_d = tot_u = tot_r = 0
    for t in types:
        u = rng.randint(4096, 2 ** rng.randint(20, 42))
        ratio = 1.0 if t in ("none", "prealloc") else rng.uniform(0.08, 0.9)
        dsk = int(u * ratio)
        ref = int(u * rng.uniform(1.0, 1.3))
        tot_d, tot_u, tot_r = tot_d + dsk, tot_u + u, tot_r + ref
        rows.append((t, dsk, u, ref))
    rows = [("TOTAL", tot_d, tot_u, tot_r)] + rows
    d.line(f"{'Type':<10} {'Perc':<8} {'Disk Usage':<12} {'Uncompressed':<12} {'Referenced':<12}", "header",
           ["Type", "Perc", "Disk Usage", "Uncompressed", "Referenced"])
    for t, dsk, u, ref in rows:
        perc = f"{dsk * 100 / u:3.0f}%"
        vals = [_h(dsk, raw), _h(u, raw), _h(ref, raw)]
        text = f"{t:<10} {perc:<8} " + " ".join(f"{v:>4}".ljust(12) for v in vals)
        d.line(text, "row", [t, perc.strip()] + vals)
    return d
