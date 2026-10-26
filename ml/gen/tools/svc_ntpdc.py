"""`ntpdc -c sysinfo` (aligned key/value report) optionally followed by
`ntpdc -c peers` (a ruled table with right-aligned numbers)."""
from lib import Doc, fake

TOOL = "ntpdc"

SERVERS = ["0.pool.ntp.org", "1.debian.pool.ntp.org", "time.cloudflare.com", "ntp1.example.com",
           "ntp.ubuntu.com", "time.google.com", "gps0.lan", "tick.usno.navy.mil", "LOCAL(0)",
           "ntp-b.nist.gov", "clock.isc.org"]


def sysinfo(d, rng):
    peer = rng.choice(SERVERS)
    stratum = rng.randint(1, 5)
    ref = rng.choice([fake.ip(rng), "127.127.1.0", "GPS", "PPS"])
    mons = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    rt = (f"{fake.hexid(rng, 8)}.{fake.hexid(rng, 8)}  {rng.choice(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])}, "
          f"{rng.choice(mons)} {rng.randint(1, 28):2d} {rng.randint(2019, 2026)} "
          f"{rng.randint(0, 23):2d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}.{rng.randint(0, 999):03d}")
    pairs = [("system peer", peer),
             ("system peer mode", rng.choice(["client", "client", "symmetric active", "unspec"])),
             ("leap indicator", rng.choice(["00", "00", "01", "11"])),
             ("stratum", str(stratum)),
             ("precision", str(rng.randint(-24, -18))),
             ("root distance", f"{rng.uniform(0, .2):.5f} s"),
             ("root dispersion", f"{rng.uniform(0, .3):.5f} s"),
             ("reference ID", f"[{ref}]"),
             ("reference time", rt),
             ("system flags", " ".join(rng.sample(["auth", "monitor", "ntp", "kernel", "stats", "bclient", "pll"],
                                                 rng.randint(2, 5)))),
             ("jitter", f"{rng.uniform(0, .01):.6f} s"),
             ("stability", f"{rng.uniform(0, 2):.3f} ppm"),
             ("broadcastdelay", f"{rng.choice([0, .003, .004]):.6f} s"),
             ("authdelay", "0.000000 s")]
    w = 22
    for k, v in pairs:
        text = (k + ":").ljust(w) + v
        if k == "reference time":
            a, b = v.split("  ", 1)
            d.line(text, "kv", [k, a, b])
        else:
            d.line(text, "kv", [k, v])


def peers(d, rng):
    local = fake.ip(rng)
    d.line("     remote           local      st poll reach  delay   offset    disp", "header",
           ["remote", "local", "st", "poll", "reach", "delay", "offset", "disp"])
    d.skip("=" * 71)
    for _ in range(rng.randint(1, 8)):
        sym = rng.choice("*+=-.^ #")
        name = (sym + rng.choice(SERVERS + [fake.ip(rng)]))[:16]
        st = str(rng.randint(1, 16))
        poll = str(rng.choice([16, 64, 128, 256, 512, 1024]))
        reach = rng.choice(["377", "377", "377", "177", "17", "1", "0"])
        delay = f"{rng.uniform(0, .3):.5f}"
        off = f"{rng.uniform(-.05, .05):.6f}"
        disp = f"{rng.uniform(0, 4):.5f}"
        lip = rng.choice([local, local, "0.0.0.0"])
        text = f"{name:<16s} {lip:<15s} {st:>2s} {poll:>4s} {reach:>5s} {delay} {off:>9s} {disp}"
        d.line(text, "row", [name, lip, st, poll, reach, delay, off, disp])


def generate(rng):
    d = Doc()
    mode = rng.random()
    if mode < 0.75:
        sysinfo(d, rng)
    if mode > 0.45:
        if mode < 0.75:
            d.blank() if rng.random() < 0.5 else None
        peers(d, rng)
    return d
