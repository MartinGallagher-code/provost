"""FreeSWITCH `fs_cli -x 'sofia status'`: right-aligned name and data columns
joined by tabs, `====` rules, and a `N profiles N alias` footer."""
from lib import Doc, fake

TOOL = "fs_cli-x-sofia-status"

GW_STATES = ["REGED", "REGED", "NOREG", "UNREGED", "TRYING", "FAIL_WAIT", "FAILED", "REGISTER"]
PROVIDERS = ["sip.flowroute.com", "voip.ms", "sip.telnyx.com", "sip.callcentric.net", "trunk.example.net",
             "gw1.carrier-upstream.example.org", "sipgate.co.uk"]


def generate(rng):
    d = Doc()
    ip = fake.ip(rng)
    entries = []
    profiles = ["internal", "external"] + [p for p in ["internal-ipv6", "external-ipv6", "wss", "carrier"]
                                            if rng.random() < .25]
    for p in profiles:
        port = {"internal": 5060, "external": 5080}.get(p, rng.choice([5070, 5090, 7443, 5062]))
        host = fake.ip(rng, v6=True) if p.endswith("ipv6") else ip
        url = f"sip:mod_sofia@[{host}]:{port}" if p.endswith("ipv6") else f"sip:mod_sofia@{host}:{port}"
        state = (f"RUNNING ({rng.randint(0, 40)})" if rng.random() < .9 else "DOWN (0)")
        entries.append((p, "profile", url, state))
        if rng.random() < .3:
            entries.append((p, "profile", url.replace(str(port), str(port + 1)), state + " (TLS)"))
        if p.startswith("external"):
            for prov in rng.sample(PROVIDERS, rng.randint(0, 3)):
                gw = prov.split(".")[0] if rng.random() < .5 else prov
                user = rng.choice(["joeuser", fake.num(rng, 100000, 9999999), "trunk01"])
                entries.append((f"{p}::{gw}", "gateway", f"sip:{user}@{prov}", rng.choice(GW_STATES)))
    aliases = 0
    if rng.random() < .7:
        entries.append((ip, "alias", "internal", "ALIASED"))
        aliases += 1
    rng.shuffle(entries)
    d.line("%25s\t%s\t  %40s\t%s" % ("Name", "   Type", "Data", "State"), "header", ["Name", "Type", "Data", "State"])
    rule = "=" * 97
    d.skip(rule)
    for name, typ, data, state in entries:
        d.line("%25s\t%s\t  %40s\t%s" % (name, typ, data, state), "row", [name, typ, data, state])
    d.skip(rule)
    np_ = sum(1 for e in entries if e[1] == "profile")
    d.skip(f"{np_} profile{'s' if np_ != 1 else ''} {aliases} alias{'es' if aliases != 1 else ''}")
    if rng.random() < .3:
        d.blank()
    return d
