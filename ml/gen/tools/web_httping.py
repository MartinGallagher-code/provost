"""httping: a PING header, one `connected to ...` line per probe with seq=/time=
pairs, then a `--- ... ping statistics ---` block."""
from lib import Doc, fake

TOOL = "httping"


def generate(rng):
    d = Doc()
    host = rng.choice([fake.host(rng), f"www.{fake.word(rng)}.example.com", "localhost", fake.ip(rng)])
    tls = rng.random() < .4
    port = "443" if tls else rng.choice(["80", "80", "8080"])
    path = rng.choice(["/", "/", "/health", f"/{fake.word(rng)}"])
    url = f"{'https' if tls else 'http'}://{host}{path}" if rng.random() < .7 else host
    addr = fake.ip(rng) if not host[0].isdigit() else host
    d.skip(f"PING {host}:{port} ({path}):")
    n = rng.randint(3, 20)
    status = rng.random() < .4
    nbytes = rng.randint(100, 900)
    ok, times = 0, []
    split = rng.random() < .2
    for seq in range(n):
        if rng.random() < .08:
            d.line(rng.choice(["timeout receiving reply from host", "connect time out",
                               f"error connecting to host ({addr}): Connection refused"]), "row",
                   [])
            d.labels[-1]["cells"] = [d.lines[-1]]
            continue
        t = rng.choice([rng.uniform(0.2, 5), rng.uniform(5, 120), rng.uniform(100, 3000)])
        times.append(t)
        ok += 1
        if split:
            parts = [rng.uniform(0, t / 4) for _ in range(3)]
            tv = "+".join(f"{x:6.2f}" for x in parts + [t - sum(parts)]) + " ms"
        else:
            tv = f"{t:6.2f} ms"
        text = f"connected to {addr}:{port} ({nbytes} bytes), seq={seq} time={tv}"
        cells = ["connected to", f"{addr}:{port}", f"{nbytes} bytes", "seq", str(seq), "time", tv.strip()]
        if status:
            code = rng.choice(["200 OK", "200 OK", "301 Moved Permanently", "404 Not Found", "503 Service Unavailable"])
            text += f" {code}"
            cells.append(code)
        d.line(text + " ", "row", cells)
    d.line(f"--- {url} ping statistics ---", "section", [f"{url} ping statistics"])
    total_ms = int(n * 1000 + sum(times))
    failed = 100 * (n - ok) / n
    text = f"{n} connects, {ok} ok, {failed:.2f}% failed, time {total_ms}ms"
    d.line(text, "row", [f"{n} connects", f"{ok} ok", f"{failed:.2f}% failed", "time", f"{total_ms}ms"])
    if times:
        val = f"{min(times):.1f}/{sum(times) / len(times):.1f}/{max(times):.1f} ms"
        d.kv("round-trip min/avg/max", val, sep=" = ")
    if status and rng.random() < .5:
        d.kv("HTTP status counts", ", ".join(f"{c}={rng.randint(1, n)}" for c in ["200"] + rng.sample(["301", "404", "503"], rng.randint(0, 2))))
    return d
