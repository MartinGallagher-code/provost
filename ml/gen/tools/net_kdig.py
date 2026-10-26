"""Knot DNS `kdig`: `;;`-prefixed header lines of `key: value` pairs, named
sections (QUESTION, ANSWER, AUTHORITY, ...) holding tab-separated resource
records, and a Received/Time/From footer."""
from lib import Doc, fake

TOOL = "kdig"


def _owner(name, rng):
    return name.ljust(rng.choice([20, 24])) if len(name) < 20 else name


def _rdata(rng, rtype, zone):
    return {
        "A": lambda: fake.ip(rng),
        "AAAA": lambda: f"2606:2800:{rng.randint(0, 65535):x}:{rng.randint(0, 65535):x}::{rng.randint(1, 255):x}",
        "MX": lambda: f"{rng.choice([0, 10, 20, 50])} {rng.choice(['mail', 'mx1', 'mx2', 'smtp'])}.{zone}",
        "NS": lambda: f"{rng.choice(['ns1', 'ns2', 'a.iana-servers', 'dns1'])}.{zone}",
        "TXT": lambda: rng.choice(['"v=spf1 -all"', f'"v=spf1 include:_spf.{zone} ~all"',
                                   f'"google-site-verification={fake.token(rng, 24)}"']),
        "CNAME": lambda: f"{fake.word(rng)}.{rng.choice(['cdn.cloudflare.net.', 'edgekey.net.', zone])}",
        "CAA": lambda: f'0 issue "{rng.choice(["letsencrypt.org", "digicert.com"])}"',
    }[rtype]()


def generate(rng):
    d = Doc()
    zone = rng.choice(["example.com.", "example.org.", "knot-dns.cz.", f"{fake.word(rng)}.net.", "nic.cz."])
    qname = rng.choice([zone, f"www.{zone}", f"{fake.word(rng)}.{zone}"])
    qtype = rng.choice(["A", "A", "AAAA", "MX", "NS", "TXT", "CAA"])
    status = rng.choice(["NOERROR"] * 6 + ["NXDOMAIN", "SERVFAIL"])
    qid = str(rng.randint(1, 65535))
    d.line(f";; ->>HEADER<<- opcode: QUERY; status: {status}; id: {qid}", "row",
           ["opcode", "QUERY", "status", status, "id", qid])
    nans = 0 if status != "NOERROR" else rng.randint(1, 6)
    nauth = 1 if status == "NXDOMAIN" else rng.choice([0, 0, 2])
    edns = rng.random() < .75
    flags = rng.choice(["qr rd ra", "qr rd ra", "qr aa rd", "qr rd ra ad", "qr aa"])
    counts = ["QUERY", "1", "ANSWER", str(nans), "AUTHORITY", str(nauth), "ADDITIONAL", str(int(edns))]
    d.line(f";; Flags: {flags}; QUERY: 1; ANSWER: {nans}; AUTHORITY: {nauth}; ADDITIONAL: {int(edns)}", "row",
           ["Flags", flags] + counts)
    d.blank()
    if edns:
        d.section(";; EDNS PSEUDOSECTION:", "EDNS PSEUDOSECTION")
        ef = rng.choice(["", "do"])
        size = rng.choice(["1232", "1232", "4096", "512"])
        text = f";; Version: 0; flags: {ef}; UDP size: {size} B; ext-rcode: NOERROR"
        d.line(text, "row", ["Version", "0", "flags", ef or None, "UDP size", f"{size} B", "ext-rcode", "NOERROR"])
        if rng.random() < .3:
            pad = str(rng.randint(100, 400))
            d.line(f";; PADDING: {pad} B", "kv", ["PADDING", f"{pad} B"])
        d.blank()
    d.section(";; QUESTION SECTION:", "QUESTION SECTION")
    d.line(f";; {_owner(qname, rng)}\t\tIN\t{qtype}", "row", [qname, "IN", qtype])
    if nans:
        d.blank()
        d.section(";; ANSWER SECTION:", "ANSWER SECTION")
        ttl = rng.choice([60, 300, 3600, 86400, rng.randint(1, 86400)])
        if qtype in ("A", "AAAA") and rng.random() < .3:
            target = f"{fake.word(rng)}.cdn.cloudflare.net."
            d.line(f"{_owner(qname, rng)}\t{ttl}\tIN\tCNAME\t{target}", "row", [qname, str(ttl), "IN", "CNAME", target])
            nans -= 1
            owner = target
        else:
            owner = qname
        for _ in range(nans):
            rd = _rdata(rng, qtype, zone)
            d.line(f"{_owner(owner, rng)}\t{ttl}\tIN\t{qtype}\t{rd}", "row", [owner, str(ttl), "IN", qtype, rd])
    if nauth:
        d.blank()
        d.section(";; AUTHORITY SECTION:", "AUTHORITY SECTION")
        for _ in range(nauth):
            if status == "NXDOMAIN":
                rd = f"ns1.{zone} hostmaster.{zone} {rng.randint(2020010100, 2026123199)} 7200 3600 1209600 3600"
                rt = "SOA"
            else:
                rd, rt = _rdata(rng, "NS", zone), "NS"
            ttl = str(rng.choice([3600, 86400, 900]))
            d.line(f"{_owner(zone, rng)}\t{ttl}\tIN\t{rt}\t{rd}", "row", [zone, ttl, "IN", rt, rd])
    d.blank()
    rec = f"{rng.randint(40, 600)} B"
    d.line(f";; Received {rec}", "kv", ["Received", rec])
    ts = fake.date(rng, "datetime") + " " + rng.choice(["UTC", "CET", "CEST", "EST", "PDT"])
    d.line(f";; Time {ts}", "kv", ["Time", ts])
    server = rng.choice(["1.1.1.1", "8.8.8.8", "9.9.9.9", "127.0.0.53", fake.ip(rng), "2606:4700:4700::1111"])
    proto = rng.choice(["UDP", "UDP", "TCP", "TLS", "HTTPS", "QUIC"])
    port = {"UDP": "53", "TCP": "53", "TLS": "853", "HTTPS": "443", "QUIC": "853"}[proto]
    src = f"{server}@{port}({proto})"
    took = f"in {rng.uniform(0.1, 300):.1f} ms"
    d.line(f";; From {src} {took}", "kv", ["From", src, took])
    return d
