"""Cilium `hubble observe`: one flow per line, `timestamp: src (identity)
-> dst (identity) observation-point VERDICT (summary)`, with the arrow
direction varying (->, <-, <>) and occasional DNS/HTTP summaries."""
from lib import Doc, fake

TOOL = "hubble-observe"


def generate(rng):
    d = Doc()
    mon = rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())
    day = rng.randint(1, 28)
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 50)
    ms = rng.randint(0, 900)
    ns = rng.choice(["default", "default", "kube-system", "prod", "monitoring", fake.word(rng)])
    pods = [f"{ns}/{fake.word(rng)}-{fake.hexid(rng, rng.choice([9, 10]))}-{fake.token(rng, 5)}" for _ in range(rng.randint(2, 4))]
    pods += [f"kube-system/coredns-{fake.hexid(rng, 10)}-{fake.token(rng, 5)}", f"{ns}/{fake.word(rng)}"]
    idents = {p: f"(ID:{rng.randint(1000, 65535)})" for p in pods}
    outside = [(fake.ip(rng), rng.choice(["(world)", "(host)", "(remote-node)", "(kube-apiserver)"])) for _ in range(2)]
    for _ in range(rng.randint(3, 18)):
        ms += rng.randint(0, 400)
        if ms >= 1000:
            ms -= 1000
            s = min(59, s + 1)
        ts = f"{mon} {day:2d} {h:02d}:{m:02d}:{s:02d}.{ms:03d}"
        a, b = rng.sample(pods, 2)
        srcp, dstp = rng.randint(32768, 60999), rng.choice([80, 8080, 443, 53, 5432, 6379, 9090])
        if rng.random() < .2:
            ip, ident = rng.choice(outside)
            src, sid = f"{ip}:{rng.randint(1024, 65535)}", ident
        else:
            src, sid = f"{a}:{srcp}", idents[a]
        dst, did = (f"{b}:{dstp}", idents[b])
        kind = rng.random()
        if kind < .45:
            arrow = rng.choice(["->", "<-"])
            obs = rng.choice(["to-endpoint", "to-stack", "to-overlay", "to-proxy", "from-proxy"])
            verdict = "FORWARDED"
            summ = rng.choice(["(TCP Flags: SYN)", "(TCP Flags: SYN, ACK)", "(TCP Flags: ACK)", "(TCP Flags: ACK, PSH)",
                               "(TCP Flags: ACK, FIN)", "(TCP Flags: RST)", "(UDP)"])
        elif kind < .6:
            arrow, obs, verdict = "->", rng.choice(["policy-verdict:none INGRESS", "policy-verdict:L3-L4 INGRESS",
                                                     "policy-verdict:L3-Only EGRESS", "policy-verdict:all EGRESS"]), \
                rng.choice(["ALLOWED", "ALLOWED", "DENIED"])
            summ = "(TCP Flags: SYN)"
        elif kind < .72:
            arrow, obs, verdict = "<>", rng.choice(["Policy denied", "Stale or unroutable IP", "Unsupported L3 protocol",
                                                     "Invalid source ip", "CT: Unknown L4 protocol"]), "DROPPED"
            summ = rng.choice(["(TCP Flags: SYN)", "(ICMPv4 EchoRequest)", "(UDP)", "(ICMPv6 RouterSolicitation)"])
        elif kind < .85:
            arrow, obs, verdict = rng.choice(["->", "<-"]), rng.choice(["dns-request proxy", "dns-response proxy"]), "FORWARDED"
            host = rng.choice(["api.github.com.", "kubernetes.default.svc.cluster.local.", f"{fake.word(rng)}.{ns}.svc.cluster.local.",
                               "registry-1.docker.io."])
            summ = f"(DNS Query {host} {rng.choice(['A', 'AAAA'])})" if "request" in obs else \
                f"(DNS Answer \"{fake.ip(rng)}\" TTL: {rng.choice([30, 60, 300])} (Proxy {host} A))"
            dst, did = f"kube-system/coredns-{fake.hexid(rng, 10)}-{fake.token(rng, 5)}:53", "(ID:" + str(rng.randint(1000, 9999)) + ")"
        else:
            arrow, obs, verdict = rng.choice(["->", "<-"]), rng.choice(["http-request", "http-response"]), "FORWARDED"
            url = f"http://{b.split('/')[1].split('-')[0]}.{ns}.svc.cluster.local/{rng.choice(['v1/request-landing', 'healthz', 'api/users', 'metrics'])}"
            meth = rng.choice(["GET", "POST", "PUT"])
            summ = f"(HTTP/1.1 {meth} {url})" if obs == "http-request" else \
                f"(HTTP/1.1 {rng.choice([200, 200, 201, 403, 404, 503])} {rng.randint(0, 900)}ms ({meth} {url}))"
        line = f"{ts}: {src} {sid} {arrow} {dst} {did} {obs} {verdict} {summ}"
        d.line(line, "row", [ts, src, sid, dst, did, obs, verdict, summ])
    if rng.random() < 0.2:
        d.line(f"EVENTS LOST: HUBBLE_RING_BUFFER CPU(0) {rng.randint(1, 900)}", "skip")
    return d
