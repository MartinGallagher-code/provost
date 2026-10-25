"""varnishlog (default -g vxid): one block per transaction, a `*   << Request  >> vxid`
heading then `-   Tag   value` records, blank line between blocks."""
from lib import Doc, fake

TOOL = "varnishlog"

UAS = ["curl/8.4.0", "Mozilla/5.0 (X11; Linux x86_64; rv:119.0) Gecko/20100101 Firefox/119.0",
       "Wget/1.21.4", "kube-probe/1.28", "Go-http-client/1.1", "python-requests/2.31.0",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15"]


def _ts(rng, t0, label):
    a = rng.uniform(0, 0.2)
    return f"{label}: {t0 + a:.6f} {a:.6f} {rng.uniform(0, a):.6f}"


def _block(d, rng, kind, vxid, t0, pad):
    d.line(f"*   << {kind:<8} >> {vxid}", "section", [f"<< {kind:<8} >> {vxid}"])
    recs = []
    host = rng.choice([fake.host(rng), f"www.{fake.word(rng)}.example.com", "localhost:6081"])
    url = rng.choice(["/", "/index.html", f"/{fake.word(rng)}/{fake.word(rng)}.css", f"/api/{fake.word(rng)}?id={rng.randint(1, 9999)}",
                      "/favicon.ico", f"/img/{fake.token(rng, 10)}.png"])
    status, reason = rng.choice([("200", "OK"), ("200", "OK"), ("304", "Not Modified"), ("404", "Not Found"),
                                 ("301", "Moved Permanently"), ("503", "Backend fetch failed")])
    if kind == "Request":
        recs.append(("Begin", f"req {vxid - 1} rxreq"))
        recs.append(("Timestamp", _ts(rng, t0, "Start")))
        recs.append(("Timestamp", _ts(rng, t0, "Req")))
        if rng.random() < 0.5:
            recs.append(("VCL_use", "boot"))
        recs.append(("ReqStart", f"{fake.ip(rng)} {rng.randint(1024, 65535)} {rng.choice(['a0', 'a1', 'http', 'https'])}"))
        recs.append(("ReqMethod", rng.choice(["GET", "GET", "HEAD", "POST", "PURGE"])))
        recs.append(("ReqURL", url))
        recs.append(("ReqProtocol", rng.choice(["HTTP/1.1", "HTTP/1.0", "HTTP/2.0"])))
        recs.append(("ReqHeader", f"Host: {host}"))
        recs.append(("ReqHeader", f"User-Agent: {rng.choice(UAS)}"))
        recs.append(("ReqHeader", "Accept: " + rng.choice(["*/*", "text/html", "image/webp,*/*"])))
        recs.append(("ReqHeader", f"X-Forwarded-For: {fake.ip(rng)}"))
        hit = rng.random() < 0.55
        for call, ret in [("RECV", "hash"), ("HASH", "lookup")]:
            recs += [("VCL_call", call), ("VCL_return", ret)]
        if hit:
            recs.append(("Hit", f"{vxid + 1} {rng.uniform(1, 3600):.6f} {rng.choice(['10.000000', '0.000000'])} 0.000000"))
            recs += [("VCL_call", "HIT"), ("VCL_return", "deliver")]
        else:
            recs.append(("VCL_call", "MISS"))
            recs.append(("VCL_return", "fetch"))
            recs.append(("Link", f"bereq {vxid + 1} fetch"))
            recs.append(("Timestamp", _ts(rng, t0, "Fetch")))
        recs.append(("RespProtocol", "HTTP/1.1"))
        recs.append(("RespStatus", status))
        recs.append(("RespReason", reason))
        recs.append(("RespHeader", "Content-Type: " + rng.choice(["text/html; charset=utf-8", "application/json", "image/png", "text/css"])))
        recs.append(("RespHeader", f"X-Varnish: {vxid}" + (f" {vxid + 1}" if hit else "")))
        recs.append(("RespHeader", f"Age: {rng.randint(0, 3600) if hit else 0}"))
        recs.append(("RespHeader", "Via: 1.1 varnish (Varnish/7.4)"))
        recs += [("VCL_call", "DELIVER"), ("VCL_return", "deliver")]
        recs.append(("Timestamp", _ts(rng, t0, "Process")))
        recs.append(("RespHeader", "Accept-Ranges: bytes"))
        recs.append(("RespHeader", f"Content-Length: {rng.randint(0, 90000)}"))
        recs.append(("RespHeader", "Connection: keep-alive"))
        recs.append(("Timestamp", _ts(rng, t0, "Resp")))
        a = [rng.randint(40, 900), 0, 0, rng.randint(150, 400), rng.randint(0, 90000)]
        a[2], a = a[0], a + [0]
        a[5] = a[3] + a[4]
        recs.append(("ReqAcct", " ".join(map(str, a))))
        recs.append(("End", None))
    else:
        recs.append(("Begin", f"bereq {vxid - 1} fetch"))
        recs.append(("VCL_use", "boot"))
        recs.append(("Timestamp", _ts(rng, t0, "Start")))
        recs.append(("BereqMethod", "GET"))
        recs.append(("BereqURL", url))
        recs.append(("BereqProtocol", "HTTP/1.1"))
        recs.append(("BereqHeader", f"Host: {host}"))
        recs.append(("BereqHeader", f"X-Varnish: {vxid}"))
        recs += [("VCL_call", "BACKEND_FETCH"), ("VCL_return", "fetch")]
        recs.append(("BackendOpen", f"{rng.randint(20, 40)} {rng.choice(['default', 'boot.default', 'app1', 'api_be'])} "
                                    f"{fake.ip(rng)} {rng.choice([80, 8080, 3000])} {fake.ip(rng)} {rng.randint(30000, 60000)} "
                                    + rng.choice(["connect", "reuse"])))
        recs.append(("Timestamp", _ts(rng, t0, "Bereq")))
        recs.append(("Timestamp", _ts(rng, t0, "Beresp")))
        recs.append(("BerespProtocol", "HTTP/1.1"))
        recs.append(("BerespStatus", status))
        recs.append(("BerespReason", reason))
        recs.append(("BerespHeader", f"Date: {fake.date(rng, 'rfc')}"))
        recs.append(("BerespHeader", "Server: " + rng.choice(["nginx", "Apache", "gunicorn", "Kestrel"])))
        recs.append(("TTL", f"RFC {rng.choice([120, 3600, -1])} 10 0 {int(t0)} {int(t0)} {int(t0)} 0 0 cacheable"))
        recs += [("VCL_call", "BACKEND_RESPONSE"), ("VCL_return", "deliver")]
        recs.append(("Storage", rng.choice(["malloc s0", "file s0", "malloc Transient"])))
        recs.append(("Fetch_Body", "3 length stream"))
        recs.append(("BackendClose", f"{rng.randint(20, 40)} default recycle"))
        recs.append(("Timestamp", _ts(rng, t0, "BerespBody")))
        recs.append(("Length", str(rng.randint(0, 90000))))
        recs.append(("BereqAcct", " ".join(str(rng.randint(0, 9000)) for _ in range(6))))
        recs.append(("End", None))
    for tag, val in recs:
        text = f"-   {tag.ljust(pad)} {val or ''}".rstrip()
        d.line(text, "row", [tag, val])


def generate(rng):
    d = Doc()
    pad = rng.choice([14, 14, 15])
    vxid = rng.choice([2, 32770, rng.randint(3, 9_000_000)])
    t0 = rng.uniform(1.6e9, 1.8e9)
    for i in range(rng.randint(1, 3)):
        kinds = ["BeReq", "Request"] if rng.random() < 0.4 else ["Request"]
        for k in kinds:
            _block(d, rng, k, vxid + (1 if k == "BeReq" else 0), t0, pad)
            d.blank()
        vxid += rng.randint(2, 40)
        t0 += rng.uniform(0, 5)
    return d
