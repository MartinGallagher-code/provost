"""MIT Kerberos `klist` (credential cache, optionally -f / -e) and `klist -k`
(keytab): cache/keytab kv lines, an aligned ticket table, and tab-indented
`renew until` / `Flags:` / `Etype` continuation lines."""
from lib import Doc, fake

TOOL = "klist"

ENCTYPES = ["aes256-cts-hmac-sha1-96", "aes128-cts-hmac-sha1-96", "aes256-cts-hmac-sha384-192",
            "aes128-cts-hmac-sha256-128", "arcfour-hmac", "camellia256-cts-cmac"]
SERVICES = ["HTTP", "host", "cifs", "ldap", "nfs", "imap", "postgres", "HTTP", "host"]


def realm(rng):
    return rng.choice(["EXAMPLE.COM", "CORP.EXAMPLE.COM", "AD.LAN", "IPA.INTERNAL", "ACME.ORG", "LAB.TEST"])


def stamp(rng, y4, base):
    m, dd, H, M, S = base
    y = "2026" if y4 else "26"
    return f"{m:02d}/{dd:02d}/{y} {H:02d}:{M:02d}:{S:02d}"


def rand_base(rng):
    return (rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59))


def keytab(rng, d):
    r = realm(rng)
    path = rng.choice(["/etc/krb5.keytab", "/etc/httpd/http.keytab", f"/var/lib/{fake.word(rng)}/service.keytab"])
    d.kv("Keytab name", f"FILE:{path}")
    ts = rng.random() < .6
    enc = rng.random() < .4
    host = fake.host(rng).split(".")[0] + "." + r.lower()
    rows = []
    y4 = rng.random() < .5
    for _ in range(rng.randint(1, 4)):
        svc = rng.choice(SERVICES + ["HOST"])
        kv = str(rng.randint(1, 12))
        princ = rng.choice([f"{svc}/{host}@{r}", f"{host.split('.')[0].upper()}$@{r}"])
        t = stamp(rng, y4, rand_base(rng)) if ts else None
        for e in rng.sample(ENCTYPES, rng.randint(1, 3)) if enc else [None]:
            row = [kv] + ([t] if ts else []) + [princ] + ([f"({e})"] if enc else [])
            rows.append(row)
    hdr = ["KVNO"] + (["Timestamp"] if ts else []) + ["Principal"] + ([None] if enc else [])
    tw = max(len(r[1]) for r in rows) if ts else 0
    d.line("KVNO" + (" " + "Timestamp".ljust(tw) if ts else "") + " Principal", "header", hdr)
    d.skip("----" + (" " + "-" * tw if ts else "") + " " + "-" * rng.choice([54, 76, 78]))
    for r in rows:
        text = r[0].rjust(4) + (" " + r[1] if ts else "") + " " + " ".join(r[1 + ts:]) + (" " if enc else "")
        d.line(text, "row", r)
    return d


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        return keytab(rng, d)
    r = realm(rng)
    uid = rng.randint(1000, 60000)
    user = rng.choice(fake.USERS[1:6] + ["jsmith", "m.garcia", "svc-backup", "admin"])
    cache = rng.choice([f"FILE:/tmp/krb5cc_{uid}", f"KCM:{uid}", f"KCM:{uid}:{rng.randint(10000, 99999)}",
                        f"KEYRING:persistent:{uid}:{uid}", f"DIR::/run/user/{uid}/krb5cc/tkt"])
    d.kv("Ticket cache", cache)
    d.kv("Default principal", f"{user}@{r}")
    d.blank()
    y4 = rng.random() < .5
    flags = rng.random() < .35
    etype = rng.random() < .2
    start = rand_base(rng)
    tkts = [f"krbtgt/{r}@{r}"]
    for _ in range(rng.randint(0, 5)):
        h = fake.host(rng).split(".")[0] + "." + r.lower()
        tkts.append(f"{rng.choice(SERVICES)}/{h}@{r}")
    if rng.random() < .2:
        other = realm(rng)
        if other != r:
            tkts.insert(1, f"krbtgt/{other}@{r}")
    w = len(stamp(rng, y4, start))
    d.line("Valid starting".ljust(w) + "  " + "Expires".ljust(w) + "  " + "Service principal", "header",
           ["Valid starting", "Expires", "Service principal"])
    m, dd, H, M, S = start
    life = rng.choice([8, 10, 10, 24])
    end = (m, dd + (H + life) // 24, (H + life) % 24, M, S)
    renew = (m, min(dd + 7, 28), H, M, S)
    for i, t in enumerate(tkts):
        s = stamp(rng, y4, start if i == 0 else (m, dd, H, (M + i * 3) % 60, rng.randint(0, 59)))
        e = stamp(rng, y4, end)
        d.line(f"{s}  {e}  {t}", "row", [s, e, t])
        has_renew = rng.random() < .7
        fl = "".join(c for c in "FfPpDdRIAOH" if rng.random() < .3) or "A"
        if i == 0:
            fl = "FRIA" if rng.random() < .6 else "FRIAT"
        rn = stamp(rng, y4, renew)
        if has_renew and flags:
            d.line(f"\trenew until {rn}, Flags: {fl}", "cont", ["renew until", rn, "Flags", fl])
        elif has_renew:
            d.line(f"\trenew until {rn}", "cont", ["renew until", rn])
        elif flags:
            d.line(f"\tFlags: {fl}", "cont", ["Flags", fl])
        if etype:
            a, b = rng.choice(ENCTYPES[:4]), rng.choice(ENCTYPES[:4])
            d.line(f"\tEtype (skey, tkt): {a}, {b} ", "cont", ["Etype (skey, tkt)", a, b])
    return d
