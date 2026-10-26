"""varnishncsa: Apache/NCSA combined log lines from the Varnish shared log,
optionally with a custom -F format adding time-taken and hit/miss."""
from lib import Doc, fake

TOOL = "varnishncsa"

UAS = ["curl/8.4.0", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
       "Wget/1.21.4", "kube-probe/1.28", "Googlebot/2.1 (+http://www.google.com/bot.html)", "-",
       "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
       "Prometheus/2.47.0", "python-requests/2.31.0"]
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def generate(rng):
    d = Doc()
    fmt = rng.choice(["combined", "combined", "timed", "hitmiss", "xff"])
    hosts = [f"www.{fake.word(rng)}.example.com", fake.host(rng), "localhost"]
    day, mon, yr = rng.randint(1, 28), rng.choice(MON), rng.randint(2020, 2026)
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    tz = rng.choice(["+0000", "+0100", "-0500", "+0200"])
    clients = [fake.ip(rng) for _ in range(rng.randint(1, 6))] + ([fake.ip(rng, v6=True)] if rng.random() < .3 else [])
    for _ in range(rng.randint(3, 25)):
        s += rng.randint(0, 3)
        m, s = m + s // 60, s % 60
        h, m = (h + m // 60) % 24, m % 60
        ts = f"[{day:02d}/{mon}/{yr}:{h:02d}:{m:02d}:{s:02d} {tz}]"
        ip = rng.choice(clients)
        user = "-" if rng.random() < .93 else rng.choice(fake.USERS)
        method = rng.choice(["GET"] * 6 + ["HEAD", "POST", "PURGE", "OPTIONS"])
        path = rng.choice(["/", "/index.html", f"/{fake.word(rng)}/{fake.word(rng)}", f"/static/{fake.token(rng, 8)}.js",
                           f"/api/v{rng.randint(1, 3)}/{fake.word(rng)}?page={rng.randint(1, 40)}", "/favicon.ico", "/robots.txt",
                           f"/img/{fake.token(rng, 12)}.webp"])
        url = f"http://{rng.choice(hosts)}{path}"
        req = f"{method} {url} {rng.choice(['HTTP/1.1', 'HTTP/1.1', 'HTTP/2.0', 'HTTP/1.0'])}"
        status = rng.choice(["200"] * 8 + ["304", "301", "404", "403", "500", "503", "206"])
        size = "-" if status in ("304",) and rng.random() < .5 else str(rng.choice([0, rng.randint(1, 999), rng.randint(1000, 4_000_000)]))
        ref = rng.choice(["-", "-", f"https://{rng.choice(hosts)}/", f"https://www.google.com/search?q={fake.word(rng)}"])
        ua = rng.choice(UAS)
        cells = [ip, "-", user, ts, req, status, size, ref, ua]
        text = f'{ip} - {user} {ts} "{req}" {status} {size} "{ref}" "{ua}"'
        if fmt == "timed":
            us = str(rng.randint(80, 9_000_000))
            text += f" {us}"
            cells.append(us)
        elif fmt == "hitmiss":
            hm = rng.choice(["hit", "miss", "miss", "pass", "synth"])
            ttfb = f"{rng.uniform(0, 3):.6f}"
            text += f" {hm} {ttfb}"
            cells += [hm, ttfb]
        elif fmt == "xff":
            xff = rng.choice(["-", fake.ip(rng), f"{fake.ip(rng)}, {fake.ip(rng)}"])
            text += f' "{xff}"'
            cells.append(xff)
        d.line(text, "row", cells)
    return d
