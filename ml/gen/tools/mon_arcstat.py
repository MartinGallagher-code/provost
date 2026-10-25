"""ZFS `arcstat [-f fields] [interval [count]]`: fixed-width, right-aligned
columns (two-space gap), human-scaled numbers (1.2K, 34M, 3.9G), the header
repeated every N samples."""
from lib import Doc

TOOL = "arcstat"

# name -> (width, kind)
COLS = {"time": (8, "time"), "hits": (4, "n"), "miss": (4, "n"), "read": (4, "n"), "hit%": (4, "p"),
        "miss%": (5, "p"), "dhit": (4, "n"), "dmis": (4, "n"), "dh%": (3, "p"), "dm%": (3, "p"),
        "phit": (4, "n"), "pmis": (4, "n"), "ph%": (3, "p"), "pm%": (3, "p"), "mhit": (4, "n"),
        "mmis": (4, "n"), "mh%": (3, "p"), "mm%": (3, "p"), "arcsz": (5, "b"), "size": (4, "b"),
        "c": (4, "b"), "mfu": (4, "n"), "mru": (4, "n"), "mfug": (4, "n"), "mrug": (4, "n"),
        "eskip": (5, "n"), "mtxmis": (6, "n"), "dread": (5, "n"), "pread": (5, "n"), "l2hits": (6, "n"),
        "l2miss": (6, "n"), "l2read": (6, "n"), "l2hit%": (6, "p"), "l2miss%": (7, "p"), "l2asize": (7, "b"),
        "l2size": (6, "b"), "l2bytes": (7, "b"), "grow": (4, "i"), "need": (4, "b"), "free": (4, "b"),
        "avail": (5, "b"), "waste": (5, "b"), "ddread": (6, "n"), "ddh%": (4, "p"), "dmread": (6, "n"),
        "dmh%": (4, "p"), "pread": (5, "n"), "ph%": (3, "p"), "mfu%": (4, "p"), "mru%": (4, "p")}

SETS = [["time", "read", "miss", "miss%", "dmis", "dm%", "pmis", "pm%", "mmis", "mm%", "arcsz", "c"],
        ["time", "read", "miss", "miss%", "dmis", "dm%", "pmis", "pm%", "mmis", "mm%", "size", "c", "avail"],
        ["time", "read", "ddread", "ddh%", "dmread", "dmh%", "pread", "ph%", "size", "c", "avail"],
        ["time", "hits", "miss", "hit%", "l2hits", "l2miss", "l2hit%", "l2size", "arcsz"]]


def _pretty(v):
    for unit, div in (("T", 1 << 40), ("G", 1 << 30), ("M", 1 << 20), ("K", 1 << 10)):
        if v >= div:
            x = v / div
            return f"{x:.1f}{unit}" if x < 10 else f"{int(x)}{unit}"
    return str(int(v))


def generate(rng):
    d = Doc()
    cols = list(rng.choice(SETS))
    if rng.random() < .35:
        extra = [c for c in COLS if c not in cols and c != "time"]
        cols = ["time"] + rng.sample(extra, rng.randint(3, 9))
    hdr_every = rng.choice([5, 10, 20, 1000])
    n = rng.randint(2, 26)
    arc = rng.uniform(.3, 120) * (1 << 30)
    cmax = arc * rng.uniform(1, 1.3)
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    step = rng.choice([1, 1, 2, 5, 10])
    busy = rng.choice([0, 40, 3000, 3000, 300000, 9000000])

    def render(vals):
        return "  ".join(v.rjust(COLS[c][0]) for c, v in zip(cols, vals))

    for i in range(n):
        if i % hdr_every == 0:
            d.line(render(cols), "header", cols)
        t = h * 3600 + m * 60 + s + i * step
        reads = rng.randint(0, busy) if busy else 0
        hitp = rng.randint(70, 100) if reads else 0
        vals = []
        for c in cols:
            kind = COLS[c][1]
            if kind == "time":
                vals.append(f"{t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}")
            elif kind == "n":
                vals.append(_pretty(int(reads * rng.uniform(0, 1))))
            elif kind == "p":
                vals.append(str(rng.choice([hitp, 100 - hitp, rng.randint(0, 100)]) if reads else 0))
            elif kind == "i":
                vals.append(str(rng.choice([0, 1])))
            else:
                base = {"arcsz": arc, "size": arc, "c": cmax}.get(c, arc * rng.uniform(0, .5))
                vals.append(_pretty(base * rng.uniform(.98, 1.02)))
        d.line(render(vals), "row", vals)
    return d
