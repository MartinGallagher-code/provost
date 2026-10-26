"""httperf: the echoed command line, then its summary block: `Label: key value key value ...`
lines (rows), single-value lines (kv), grouped by blank lines."""
from lib import Doc, fake

TOOL = "httperf"


def _pairs(d, label, pairs, tail=""):
    text = f"{label}: " + " ".join(f"{k} {v}" for k, v in pairs) + tail
    cells = [label]
    for k, v in pairs:
        cells += [k, v]
    d.line(text, "row", cells)


def generate(rng):
    d = Doc()
    server = rng.choice(["localhost", "127.0.0.1", fake.host(rng), f"www.{fake.word(rng)}.example.com"])
    port = rng.choice(["80", "8080", "443", "8000"])
    uri = rng.choice(["/", "/index.html", f"/{fake.word(rng)}", f"/api/{fake.word(rng)}/{rng.randint(1, 99)}"])
    conns = rng.choice([100, 500, 1000, 5000, 10000, 20000])
    calls = rng.choice([1, 1, 1, 5, 10])
    rate = rng.choice([None, 10, 50, 100, 200, 500, 1000])
    opts = [("--client", "0/1"), ("--server", server), ("--port", port), ("--uri", uri)]
    if rate:
        opts.append(("--rate", str(rate)))
    opts += [("--send-buffer", "4096"), ("--recv-buffer", "16384")]
    if port == "443":
        opts.insert(4, ("--ssl", None))
    if rng.random() < .3:
        opts.append(("--timeout", str(rng.choice([1, 5, 10]))))
    opts += [("--num-conns", str(conns)), ("--num-calls", str(calls))]
    text, cells = "httperf", ["httperf"]
    for k, v in opts:
        text += f" {k}" + (f"={v}" if v else "")
        cells += [k] + ([v] if v else [])
    d.line(text, "row", cells)
    if rng.random() < .3:
        d.skip("httperf: warning: open file limit > FD_SETSIZE; limiting max. # of open files to FD_SETSIZE")
    d.kv("Maximum connect burst length", str(rng.choice([1, 1, 2, rng.randint(3, 60)])))
    d.blank()
    reqs = conns * calls
    errs = rng.choice([0, 0, 0, rng.randint(1, conns // 10 + 1)])
    replies = reqs - errs
    dur = conns / (rate or rng.uniform(80, 4000)) * rng.uniform(1, 1.05)
    _pairs(d, "Total", [("connections", str(conns)), ("requests", str(reqs)), ("replies", str(replies)),
                        ("test-duration", f"{dur:.3f} s")])
    d.blank()
    cr = conns / dur
    conc = rng.choice([1, rng.randint(1, 300)])
    d.kv("Connection rate", f"{cr:.1f} conn/s ({1000 / cr:.1f} ms/conn, <={conc} concurrent connections)")
    ct = sorted(rng.uniform(0.1, 900) for _ in range(3))
    _pairs(d, "Connection time [ms]", [("min", f"{ct[0]:.1f}"), ("avg", f"{ct[1]:.1f}"), ("max", f"{ct[2]:.1f}"),
                                       ("median", f"{ct[1] * rng.uniform(.8, 1.1):.1f}"), ("stddev", f"{rng.uniform(0, 50):.1f}")])
    _pairs(d, "Connection time [ms]", [("connect", f"{rng.uniform(0, ct[0]):.1f}")])
    d.kv("Connection length [replies/conn]", f"{replies / conns:.3f}")
    d.blank()
    rr = reqs / dur
    d.kv("Request rate", f"{rr:.1f} req/s ({1000 / rr:.1f} ms/req)")
    d.kv("Request size [B]", f"{rng.randint(55, 400)}.0")
    d.blank()
    ns = max(0, int(dur / 5))
    if ns:
        lo, hi = rr * rng.uniform(.6, 1), rr * rng.uniform(1, 1.3)
        _pairs(d, "Reply rate [replies/s]", [("min", f"{lo:.1f}"), ("avg", f"{rr:.1f}"), ("max", f"{hi:.1f}"),
                                             ("stddev", f"{rng.uniform(0, hi - lo):.1f}")], f" ({ns} samples)")
    else:
        _pairs(d, "Reply rate [replies/s]", [("min", "0.0"), ("avg", "0.0"), ("max", "0.0"), ("stddev", "0.0")], " (0 samples)")
    _pairs(d, "Reply time [ms]", [("response", f"{rng.uniform(0.1, 800):.1f}"), ("transfer", f"{rng.uniform(0, 30):.1f}")])
    h, c = rng.randint(150, 400), rng.randint(0, 200000)
    text = f"Reply size [B]: header {h}.0 content {c}.0 footer {rng.choice([0, 2])}.0 (total {h + c}.0)"
    d.line(text, "row", ["Reply size [B]", "header", f"{h}.0", "content", f"{c}.0", "footer", text.split("footer ")[1].split()[0],
                         "total", f"{h + c}.0"])
    st = [replies - (x := rng.choice([0, 0, rng.randint(0, replies)])), x]
    codes = [("1xx", "0"), ("2xx", str(st[0])), ("3xx", str(rng.choice([0, 0, st[1]]))), ("4xx", str(st[1])), ("5xx", "0")]
    text = "Reply status: " + " ".join(f"{k}={v}" for k, v in codes)
    cells = ["Reply status"]
    for k, v in codes:
        cells += [k, v]
    d.line(text, "row", cells)
    d.blank()
    u, s = rng.uniform(0, dur * .5), rng.uniform(0, dur * .5)
    pu, ps = 100 * u / dur, 100 * s / dur
    text = f"CPU time [s]: user {u:.2f} system {s:.2f} (user {pu:.1f}% system {ps:.1f}% total {pu + ps:.1f}%)"
    d.line(text, "row", ["CPU time [s]", "user", f"{u:.2f}", "system", f"{s:.2f}", "user", f"{pu:.1f}%",
                         "system", f"{ps:.1f}%", "total", f"{pu + ps:.1f}%"])
    kb = rr * (h + c) / 1024
    d.kv("Net I/O", f"{kb:.1f} KB/s ({kb * 8192 / 1e6:.1f}*10^6 bps)")
    d.blank()
    e = [rng.randint(0, errs) for _ in range(5)]
    _pairs(d, "Errors", [("total", str(errs)), ("client-timo", str(e[0])), ("socket-timo", str(e[1])),
                         ("connrefused", str(e[2])), ("connreset", str(e[3]))])
    _pairs(d, "Errors", [("fd-unavail", "0"), ("addrunavail", "0"), ("ftab-full", "0"), ("other", str(e[4]))])
    if rng.random() < .3:
        d.blank()
        _pairs(d, "Session rate [sess/s]", [("min", "0.00"), ("avg", f"{rng.uniform(1, 500):.2f}"), ("max", f"{rng.uniform(1, 900):.2f}"),
                                            ("stddev", f"{rng.uniform(0, 50):.2f}")], f" ({conns}/{conns})")
        d.kv("Session", f"avg {rng.uniform(1, 9):.2f} connections/session")
        d.kv("Session lifetime [s]", f"{rng.uniform(0, 5):.1f}")
        d.kv("Session failtime [s]", f"{rng.uniform(0, 5):.1f}")
        text = "Session length histogram: " + " ".join(str(rng.choice([0, rng.randint(0, conns)])) for _ in range(rng.randint(3, 12)))
        d.line(text, "kv", ["Session length histogram", text.split(": ", 1)[1]])
    return d
