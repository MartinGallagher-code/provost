"""`mongostat`: one right-aligned line per interval, `*N` for replicated ops,
`a|b` queue pairs, sizes with units, the header repeated every few lines;
replica-set and --discover runs add set/repl and host columns."""
from lib import Doc, fake

TOOL = "mongostat"


def _sz(rng, lo, hi, units="bkmG"):
    v = rng.uniform(lo, hi)
    u = rng.choice(units)
    return (f"{v:.0f}" if u == "b" else f"{v:.1f}" if v < 100 else f"{v:.0f}") + u


def generate(rng):
    d = Doc()
    rs = rng.random() < .55
    discover = rs and rng.random() < .35
    engine_wt = rng.random() < .9
    cols = ["insert", "query", "update", "delete", "getmore", "command"]
    cols += ["dirty", "used", "flushes"] if engine_wt else ["flushes", "mapped"]
    cols += ["vsize", "res", "qrw", "arw", "net_in", "net_out", "conn"]
    if rs:
        cols += ["set", "repl"]
    cols += ["time"]
    if discover:
        cols = ["host"] + cols
    setname = rng.choice(["rs0", "replset", "shard01", "prod-rs"])
    hosts = [f"{rng.choice(['mongo', 'db', 'mdb'])}{i}.{rng.choice(['internal', 'example.com'])}:27017" for i in range(1, 4)]
    hh, mm, ss = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    day = rng.randint(1, 28)
    mon = rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())
    vs = rng.uniform(1, 60)
    res = vs * rng.uniform(.05, .6)
    me_primary = rng.random() < .5
    host_repl = {h: ("PRI" if i == 0 else rng.choice(["SEC", "SEC", "SEC", "ARB", "REC"])) for i, h in enumerate(hosts)}
    mapped = _sz(rng, 1, 80, "MG")
    rows = []
    ticks = rng.randint(3, 24)
    for t in range(ticks):
        for h in (hosts if discover else [None]):
            primary = not rs or (host_repl[h] == "PRI" if discover else me_primary)
            star = "" if primary else "*"
            r = {}
            for c in ["insert", "query", "update", "delete"]:
                r[c] = star + str(rng.choice([0, 0, rng.randint(0, 50), rng.randint(0, 5000)]))
            r["getmore"] = str(rng.choice([0, rng.randint(0, 30)]))
            r["command"] = f"{rng.randint(0, 400)}|{rng.choice([0, 0, rng.randint(0, 9)])}"
            r["dirty"] = f"{rng.uniform(0, 5):.1f}%"
            r["used"] = f"{rng.uniform(0, 80):.1f}%"
            r["flushes"] = str(rng.choice([0, 0, 0, 1]))
            r["mapped"] = mapped
            r["vsize"] = f"{vs:.2f}G" if vs < 10 else f"{vs:.1f}G"
            r["res"] = f"{res * 1024:.0f}M" if res < 1 else f"{res:.2f}G"
            r["qrw"] = f"{rng.choice([0, 0, rng.randint(0, 9)])}|{rng.choice([0, 0, rng.randint(0, 9)])}"
            r["arw"] = f"{rng.randint(0, 3)}|{rng.choice([0, rng.randint(0, 4)])}"
            r["net_in"] = _sz(rng, 50, 999, "bkm")
            r["net_out"] = _sz(rng, 50, 999, "bkm")
            r["conn"] = str(rng.randint(2, 900))
            r["set"] = setname
            r["repl"] = host_repl[h] if discover else ("PRI" if primary else "SEC")
            r["time"] = f"{mon} {day:2d} {hh:02d}:{mm:02d}:{(ss + t) % 60:02d}.{rng.randint(0, 999):03d}"
            r["host"] = h
            rows.append([r[c] for c in cols])
    w = [max(len(cols[c]), *(len(r[c]) for r in rows)) for c in range(len(cols))]

    def fmt(vals):
        return " ".join(v.rjust(w[c]) if not (discover and c == 0) else v.ljust(w[c]) for c, v in enumerate(vals))

    every = rng.choice([10, 10, 5]) * (3 if discover else 1)
    noheaders = rng.random() < .15
    for i, r in enumerate(rows):
        if not noheaders and i % every == 0:
            d.line(fmt(cols), "header", cols)
        d.line(fmt(r), "row", r)
    return d
