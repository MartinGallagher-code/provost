"""FreeBSD `gstat -b` / `gstat -B`: a `dT: ... w: ...` interval line, then a
right-aligned GEOM I/O table whose last column follows a `|`; optional
delete (-d) and other (-o) column groups; sampled once."""
from lib import Doc, fake

TOOL = "gstat"


def _provs(rng):
    disks = rng.sample(["ada0", "ada1", "ada2", "ada3", "da0", "da1", "da2", "nvd0", "nvd1", "nda0", "cd0", "mfid0"],
                       rng.randint(1, 4))
    out = []
    for dk in disks:
        out.append(dk)
        if dk.startswith("cd"):
            continue
        for p in range(1, rng.randint(1, 4)):
            out.append(f"{dk}p{p}")
        if rng.random() < .3:
            out.append(f"gpt/{rng.choice(['boot', 'swap', 'zfs', 'efiboot'])}{rng.randint(0, 3)}")
    if rng.random() < .3:
        out.append(rng.choice(["mirror/gm0", "gptid/" + fake.uuid(rng), "label/data", "diskid/DISK-" + fake.hexid(rng, 10).upper()]))
    if rng.random() < .2:
        out.append(f"{out[0]}p{rng.randint(1, 3)}.eli")
    return out


def generate(rng):
    d = Doc()
    dcol = rng.random() < .35
    ocol = rng.random() < .25
    header = ["L(q)", "ops/s", "r/s", "kBps", "ms/r", "w/s", "kBps", "ms/w"]
    widths = [5, 6, 6, 6, 6, 6, 6, 6]
    if dcol:
        header += ["d/s", "kBps", "ms/d"]
        widths += [6, 6, 6]
    if ocol:
        header += ["o/s", "ms/o"]
        widths += [6, 6]
    header += ["%busy"]
    widths += [7]
    provs = _provs(rng)
    for b in range(1):
        dt = f"{rng.uniform(1.0, 1.02):.3f}s"
        wv = rng.choice(["1.000s", "1.000s", "0.500s", "5.000s"])
        if rng.random() < .2:
            flt = rng.choice(["^a?da?.$", "nvd", "^da[0-9]$", "p2"])
            d.line(f"dT: {dt}  w: {wv}  filter: {flt}", "row", ["dT", dt, "w", wv, "filter", flt])
        else:
            d.line(f"dT: {dt}  w: {wv}", "row", ["dT", dt, "w", wv])
        d.line(" ".join(h.rjust(w) for h, w in zip(header, widths)) + " Name", "header", header + ["Name"])
        busy_disks = set(rng.sample(provs, max(1, len(provs) // 2)))
        for p in provs:
            active = p in busy_disks
            vals = [str(rng.choice([0, 0, 0, 1, 2, 5]) if active else 0)]
            r = rng.randint(0, 900) if active and rng.random() < .6 else 0
            w = rng.randint(0, 1500) if active else 0
            vals += [str(r + w), str(r), str(r * rng.randint(4, 128)), f"{rng.uniform(0.1, 20) if r else 0:.1f}",
                     str(w), str(w * rng.randint(4, 128)), f"{rng.uniform(0.1, 30) if w else 0:.1f}"]
            if dcol:
                dd = rng.randint(0, 50) if active and rng.random() < .3 else 0
                vals += [str(dd), str(dd * rng.randint(4, 4096)), f"{rng.uniform(0.1, 9) if dd else 0:.1f}"]
            if ocol:
                o = rng.randint(0, 30) if active and rng.random() < .3 else 0
                vals += [str(o), f"{rng.uniform(0.1, 9) if o else 0:.1f}"]
            busy = min(100.0, (r + w) / rng.uniform(5, 20)) if (r + w) else 0.0
            vals += [f"{busy:.1f}"]
            text = " ".join(v.rjust(wd) for v, wd in zip(vals, widths)) + "| " + p
            d.line(text, "row", vals + [p])
    return d
