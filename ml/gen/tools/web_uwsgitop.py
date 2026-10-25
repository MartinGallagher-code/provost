"""uwsgitop (one screen, captured): two `key: value - key: value` summary lines,
then the per-worker table."""
from lib import Doc, fake

TOOL = "uwsgitop"


def _size(rng, n):
    for u in ("", "K", "M", "G"):
        if n < 1024:
            return f"{n:.0f}{u}" if u == "" or n >= 100 else f"{n:.1f}{u}"
        n /= 1024
    return f"{n:.1f}T"


def generate(rng):
    d = Doc()
    nw = rng.randint(1, 16)
    ver = rng.choice(["2.0.18", "2.0.20", "2.0.21", "2.0.22", "2.0.23"])
    dt = fake.date(rng, "rfc").replace(",", "").replace(" GMT", "")
    tot = rng.randint(0, 9_000_000)
    rps = str(rng.randint(0, 900))
    lq = str(rng.choice([0, 0, 0, rng.randint(1, 100)]))
    tx = _size(rng, rng.randint(0, 2 ** 34))
    head = [("req", str(tot)), ("RPS", rps), ("lq", lq), ("tx", tx)]
    text = f"uwsgi-{ver} - {dt} - " + " - ".join(f"{k}: {v}" for k, v in head)
    cells = [f"uwsgi-{ver}", dt]
    for k, v in head:
        cells += [k, v]
    d.line(text, "row", cells)
    node = fake.host(rng)
    cwd = fake.path(rng)
    uid = str(rng.choice([33, 1000, 0, 999]))
    gid = uid
    mp = str(rng.randint(100, 99999))
    p2 = [("node", node), ("cwd", cwd), ("uid", uid), ("gid", gid), ("masterpid", mp)]
    c2 = []
    for k, v in p2:
        c2 += [k, v]
    d.line(" - ".join(f"{k}: {v}" for k, v in p2), "row", c2)
    if rng.random() < .3:
        d.blank()
    header = ["WID", "%", "PID", "REQ", "RPS", "EXC", "SIG", "STATUS", "AVG", "RSS", "VSZ", "TX", "ReSpwn", "HC", "RunT", "LastSpwn"]
    mem = rng.random() < .6
    rows = []
    shares = [rng.random() for _ in range(nw)]
    ssum = sum(shares) or 1
    base = int(mp)
    for i in range(nw):
        req = int(tot * shares[i] / ssum)
        rows.append([
            str(i + 1), f"{100 * shares[i] / ssum:.1f}", str(base + i + 1), str(req), str(rng.randint(0, 120)),
            str(rng.choice([0, 0, 0, rng.randint(1, 50)])), str(rng.choice([0, 0, rng.randint(1, 5)])),
            rng.choice(["idle", "idle", "busy", "busy", "cheap", "pause", "sig"]),
            f"{rng.randint(0, 3000)}ms",
            _size(rng, rng.randint(2 ** 22, 2 ** 30)) if mem else "0",
            _size(rng, rng.randint(2 ** 26, 2 ** 32)) if mem else "0",
            _size(rng, rng.randint(0, 2 ** 31)),
            str(rng.randint(1, 40)), str(rng.choice([0, 0, rng.randint(1, 9)])),
            f"{rng.uniform(0, 900000):.2f}",
            fake.date(rng, "time") if rng.random() < .8 else fake.date(rng, "datetime"),
        ])
    if rng.random() < .5:
        rows.sort(key=lambda r: -int(r[3]))
    w = [max(len(h), *(len(r[i]) for r in rows)) for i, h in enumerate(header)]
    pad = rng.choice([0, 0, 1])
    def render(cells):
        return " " + "".join(c.ljust(max(8, w[i] + 1 + pad)) for i, c in enumerate(cells)).rstrip()
    d.line(render(header), "header", header)
    for r in rows:
        d.line(render(r), "row", r)
    return d
