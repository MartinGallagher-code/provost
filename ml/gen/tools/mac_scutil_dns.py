"""macOS `scutil --dns`: `DNS configuration` headings, `resolver #N` sub-
headings and ` key : value` lines (short keys padded to 8)."""
from lib import Doc, fake

TOOL = "scutil-dns"

REACH_OK = "0x00020002 (Reachable,Directly Reachable Address)"
REACH_NO = "0x00000000 (Not Reachable)"


def kv(d, k, v):
    d.line(f"  {k:<8} : {v}", "kv", [k, v])


def generate(rng):
    d = Doc()
    ifs = [("en0", rng.randint(4, 15))] + ([("utun3", rng.randint(16, 30))] if rng.random() < .4 else [])
    nameservers = [fake.ip(rng) for _ in range(rng.randint(1, 3))]
    if rng.random() < .3:
        nameservers.append(fake.ip(rng, v6=True))
    search = rng.sample(["lan", "home.arpa", "corp.example.com", "local.domain", "eng.internal"], rng.randint(0, 2))

    def main_resolver(scoped):
        for i, s in enumerate(search):
            kv(d, f"search domain[{i}]", s)
        for i, ns in enumerate(nameservers):
            kv(d, f"nameserver[{i}]", ns)
        ifn, idx = ifs[0]
        kv(d, "if_index", f"{idx} ({ifn})")
        kv(d, "flags", "Scoped, Request A records" + (", Request AAAA records" if len(nameservers) > 2 else "") if scoped
           else "Request A records" + (", Request AAAA records" if len(nameservers) > 2 else ""))
        kv(d, "reach", REACH_OK)
        if rng.random() < .3:
            kv(d, "order", str(rng.choice([100000, 200000])))

    d.section("DNS configuration")
    d.blank()
    d.section("resolver #1")
    main_resolver(False)
    d.blank()
    n = 2
    extras = [("local", "mdns", 300000)] + [(z, "mdns", o) for z, o in
              (("254.169.in-addr.arpa", 300200), ("8.e.f.ip6.arpa", 300400), ("9.e.f.ip6.arpa", 300600),
               ("a.e.f.ip6.arpa", 300800), ("b.e.f.ip6.arpa", 301000))]
    extras = extras[:rng.randint(1, len(extras))]
    if rng.random() < .3:
        extras.insert(0, (rng.choice(["corp.example.com", "vpn.internal", "tailnet-1234.ts.net"]), None, None))
    for dom, opt, order in extras:
        d.section(f"resolver #{n}")
        n += 1
        kv(d, "domain", dom)
        if opt:
            kv(d, "options", opt)
            kv(d, "timeout", "5")
            kv(d, "flags", "Request A records")
            kv(d, "reach", REACH_NO)
            kv(d, "order", str(order))
        else:
            kv(d, "nameserver[0]", fake.ip(rng))
            kv(d, "if_index", f"{ifs[-1][1]} ({ifs[-1][0]})")
            kv(d, "flags", "Supplemental, Request A records")
            kv(d, "reach", REACH_OK)
            kv(d, "order", "102400")
        d.blank()
    if rng.random() < .85:
        d.section("DNS configuration (for scoped queries)")
        d.blank()
        d.section("resolver #1")
        main_resolver(True)
        d.blank()
    return d
