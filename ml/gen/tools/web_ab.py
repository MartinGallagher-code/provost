"""ApacheBench (`ab -n N -c C URL`): banner, progress, key/value report,
connection-times table and the percentile list."""
from lib import Doc, fake

TOOL = "ab"


def _kv(d, key, value):
    d.line((key + ":").ljust(24) + value, "kv", [key, value])


def generate(rng):
    d = Doc()
    d.skip("This is ApacheBench, Version 2.3 <$Revision: %d $>" % rng.choice([1843412, 1879490, 1903618, 1913912]))
    d.skip("Copyright 1996 Adam Twiss, Zeus Technology Ltd, http://www.zeustech.net/")
    d.skip("Licensed to The Apache Software Foundation, http://www.apache.org/")
    d.blank()
    host = rng.choice([fake.host(rng), "localhost", "127.0.0.1", f"www.{fake.word(rng)}.example.com", fake.ip(rng)])
    n = rng.choice([100, 500, 1000, 2000, 5000, 10000, 50000])
    c = rng.choice([1, 2, 5, 10, 20, 50, 100, 200])
    d.skip(f"Benchmarking {host} (be patient)" + ("" if n >= 1000 else ".....done"))
    if n >= 1000:
        step = n // 10
        for i in range(1, 10):
            d.skip(f"Completed {step * i} requests")
        d.skip(f"Finished {n} requests")
    d.blank()
    d.blank()
    tls = rng.random() < 0.5
    server = rng.choice(["nginx", "nginx/1.24.0", "Apache/2.4.58 (Ubuntu)", "Apache", "gunicorn", "openresty/1.21.4.3",
                         "cloudflare", "Caddy", "lighttpd/1.4.73", "Microsoft-IIS/10.0", "envoy", ""])
    _kv(d, "Server Software", server) if server else d.line("Server Software:", "kv", ["Server Software"])
    _kv(d, "Server Hostname", host)
    _kv(d, "Server Port", "443" if tls else rng.choice(["80", "8080", "3000", "8000"]))
    if tls:
        proto = rng.choice(["TLSv1.3,TLS_AES_256_GCM_SHA384,2048,256", "TLSv1.2,ECDHE-RSA-AES128-GCM-SHA256,2048,128",
                            "TLSv1.3,TLS_AES_128_GCM_SHA256,256,128", "TLSv1.2,ECDHE-ECDSA-CHACHA20-POLY1305,256,256"])
        _kv(d, "SSL/TLS Protocol", proto)
        _kv(d, "Server Temp Key", rng.choice(["X25519 253 bits", "ECDH P-256 256 bits", "ECDH X25519 253 bits"]))
        _kv(d, "TLS Server Name", host)
    d.blank()
    path = rng.choice(["/", "/index.html", "/api/v1/health", f"/{fake.word(rng)}/{fake.word(rng)}", "/static/app.js",
                       f"/search?q={fake.word(rng)}&page={rng.randint(1, 9)}"])
    _kv(d, "Document Path", path)
    doclen = rng.randint(0, 250000)
    _kv(d, "Document Length", f"{doclen} bytes")
    d.blank()
    complete = n - (rng.randint(1, n // 20) if rng.random() < 0.15 else 0)
    secs = rng.uniform(0.2, 120)
    rps = complete / secs
    _kv(d, "Concurrency Level", str(c))
    _kv(d, "Time taken for tests", f"{secs:.3f} seconds")
    _kv(d, "Complete requests", str(complete))
    failed = rng.choice([0, 0, 0, rng.randint(1, n // 10 + 1)])
    _kv(d, "Failed requests", str(failed))
    if failed:
        parts = [("Connect", rng.randint(0, failed)), ("Receive", 0), ("Length", failed), ("Exceptions", 0)]
        text = "   (" + ", ".join(f"{k}: {v}" for k, v in parts) + ")"
        cells = []
        for k, v in parts:
            cells += [k, str(v)]
        d.line(text, "row", cells)
    if rng.random() < 0.25:
        _kv(d, "Non-2xx responses", str(rng.randint(1, n)))
    if rng.random() < 0.2:
        _kv(d, "Keep-Alive requests", str(rng.randint(0, n)))
    hdr = rng.randint(150, 400)
    _kv(d, "Total transferred", f"{complete * (doclen + hdr)} bytes")
    _kv(d, "HTML transferred", f"{complete * doclen} bytes")
    _kv(d, "Requests per second", f"{rps:.2f} [#/sec] (mean)")
    _kv(d, "Time per request", f"{1000 * c / rps:.3f} [ms] (mean)")
    _kv(d, "Time per request", f"{1000 / rps:.3f} [ms] (mean, across all concurrent requests)")
    _kv(d, "Transfer rate", f"{complete * (doclen + hdr) / secs / 1024:.2f} [Kbytes/sec] received")
    if rng.random() < 0.2:
        for what in ("sent", "total"):
            val = f"{rng.uniform(1, 9000):.2f} kb/s {what}"
            d.line(" " * 24 + val, "cont", [val])
    d.blank()
    d.section("Connection Times (ms)")
    rows = []
    base = rng.randint(0, 50)
    for name in ["Connect:", "Processing:", "Waiting:", "Total:"]:
        mn = rng.randint(0, base + 1)
        mean = mn + rng.randint(0, 60)
        sd = f"{rng.uniform(0, 80):.1f}"
        med = mn + rng.randint(0, 60)
        mx = mean + rng.randint(0, rng.choice([20, 300, 3000]))
        rows.append([name, str(mn), str(mean), sd, str(med), str(mx)])
    w = [max(len(r[i]) for r in rows) for i in range(6)]
    w[0] = max(w[0], 11)
    d.line("              min  mean[+/-sd] median   max", "header", [None, "min", "mean", "[+/-sd]", "median", "max"])
    for r in rows:
        text = r[0].ljust(12) + r[1].rjust(5) + r[2].rjust(6) + r[3].rjust(6) + r[4].rjust(7) + r[5].rjust(8)
        d.line(text, "row", [r[0].rstrip(":")] + r[1:])
    if rng.random() < 0.3:
        d.skip("WARNING: The median and mean for the initial connection time are not within a normal deviation")
        d.skip("        These results are probably not that reliable.")
    d.blank()
    d.section("Percentage of the requests served within a certain time (ms)")
    v = rng.randint(1, 200)
    for p in [50, 66, 75, 80, 90, 95, 98, 99, 100]:
        v += rng.randint(0, 20 if p < 99 else 400)
        val = str(v) + (" (longest request)" if p == 100 else "")
        d.line(f"{p:>4}%{v:>7}" + (" (longest request)" if p == 100 else ""), "row", [f"{p}%", val])
    return d
