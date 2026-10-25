"""realmd `realm list` / `realm discover`: each realm's name flush left,
then two-space-indented `key: value` lines (repeated required-package keys,
comma-separated permitted logins)."""
from lib import Doc, fake

TOOL = "realm"


def one(d, rng, domain, configured):
    ad = rng.random() < .7
    pairs = [("type", "kerberos"), ("realm-name", domain.upper()), ("domain-name", domain)]
    if configured:
        pairs.append(("configured", "kerberos-member"))
    else:
        pairs.append(("configured", "no"))
    pairs.append(("server-software", "active-directory" if ad else "ipa"))
    pairs.append(("client-software", rng.choice(["sssd", "sssd", "winbind"])))
    pkgs = (["oddjob", "oddjob-mkhomedir", "sssd", "adcli", "samba-common-tools"] if ad
            else ["ipa-client", "oddjob", "oddjob-mkhomedir", "sssd"])
    if rng.random() < .3:
        pkgs = ["sssd-tools", "sssd", "libnss-sss", "libpam-sss", "adcli", "samba-common-bin"]
    for p in pkgs:
        pairs.append(("required-package", p))
    if configured:
        pairs.append(("login-formats", rng.choice(["%U@" + domain, "%U", domain.split(".")[0].upper() + "\\%U"])))
        pol = rng.choice(["allow-realm-logins", "allow-permitted-logins", "deny-any-login"])
        pairs.append(("login-policy", pol))
        if pol == "allow-permitted-logins" or rng.random() < .3:
            users = rng.sample(["alice", "bob", "carol", "dave", "erin", "jsmith", "admin"], rng.randint(1, 4))
            pairs.append(("permitted-logins", ", ".join(f"{u}@{domain}" for u in users)))
            if rng.random() < .6:
                grps = rng.sample(["Domain Admins", "linux-admins", "sre", "Help Desk", "db_ops"], rng.randint(1, 3))
                pairs.append(("permitted-groups", ", ".join(grps)))
    d.section(domain, domain)
    for k, v in pairs:
        d.line(f"  {k}: {v}", "kv", [k, v])


def generate(rng):
    d = Doc()
    n = rng.choice([1, 1, 1, 2, 3])
    doms = rng.sample(["example.com", "corp.example.com", "ad.acme.org", "ipa.internal", "lab.test",
                       "contoso.lan", "eu.globex.net", "idm.initech.io"], n)
    for i, dom in enumerate(doms):
        one(d, rng, dom, configured=(i == 0 and rng.random() < .85) or rng.random() < .3)
    return d
