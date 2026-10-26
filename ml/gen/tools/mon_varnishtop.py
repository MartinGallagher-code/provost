"""`varnishtop -1` (one-shot): a headerless, ranked list of log-record
counts: a right-aligned decaying count, the VSL tag, then the record's value
(free text: URLs, header lines, VCL calls)."""
from lib import Doc, fake

TOOL = "varnishtop"

PATHS = ["/", "/index.html", "/favicon.ico", "/robots.txt", "/healthz", "/api/v1/items", "/api/v2/users/me",
         "/static/js/app.{h}.js", "/static/css/main.{h}.css", "/img/logo.png", "/search?q={w}",
         "/products/{n}", "/cart", "/login", "/wp-login.php", "/sitemap.xml", "/feed/", "/{w}/{w}?page={n}"]
UAS = ["Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36",
       "Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0",
       "curl/8.5.0", "kube-probe/1.29", "Googlebot/2.1 (+http://www.google.com/bot.html)", "Prometheus/2.53.0"]


def _path(rng):
    return rng.choice(PATHS).format(h=fake.hexid(rng, 8), w=fake.word(rng), n=rng.randint(1, 9999))


def _value(rng, tag):
    if tag in ("ReqURL", "BereqURL", "RxURL", "TxURL"):
        return _path(rng)
    if tag in ("ReqHeader", "RespHeader", "BereqHeader", "BerespHeader", "RxHeader", "TxHeader"):
        return rng.choice([f"Host: {rng.choice(['www', 'api', 'cdn', 'static'])}.example.com",
                           f"User-Agent: {rng.choice(UAS)}", "Accept-Encoding: gzip, deflate, br",
                           f"X-Forwarded-For: {fake.ip(rng)}", "Connection: keep-alive",
                           f"Cache-Control: max-age={rng.choice([0, 60, 300, 3600, 86400])}",
                           f"Content-Type: {rng.choice(['text/html; charset=utf-8', 'application/json', 'image/png'])}",
                           f"X-Varnish: {rng.randint(10000, 9999999)}", f"Age: {rng.randint(0, 3600)}",
                           "Accept: */*", f"Via: 1.1 {fake.word(rng)} (Varnish/7.4)"])
    if tag in ("RespStatus", "BerespStatus", "RxStatus"):
        return rng.choice(["200", "200", "304", "301", "404", "503", "206", "403"])
    if tag in ("RespReason", "BerespReason"):
        return rng.choice(["OK", "Not Modified", "Not Found", "Moved Permanently", "Backend fetch failed"])
    if tag in ("ReqMethod", "BereqMethod", "RxRequest"):
        return rng.choice(["GET", "GET", "HEAD", "POST", "PURGE", "OPTIONS"])
    if tag == "VCL_call":
        return rng.choice(["RECV", "HASH", "HIT", "MISS", "PASS", "DELIVER", "BACKEND_FETCH", "BACKEND_RESPONSE", "SYNTH"])
    if tag == "VCL_return":
        return rng.choice(["hash", "lookup", "deliver", "fetch", "pass", "pipe", "synth"])
    if tag == "ReqStart":
        return f"{fake.ip(rng)} {rng.randint(1024, 65535)} a0"
    if tag == "Hit":
        return f"{rng.randint(10000, 9999999)} {rng.uniform(0, 3600):.6f} {rng.uniform(0, 10):.6f} 0.000000"
    if tag == "Timestamp":
        return f"Resp: {rng.uniform(1.7e9, 1.8e9):.6f} {rng.uniform(0, 1):.6f} {rng.uniform(0, .01):.6f}"
    if tag == "Backend_health":
        return f"{fake.word(rng)} Still healthy 4---X-RH 5 3 5 {rng.uniform(0, .1):.6f} {rng.uniform(0, .1):.6f} HTTP/1.1 200 OK"
    return fake.word(rng)


TAGSETS = [["ReqURL"], ["ReqHeader"], ["RespStatus"], ["BereqURL"], ["VCL_call"], ["ReqMethod"],
           ["ReqURL", "ReqHeader", "RespStatus", "VCL_call", "VCL_return", "ReqMethod", "RespHeader",
            "Timestamp", "ReqStart", "Hit", "RespReason"],
           ["BereqURL", "BerespStatus", "BerespHeader", "BereqMethod", "BerespReason", "Backend_health"],
           ["RxURL", "RxHeader", "TxHeader", "RxStatus", "RxRequest"]]


def generate(rng):
    d = Doc()
    tags = rng.choice(TAGSETS)
    n = rng.randint(3, 30)
    counts = sorted((rng.choice([rng.uniform(.01, 5), rng.uniform(1, 200), rng.uniform(50, 99999)]) for _ in range(n)),
                    reverse=True)
    rows, seen = [], set()
    for c in counts:
        tag = rng.choice(tags)
        val = _value(rng, tag)
        if (tag, val) in seen:
            continue
        seen.add((tag, val))
        rows.append((f"{c:.2f}", tag, val))
    tw = max(len(t) for _, t, _ in rows) if rng.random() < .7 else 0
    for c, tag, val in rows:
        text = c.rjust(9) + " " + (tag.ljust(tw) if tw else tag) + " " + val
        d.line(text, "row", [c, tag, val])
    return d
