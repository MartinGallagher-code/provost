"""FreeBSD `gstat -b`: an interval line of key/value pairs, then a right-
aligned GEOM statistics table where `|` separates %busy from the name."""
from lib import Doc, fake

TOOL = "gstat"


def generate(rng):
    d = Doc()
    dt = f"{rng.uniform(.99, 1.2):.3f}s"
    w = rng.choice(["1.000s", "1.000s", "0.500s", "5.000s"])
    pairs = [("dT", dt), ("w", w)]
    if rng.random() < .25:
        pairs.append(("filter", rng.choice(["ada", "nvd", "da[0-9]$", "gpt"])))
    d.line("  ".join(f"{k}: {v}" for k, v in pairs), "row", [x for p in pairs for x in p])
    cols = ["L(q)", "ops/s", "r/s", "kBps", "ms/r", "w/s", "kBps", "ms/w"]
    kinds = ["i", "f", "f", "f", "t", "f", "f", "t"]
    if rng.random() < .35:
        cols += ["d/s", "kBps", "ms/d"]
        kinds += ["f", "f", "t"]
    if rng.random() < .25:
        cols += ["o/s", "ms/o"]
        kinds += ["f", "t"]
    cols.append("%busy")
    d.line("".join(f"{c:>5}" if i == 0 else f" {c:>6}" for i, c in enumerate(cols)) + " Name", "header", cols + ["Name"])
    devs = []
    base = rng.choice(["ada", "nvd", "da", "vtbd"])
    for n in range(rng.randint(1, 4)):
        dev = f"{base}{n}"
        devs.append(dev)
        for p in range(1, rng.randint(1, 4) + 1):
            devs.append(f"{dev}p{p}")
            if rng.random() < .2:
                devs.append(rng.choice([f"gpt/{fake.word(rng)}{n}", f"diskid/DISK-{fake.token(rng, 12).upper()}", f"{dev}p{p}.eli"]))
    if rng.random() < .3:
        devs += ["cd0", "md0"][:rng.randint(1, 2)]
    for dev in devs:
        busy_dev = rng.random() < .4
        vals = []
        for k in kinds:
            if k == "i":
                vals.append(str(rng.choice([0, 0, 0, 1, rng.randint(0, 32)])) if busy_dev else "0")
            elif k == "f":
                vals.append(f"{rng.randint(0, 9000) if busy_dev else 0}")
            else:
                vals.append(f"{rng.uniform(0, 40) if busy_dev else 0:.1f}")
        busy = f"{rng.uniform(0, 100) if busy_dev else 0:.1f}"
        text = "".join(f"{v:>5}" if i == 0 else f" {v:>6}" for i, v in enumerate(vals)) + f" {busy:>6}| {dev}"
        d.line(text, "row", vals + [busy, dev])
    return d
