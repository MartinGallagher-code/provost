"""SSSD `sssctl domain-status <domain>` (optionally preceded by
`sssctl domain-list`): an online-status kv line, an `Active servers:` kv
block, and `Discovered ... servers:` headings over `- host` lists."""
from lib import Doc, fake

TOOL = "sssctl"


def generate(rng):
    d = Doc()
    dom = rng.choice(["example.com", "corp.example.com", "ad.acme.org", "ipa.internal", "lab.test", "contoso.lan"])
    kind = rng.choice(["AD", "AD", "IPA", "LDAP"])
    if rng.random() < .3:
        doms = [dom] + [rng.choice(["implicit_files", "child." + dom, "trusted.example.net", "LOCAL"])
                        for _ in range(rng.randint(0, 2))]
        for x in dict.fromkeys(doms):
            d.line(x, "row", [x])
        d.blank()
    online = rng.random() < .8
    d.kv("Online status", "Online" if online else "Offline")
    d.blank()

    def hosts(prefix, n):
        return [f"{prefix}{i}.{dom}" for i in rng.sample(range(1, 9), n)]

    if kind == "AD":
        gcs, dcs = hosts(rng.choice(["dc", "ad", "gc"]), rng.randint(1, 4)), hosts(rng.choice(["dc", "ad"]), rng.randint(1, 5))
        active = [("AD Global Catalog", gcs[0] if online else "not connected"),
                  ("AD Domain Controller", dcs[0] if online else "not connected")]
        if rng.random() < .3:
            active.append(("Kerberos KDC", dcs[0] if online else "not connected"))
        lists = [("AD Global Catalog", gcs), ("AD Domain Controller", dcs)]
    elif kind == "IPA":
        ipas = hosts(rng.choice(["ipa", "idm", "freeipa"]), rng.randint(1, 4))
        active = [("IPA", ipas[0] if online else "not connected")]
        lists = [("IPA", ipas)]
    else:
        ls = hosts(rng.choice(["ldap", "ds", "389ds"]), rng.randint(1, 3))
        active = [("LDAP", ls[0] if online else "not connected")]
        lists = [("LDAP", ls)]
        if rng.random() < .5:
            active.append(("KERBEROS", ls[-1] if online else "not connected"))
    d.section("Active servers:")
    for k, v in active:
        d.kv(k, v)
    for name, hs in lists:
        d.blank()
        d.section(f"Discovered {name} servers:")
        for h in hs:
            d.line(f"- {h}", "row", [h])
    if rng.random() < .4:
        d.blank()
    return d
