"""iperf (version 2) client or server run: a rule-boxed banner of settings,
the connection line, then a `[ ID] Interval Transfer Bandwidth` table of
per-interval rows (with `[SUM]` rows for parallel streams)."""
from lib import Doc, fake

TOOL = "iperf"

RULE = "-" * 60


def _xfer(rng, mbps, secs):
    mbytes = mbps * secs / 8
    if mbytes >= 1024:
        return f"{mbytes / 1024:.2f} GBytes"
    if mbytes >= 10:
        return f"{mbytes:.0f} MBytes"
    if mbytes >= 1:
        return f"{mbytes:.2f} MBytes"
    return f"{mbytes * 1024:.0f} KBytes"


def _bw(mbps):
    if mbps >= 1000:
        return f"{mbps / 1000:.2f} Gbits/sec"
    if mbps >= 1:
        return f"{mbps:.0f} Mbits/sec" if mbps >= 10 else f"{mbps:.2f} Mbits/sec"
    return f"{mbps * 1000:.0f} Kbits/sec"


def generate(rng):
    d = Doc()
    udp = rng.random() < .3
    server = rng.random() < .3
    proto = "UDP" if udp else "TCP"
    port = rng.choice(["5001", "5001", "5201", str(rng.randint(2000, 9000))])
    peer, me = fake.ip(rng), fake.ip(rng)
    d.skip(RULE)
    if server:
        d.line(f"Server listening on {proto} port {port}", "row", ["Server listening on", proto, "port", port])
    else:
        d.line(f"Client connecting to {peer}, {proto} port {port}", "row",
               ["Client connecting to", peer, proto, "port", port])
    if udp:
        if server:
            d.line("Receiving 1470 byte datagrams", "row", ["Receiving", "1470 byte datagrams"])
        else:
            d.line("Sending 1470 byte datagrams, IPG target: 11215.21 us (kalman adjust)", "row",
                   ["Sending", "1470 byte datagrams", "IPG target", "11215.21 us (kalman adjust)"])
        buf = f"{rng.choice(['208', '160', '1.00'])} {rng.choice(['KByte', 'MByte'])}"
        d.line(f"UDP buffer size: {buf} (default)", "kv", ["UDP buffer size", f"{buf} (default)"])
    else:
        win = f"{rng.choice(['85.0', '128', '64.0', '16.0', '2.50'])} {rng.choice(['KByte', 'KByte', 'MByte'])}"
        extra = rng.choice([" (default)", "", f" (WARNING: requested {rng.choice(['1.00', '4.00'])} MByte)"])
        d.line(f"TCP window size: {win}{extra}", "kv", ["TCP window size", win + extra])
    d.skip(RULE)
    nstreams = rng.choice([1, 1, 1, 2, 4])
    ids = sorted(rng.sample(range(3, 12), nstreams))
    for i in ids:
        a, b = me, peer
        pa, pb = (str(rng.randint(30000, 65000)), port) if not server else (port, str(rng.randint(30000, 65000)))
        tag = f"[{i:3d}]"
        d.line(f"{tag} local {a} port {pa} connected with {b} port {pb}", "row",
               [str(i), "local", a, "port", pa, "connected with", b, "port", pb])
    cols = ["ID", "Interval", "Transfer", "Bandwidth"]
    if udp and server:
        cols += ["Jitter", "Lost/Total Datagrams"]
    hdr = "[ ID] Interval       Transfer     Bandwidth"
    if len(cols) > 4:
        hdr += "        Jitter   Lost/Total Datagrams"
    d.line(hdr, "header", cols)
    total = rng.choice([5, 10, 10, 10, 30])
    step = rng.choice([1, 1, 2, 5]) if rng.random() < .7 else total
    base = rng.choice([1.05, 94, 300, 941, 2400, 9400]) if not udp else rng.choice([1.05, 10.0, 100])

    def row(sid, t0, t1, mbps):
        secs = t1 - t0
        iv = f"{t0:4.1f}-{t1:4.1f} sec"
        x, bw = _xfer(rng, mbps, secs), _bw(mbps)
        tag = "[SUM]" if sid is None else f"[{sid:3d}]"
        text = f"{tag} {iv}  {x:>11}  {bw:>15}"
        cells = ["SUM" if sid is None else str(sid), iv, x, bw]
        if len(cols) > 4:
            jit = f"{rng.uniform(0, 3):.3f} ms"
            tot = int(mbps * secs * 1e6 / 8 / 1470)
            lost = rng.choice([0, 0, rng.randint(0, max(1, tot // 50))])
            lt = f"{lost}/{tot} ({100 * lost / max(tot, 1):.{rng.choice([0, 2])}f}%)"
            text += f"  {jit:>9}  {lt:>15}"
            cells += [jit, lt]
        d.line(text, "row", cells)

    t = 0
    while t < total:
        t1 = min(total, t + step)
        sums = 0
        for i in ids:
            m = base * rng.uniform(.85, 1.05) / nstreams
            sums += m
            row(i, t, t1, m)
        if nstreams > 1:
            row(None, t, t1, sums)
        t = t1
    if step != total:
        for i in ids:
            row(i, 0, total, base * rng.uniform(.9, 1.0) / nstreams)
        if nstreams > 1:
            row(None, 0, total, base * rng.uniform(.9, 1.0))
    if udp and not server:
        sid = ids[0]
        n = rng.randint(800, 90000)
        d.line(f"[{sid:3d}] Sent {n} datagrams", "kv", ["Sent", f"{n} datagrams"])
        if rng.random() < .85:
            d.line(f"[{sid:3d}] Server Report:", "section", ["Server Report"])
            jit = f"{rng.uniform(0, 3):.3f} ms"
            lost = rng.choice([0, 0, rng.randint(1, max(2, n // 40))])
            lt = f"{lost}/{n:>5} ({100 * lost / n:.{rng.choice([0, 2])}g}%)"
            iv = f" 0.0-{total:4.1f} sec"
            x, bw = _xfer(rng, base, total), _bw(base)
            d.line(f"[{sid:3d}] {iv}  {x:>11}  {bw:>15}  {jit:>9}  {lt}", "row",
                   [str(sid), iv.strip(), x, bw, jit, lt])
        else:
            d.line(f"[{sid:3d}] WARNING: did not receive ack of last datagram after 10 tries.", "skip")
    return d
