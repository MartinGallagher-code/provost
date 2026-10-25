"""`rdiff-backup --list-increment-sizes DIR` (a Time / Size / Cumulative size
table under a dashed rule, newest first, the mirror annotated) or
`--list-increments DIR` (a count heading, indented increment rows and a
`Current mirror:` line)."""
import datetime

from lib import Doc, fake

TOOL = "rdiff-backup-list-increments"


def _ctime(t):
    return t.strftime("%a %b ") + f"{t.day:2d}" + t.strftime(" %H:%M:%S %Y")


def _size(rng, big=False):
    v = rng.uniform(1, 999)
    u = rng.choice(["GB", "GB", "MB"] if big else ["bytes", "KB", "MB", "MB", "GB"])
    return f"{int(v)} bytes" if u == "bytes" else f"{v:.2f} {u}"


def generate(rng):
    d = Doc()
    n = rng.randint(1, 14)
    t = datetime.datetime(rng.randint(2019, 2026), rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59))
    step = rng.choice([1, 1, 7, 0.25])
    times = []
    for _ in range(n + 1):
        times.append(t)
        t -= datetime.timedelta(days=step, seconds=rng.randint(-90, 90))
    if rng.random() < .55:
        hdr = f"{'Time':>12}{'Size':>27}{'Cumulative size':>23}"
        d.line(hdr, "header", ["Time", "Size", "Cumulative size"])
        d.skip("-" * 77)
        cum = 0.0
        mirror = _size(rng, True)
        for i, tm in enumerate(times):
            sz = mirror if i == 0 else _size(rng)
            cum_s = mirror if i == 0 else f"{rng.uniform(1, 999):.2f} {rng.choice(['MB', 'GB'])}"
            cum_cell = cum_s + ("   (current mirror)" if i == 0 else "")
            d.line(f"{_ctime(tm):<24}{sz:>16}{cum_s:>18}" + ("   (current mirror)" if i == 0 else ""), "row",
                   [_ctime(tm), sz, cum_cell])
        return d
    d.section(f"Found {n} increments:")
    colons = rng.random() < .5
    zone = rng.choice(["Z", "+02:00", "-05:00", "+01:00"])
    for tm in reversed(times[1:]):
        if colons:
            name = "increments." + tm.strftime("%Y-%m-%dT%H:%M:%S") + zone + ".dir"
        else:
            name = "increments." + tm.strftime("%Y-%m-%dT%H-%M-%S") + zone.replace(":", "-") + ".dir"
        d.line(f"    {name}   {_ctime(tm)}", "row", [name, _ctime(tm)])
    d.kv("Current mirror", _ctime(times[0]))
    return d
