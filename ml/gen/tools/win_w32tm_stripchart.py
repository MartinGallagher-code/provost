"""cmd `w32tm /stripchart /computer:<peer>` (optionally /dataonly): a
`Tracking` line, prose, the current time, then one sample per line:
`HH:MM:SS, d:+00.0312345s o:-00.0012345s  [   *   |   ]` (the strip is
decoration), with `error: 0x800705B4` lines for timed-out samples."""
from lib import Doc, fake

TOOL = "w32tm-stripchart"

PEERS = ["time.windows.com", "pool.ntp.org", "0.pool.ntp.org", "time.nist.gov", "dc01.corp.example.com",
         "ntp.ubuntu.com", "time.cloudflare.com", "10.0.0.1"]


def _sec(x):
    return f"{'+' if x >= 0 else '-'}{abs(x):010.7f}s"


def generate(rng):
    d = Doc()
    peer = rng.choice(PEERS)
    ip = peer if peer[0].isdigit() else fake.ip(rng)
    n = rng.randint(2, 12)
    data_only = rng.random() < .3
    tr = f"{peer} [{ip}:123]"
    d.line(f"Tracking {tr}.", "kv", ["Tracking", tr])
    d.skip(f"Collecting {n} samples.")
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    ap = rng.random() < .6
    hh = (h % 12 or 12) if ap else h
    now = f"{rng.randint(1, 12)}/{rng.randint(1, 28)}/2026 {hh}:{m:02d}:{s:02d}" + (f" {'AM' if h < 12 else 'PM'}" if ap else "")
    d.line(f"The current time is {now}.", "kv", ["The current time is", now])
    base = rng.uniform(-2, 2) if rng.random() < .3 else rng.uniform(-.05, .05)
    step = rng.choice([1, 2, 2, 5])
    width = rng.choice([25, 27, 31])
    for i in range(n):
        s += step
        if s >= 60:
            s -= 60
            m = (m + 1) % 60
        t = f"{h:02d}:{m:02d}:{s:02d}"
        if rng.random() < .1:
            err = rng.choice(["0x800705B4", "0x80072746", "0x800705B4"])
            d.line(f"{t}, error: {err}", "row", [t, "error", err])
            continue
        delay = rng.uniform(0.0005, 0.12)
        off = base + rng.uniform(-.005, .005)
        if data_only:
            o = _sec(off)
            d.line(f"{t}, {o}", "row", [t, o])
            continue
        ds, os_ = _sec(delay), _sec(off)
        pos = max(0, min(2 * width, width + int(off * width / .05 if abs(base) < .1 else off * width / 2.5)))
        bar = [" "] * (2 * width + 1)
        bar[width] = "|"
        bar[pos] = "*"
        d.line(f"{t}, d:{ds} o:{os_}  [" + "".join(bar) + "]", "row", [t, "d", ds, "o", os_])
    return d
