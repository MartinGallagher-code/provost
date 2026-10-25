"""`rrdtool fetch file.rrd AVERAGE --start ... --end ...`: a header of
data-source names over an unnamed timestamp column, a blank line, then
`epoch: value value ...` rows in %e notation (`-nan` / `nan` for unknown)."""
from lib import Doc

TOOL = "rrdtool-fetch"

DSSETS = [["value"], ["in", "out"], ["rx", "tx"], ["shortterm", "midterm", "longterm"], ["used", "free", "cached", "buffered"],
          ["temp"], ["ds0", "ds1"], ["user", "system", "wait", "idle"], ["read", "write"], ["ping", "ping_stddev", "ping_droprate"],
          ["load1", "load5", "load15"]]


def generate(rng):
    d = Doc()
    names = rng.choice(DSSETS)
    nan = rng.choice(["-nan", "nan", "NaN"])
    step = rng.choice([10, 60, 300, 300, 1800, 3600, 86400])
    start = (1690000000 + rng.randint(0, 80000000)) // step * step
    n = rng.randint(4, 30)
    d.line(" " * rng.choice([12, 13]) + "".join(nm.rjust(rng.choice([17, 17, 18]) if i == 0 else 17) for i, nm in enumerate(names)),
           "header", [None] + names)
    d.blank()
    scale = [rng.choice([1, 100, 1e4, 1e7, 0.01]) for _ in names]
    gap_from = rng.randint(0, n) if rng.random() < .5 else n + 1
    gap_len = rng.randint(1, 5)
    for i in range(n):
        ts = str(start + i * step)
        vals = []
        for k in range(len(names)):
            unknown = gap_from <= i < gap_from + gap_len or (i == n - 1 and rng.random() < .4)
            vals.append(nan if unknown else f"{rng.uniform(0, 10) * scale[k]:.10e}")
        d.line(f"{ts}: " + " ".join(vals), "row", [ts] + vals)
    return d
