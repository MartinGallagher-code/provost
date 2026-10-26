"""ngxtop (one refresh, captured): a `running for N seconds` status line, then
`Summary:` and `Detailed:` tables in tabulate's orgtbl style (| a | b |, |---+---|)."""
from lib import Doc, fake

TOOL = "ngxtop"


def _org(d, header, rows, numeric):
    w = [max(len(header[i]), *(len(r[i]) for r in rows)) if rows else len(header[i]) for i in range(len(header))]

    def render(cells):
        out = []
        for i, c in enumerate(cells):
            out.append(c.rjust(w[i]) if i in numeric else c.ljust(w[i]))
        return "| " + " | ".join(out) + " |"
    d.line(render(header), "header", header)
    d.skip("|" + "+".join("-" * (x + 2) for x in w) + "|")
    for r in rows:
        d.line(render(r), "row", r)


def generate(rng):
    d = Doc()
    secs = rng.randint(1, 3600)
    recs = rng.randint(0, 2_000_000)
    d.line(f"running for {secs} seconds, {recs} records processed: {recs / secs:.2f} req/sec", "row",
           [f"running for {secs} seconds", f"{recs} records processed", f"{recs / secs:.2f} req/sec"])
    d.blank()
    d.section("Summary:")
    codes = [rng.randint(0, recs) for _ in range(4)]
    _org(d, ["count", "avg_bytes_sent", "2xx", "3xx", "4xx", "5xx"],
         [[str(recs), f"{rng.uniform(0, 90000):.3f}"] + [str(c) for c in codes]], numeric={0, 1, 2, 3, 4, 5})
    d.blank()
    d.section("Detailed:")
    mode = rng.choice(["path", "path", "addr", "status", "ua"])
    n = rng.randint(1, 10)
    if mode == "path":
        header = ["request_path", "count", "avg_bytes_sent", "2xx", "3xx", "4xx", "5xx"]
        keys = rng.sample(["/", "/index.html", "/favicon.ico", "/robots.txt", "/wp-login.php", "/api/v1/users", "/api/v1/orders",
                           "/static/css/main.css", "/static/js/app.min.js", "/healthz", "/login", "/search",
                           "/images/logo.png", "/.env", "/xmlrpc.php", f"/{fake.word(rng)}/{fake.token(rng, 6)}"], n)
        rows = []
        for k in keys:
            c = rng.randint(1, 50000)
            rows.append([k, str(c), f"{rng.uniform(0, 90000):.3f}"] + [str(rng.randint(0, c)) for _ in range(4)])
        numeric = {1, 2, 3, 4, 5, 6}
    elif mode == "addr":
        header = ["remote_addr", "count"]
        rows = [[fake.ip(rng), str(rng.randint(1, 90000))] for _ in range(n)]
        numeric = {1}
    elif mode == "status":
        header = ["status", "count"]
        rows = [[s, str(rng.randint(1, 90000))] for s in rng.sample(["200", "301", "302", "304", "400", "403", "404", "499", "500", "502", "504"], min(n, 11))]
        numeric = {0, 1}
    else:
        header = ["http_user_agent", "count"]
        uas = ["curl/8.4.0", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
               "kube-probe/1.28", "Googlebot/2.1 (+http://www.google.com/bot.html)", "-", "Go-http-client/1.1",
               "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)", "python-requests/2.31.0"]
        rows = [[u, str(rng.randint(1, 90000))] for u in rng.sample(uas, min(n, len(uas)))]
        numeric = {1}
    rows.sort(key=lambda r: -int(r[1]))
    _org(d, header, rows, numeric)
    return d
