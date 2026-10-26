"""Kamailio `kamcmd ul.dump`: kamcmd's nested-brace pretty print, one
`Key: value` per line, tab-indented by depth, `Name: {` openers, `}` closers."""
from lib import Doc, fake

TOOL = "kamcmd-ul.dump"

UAS = ["Grandstream GXP1625 1.0.4.130", "Yealink SIP-T46S 66.86.0.15", "Linphone/5.2.0 (belle-sip/5.2.0)",
       "Zoiper rv2.10.19.5", "PolycomVVX-VVX_411-UA/6.4.3.5018", "Cisco/SPA504G-7.6.2c", "MicroSIP/3.21.3",
       "Obihai-OBi202-3.2.2"]


class Tree:
    def __init__(self, d):
        self.d, self.depth = d, 0

    def open(self, name):
        self.d.line("\t" * self.depth + f"{name}: {{", "section", [name])
        self.depth += 1

    def close(self):
        self.depth -= 1
        self.d.skip("\t" * self.depth + "}")

    def kv(self, k, v):
        self.d.line("\t" * self.depth + f"{k}: {v}", "kv", [k, v])


def contact(t, rng, aor, ts, srv):
    t.open("Contact")
    ip = fake.ip(rng)
    port = rng.choice(["5060", "5062", str(rng.randint(1024, 65535))])
    tr = rng.choice(["udp", "tcp", "tls", "ws"])
    t.kv("Address", f"sip:{aor}@{ip}:{port}" + (f";transport={tr}" if tr != "udp" or rng.random() < .3 else "")
         + (";rinstance=" + fake.hexid(rng, 16) if rng.random() < .3 else ""))
    t.kv("Expires", rng.choice([str(rng.randint(1, 3600)), "permanent", "deleted"]) if rng.random() < .2
         else str(rng.randint(1, 3600)))
    t.kv("Q", rng.choice(["-1.000000", "1.000000", "0.500000"]))
    t.kv("Call-ID", rng.choice([fake.uuid(rng), fake.token(rng, 22) + "..", f"{fake.hexid(rng, 8)}@{ip}"]))
    t.kv("CSeq", str(rng.randint(1, 9999)))
    t.kv("User-Agent", rng.choice(UAS))
    t.kv("Received", rng.choice(["[not set]", f"sip:{fake.ip(rng)}:{rng.randint(1024, 65535)}"]))
    t.kv("Path", rng.choice(["[not set]", "[not set]", f"<sip:{fake.ip(rng)};lr;received=sip:{ip}:{port}>"]))
    t.kv("State", rng.choice(["CS_NEW", "CS_SYNC", "CS_DIRTY"]))
    t.kv("Flags", str(rng.choice([0, 0, 1, 2])))
    t.kv("CFlags", str(rng.choice([0, 0, 64, 192])))
    t.kv("Socket", f"{tr if tr != 'ws' else 'tcp'}:{srv}:{5060 if tr in ('udp', 'tcp') else 5061}")
    t.kv("Methods", rng.choice(["5087", "4294967295", "8159", "3999"]))
    t.kv("Ruid", f"uloc-{fake.hexid(rng, 8)}-{fake.hexid(rng, 4)}-{rng.randint(1, 99)}")
    t.kv("Instance", rng.choice(["[not set]", "[not set]", f"<urn:uuid:{fake.uuid(rng)}>"]))
    t.kv("Reg-Id", str(rng.choice([0, 0, 1])))
    t.kv("Server-Id", "0")
    t.kv("Tcpconn-Id", str(rng.choice([-1, rng.randint(1, 900)])))
    t.kv("Keepalive", str(rng.choice([0, 1])))
    t.kv("Last-Keepalive", str(ts - rng.randint(0, 600)))
    if rng.random() < .6:
        t.kv("KA-Roundtrip", str(rng.choice([0, rng.randint(1000, 90000)])))
    t.kv("Last-Modified", str(ts - rng.randint(0, 3600)))
    t.close()


def generate(rng):
    d = Doc()
    t = Tree(d)
    ts = rng.randint(1690000000, 1790000000)
    srv = fake.ip(rng)
    d.skip("{")
    t.depth = 1
    t.open("Domains")
    tables = ["location"] + (["location_pbx"] if rng.random() < .2 else [])
    for tbl in tables:
        t.open("Domain")
        t.kv("Domain", tbl)
        t.kv("Size", rng.choice(["1024", "4096", "16384", "512"]))
        t.open("AoRs")
        n = rng.randint(0, 4)
        base = rng.choice([100, 1000, 2000, 4000])
        for a in sorted(rng.sample(range(base, base + 99), n)):
            aor = str(a) if rng.random() < .7 else f"{a}@{rng.choice(['pbx.example.com', srv, 'voip.lan'])}"
            t.open("Info")
            t.kv("AoR", aor)
            t.kv("HashID", str(rng.randint(10 ** 8, 4294967295)))
            t.open("Contacts")
            for _ in range(rng.choice([1, 1, 1, 2])):
                contact(t, rng, aor.split("@")[0], ts, srv)
            t.close()
            t.close()
        t.close()
        t.open("Stats")
        t.kv("Records", str(n))
        t.kv("Max-Slots", str(rng.randint(0, 2) if n else 0))
        t.close()
        t.close()
    t.close()
    d.skip("}")
    return d
