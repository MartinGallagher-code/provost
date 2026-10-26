"""bcc `biolatency [-m] [-D] [-T] [interval [count]]`: a tracing banner, then
log2 histograms (`lo -> hi : count |*****|`), optionally one per disk
(`disk = 'sda'`) and per interval with a timestamp line."""
from lib import Doc

TOOL = "biolatency"


def _hist(d, rng, unit):
    if unit == "usecs":
        peak, top = rng.randint(4, 12), rng.randint(9, 17)
    else:
        peak, top = rng.randint(0, 4), rng.randint(3, 9)
    top = max(top, peak + 1)
    total = rng.choice([30, 500, 5000, 90000])
    counts = []
    for i in range(top + 1):
        dist = abs(i - peak)
        c = int(total / (2 ** (dist * rng.uniform(.6, 1.6)))) if rng.random() < .95 else 0
        counts.append(max(c, 0))
    counts[-1] = max(counts[-1], 1)
    first = 0
    while rng.random() < .3 and first < peak and counts[first] == 0:
        first += 1
    mx = max(counts) or 1
    d.line(" " * 5 + unit.ljust(19) + " : count     distribution", "header", [unit, "count", "distribution"])
    for i in range(first, top + 1):
        lo = 0 if i == 0 else 2 ** i
        hi = 1 if i == 0 else 2 ** (i + 1) - 1
        bar = "*" * int(counts[i] * 40 / mx)
        rng_s = f"{lo:>10} -> {hi:<10}"
        cnt = str(counts[i])
        d.line(f"{rng_s} : {cnt:<8} |{bar:<40}|", "row", [rng_s.strip(), cnt, None])


def generate(rng):
    d = Doc()
    unit = "msecs" if rng.random() < .3 else "usecs"
    per_disk = rng.random() < .35
    stamps = rng.random() < .3
    intervals = rng.choice([1, 1, 2, 3])
    if intervals > 1 or rng.random() < .3:
        d.skip("Tracing block device I/O... Hit Ctrl-C to end.")
    else:
        d.skip("Tracing block device I/O... Hit Ctrl-C to end.")
        d.skip("^C")
    disks = rng.sample(["sda", "sdb", "nvme0n1", "nvme1n1", "vda", "xvda", "dm-0"], rng.randint(1, 3))
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    step = rng.choice([1, 5, 10])
    for it in range(intervals):
        d.blank()
        if stamps:
            t = h * 3600 + m * 60 + s + (it + 1) * step
            ts = f"{t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"
            d.line(ts, "section", [ts])
        for k, dk in enumerate(disks if per_disk else [None]):
            if dk:
                if k:
                    d.blank()
                d.line(f"disk = '{dk}'", "kv", ["disk", f"'{dk}'"])
            _hist(d, rng, unit)
    if rng.random() < .4:
        d.skip("Detaching...")
    return d
