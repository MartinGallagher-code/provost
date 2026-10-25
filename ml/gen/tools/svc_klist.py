"""Kerberos `klist`: MIT ticket cache (kv banner + `Valid starting` table with
indented `renew until`/flags continuation lines), Heimdal variant, or
`klist -k` keytab listing."""
from lib import Doc, fake

TOOL = "klist"

REALMS = ["EXAMPLE.COM", "CORP.EXAMPLE.ORG", "AD.CONTOSO.COM", "ATHENA.MIT.EDU", "LAB.LOCAL"]
SERVICES = ["HTTP/{h}", "host/{h}", "cifs/{h}", "ldap/{h}", "nfs/{h}", "imap/{h}", "postgres/{h}", "HTTP/{h}"]
ETYPES = ["aes256-cts-hmac-sha1-96", "aes128-cts-hmac-sha1-96", "aes256-cts-hmac-sha384-192",
          "arcfour-hmac", "des3-cbc-sha1"]


def stamp(rng, fmt, y, m, dd, H, M, S):
    mons = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    return {"us4": f"{m:02d}/{dd:02d}/{y} {H:02d}:{M:02d}:{S:02d}",
            "us2": f"{m:02d}/{dd:02d}/{y % 100:02d} {H:02d}:{M:02d}:{S:02d}",
            "iso": f"{y}-{m:02d}-{dd:02d} {H:02d}:{M:02d}:{S:02d}",
            "eu": f"{dd:02d}.{m:02d}.{y} {H:02d}:{M:02d}:{S:02d}",
            "heim": f"{mons[m - 1]} {dd:2d} {H:02d}:{M:02d}:{S:02d} {y}"}[fmt]


def mit(d, rng, realm, user):
    fmt = rng.choice(["us4", "us4", "us2", "iso", "eu"])
    d.kv("Ticket cache", rng.choice([f"FILE:/tmp/krb5cc_{rng.randint(1000, 1999)}",
                                     f"KCM:{rng.randint(1000, 1999)}", f"KEYRING:persistent:{rng.randint(1000, 1999)}:krb_ccache_{fake.token(rng, 7)}",
                                     f"FILE:/tmp/krb5cc_{rng.randint(1000, 1999)}_{fake.token(rng, 6)}"]))
    d.kv("Default principal", f"{user}@{realm}")
    d.blank()
    flags = rng.random() < .25
    enc = rng.random() < .2
    hdr = ["Valid starting", "Expires", "Service principal"]
    y, m, dd = rng.randint(2020, 2026), rng.randint(1, 12), rng.randint(1, 27)
    H, M, S = rng.randint(0, 13), rng.randint(0, 59), rng.randint(0, 59)
    a = stamp(rng, fmt, y, m, dd, H, M, S)
    b = stamp(rng, fmt, y, m, dd, H + 10, M, S)
    w = len(a) + 2
    d.line(hdr[0].ljust(w) + hdr[1].ljust(w) + hdr[2], "header", hdr)
    hosts = [fake.host(rng) for _ in range(6)]
    princs = [f"krbtgt/{realm}@{realm}"] + [rng.choice(SERVICES).format(h=rng.choice(hosts)) + "@" + realm
                                            for _ in range(rng.randint(0, 7))]
    if rng.random() < .2:
        princs.append(f"krbtgt/{rng.choice(REALMS)}@{realm}")
    renew = stamp(rng, fmt, y, m, min(dd + 7, 28), H, M, S)
    for i, p in enumerate(princs):
        st = a if i == 0 else stamp(rng, fmt, y, m, dd, H + rng.randint(0, 9), rng.randint(0, 59), rng.randint(0, 59))
        d.line(st.ljust(w) + b.ljust(w) + p, "row", [st, b, p])
        if (i == 0 or rng.random() < .4) and rng.random() < .85:
            d.line(f"\trenew until {renew}", "cont", [f"renew until {renew}"])
        if flags:
            fl = rng.choice(["FRIA", "FRIT", "FRA", "FAT", "FRIAO"]) if i == 0 else rng.choice(["FRT", "FAT", "FRAO"])
            d.line(f"\tFlags: {fl}", "cont", [f"Flags: {fl}"])
        if enc:
            e1, e2 = rng.choice(ETYPES), rng.choice(ETYPES)
            d.line(f"\tEtype (skey, tkt): {e1}, {e2} ", "cont", [f"Etype (skey, tkt): {e1}, {e2}"])


def heimdal(d, rng, realm, user):
    d.kv("Credentials cache", f"FILE:/tmp/krb5cc_{rng.randint(1000, 1999)}")
    d.kv("Principal", f"{user}@{realm}", indent=" " * 8)
    if rng.random() < .5:
        d.kv("Cache version", "4", indent=" " * 4)
    d.blank()
    hdr = ["Issued", "Expires", "Principal"]
    y, m, dd = rng.randint(2020, 2026), rng.randint(1, 12), rng.randint(1, 27)
    rows = []
    for i in range(rng.randint(1, 6)):
        H, M, S = rng.randint(0, 13), rng.randint(0, 59), rng.randint(0, 59)
        p = f"krbtgt/{realm}@{realm}" if i == 0 else rng.choice(SERVICES).format(h=fake.host(rng)) + "@" + realm
        exp = stamp(rng, "heim", y, m, dd, H + 10, M, S)
        if rng.random() < .1:
            exp = ">>>Expired<<<"
        rows.append([stamp(rng, "heim", y, m, dd, H, M, S), exp, p])
    d.table(hdr, rows, indent="", gap=2)


def keytab(d, rng, realm, user):
    d.kv("Keytab name", rng.choice(["FILE:/etc/krb5.keytab", "FILE:/etc/httpd/http.keytab", "FILE:/tmp/svc.keytab"]))
    ts = rng.random() < .4
    en = rng.random() < .5
    hdr = ["KVNO"] + (["Timestamp"] if ts else []) + ["Principal"]
    rule = "---- " + ("------------------- " if ts else "") + "-" * rng.choice([66, 74, 78])
    d.line(" ".join(h.ljust(19) if h == "Timestamp" else h for h in hdr), "header", hdr)
    d.skip(rule)
    h = fake.host(rng).split(".")[0].upper()
    names = [f"{h}$@{realm}", f"host/{h.lower()}.{realm.lower()}@{realm}", f"HTTP/{h.lower()}.{realm.lower()}@{realm}",
             f"nfs/{h.lower()}.{realm.lower()}@{realm}", f"RestrictedKrbHost/{h}@{realm}"]
    kv = str(rng.randint(1, 30))
    dt = stamp(rng, rng.choice(["us4", "us2"]), rng.randint(2019, 2026), rng.randint(1, 12), rng.randint(1, 28),
               rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59))
    for nm in rng.sample(names, rng.randint(1, len(names))):
        for et in (rng.sample(ETYPES[:4], rng.randint(1, 3)) if en else [None]):
            p = nm + (f" ({et})" if et else "")
            cells = [kv] + ([dt] if ts else []) + [p]
            d.line(f"{kv:>4} " + (dt.ljust(19) + " " if ts else "") + p, "row", cells)


def generate(rng):
    d = Doc()
    realm = rng.choice(REALMS)
    user = rng.choice(fake.USERS[:6] + ["jsmith", "admin"])
    r = rng.random()
    if r < 0.6:
        mit(d, rng, realm, user)
    elif r < 0.8:
        heimdal(d, rng, realm, user)
    else:
        keytab(d, rng, realm, user)
    return d
