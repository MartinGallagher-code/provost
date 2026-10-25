"""realmd `realm list` / `realm discover`: one heading line per realm, then
two-space-indented `key: value` properties (keys may repeat)."""
from lib import Doc, fake

TOOL = "realm"

DOMS = ["example.com", "corp.example.org", "ad.contoso.com", "lab.local", "ipa.example.test", "ads.uni.edu",
        "office.acme.co.uk", "dc.internal"]


def generate(rng):
    d = Doc()
    discover = rng.random() < 0.3
    for i, dom in enumerate(rng.sample(DOMS, rng.choice([1, 1, 1, 2, 3]))):
        if i:
            d.blank() if rng.random() < .3 else None
        ipa = "ipa" in dom or rng.random() < .15
        d.section(dom)
        pairs = [("type", "kerberos"), ("realm-name", dom.upper()), ("domain-name", dom)]
        joined = not discover or rng.random() < .3
        pairs.append(("configured", rng.choice(["kerberos-member"]) if joined else "no"))
        pairs.append(("server-software", "ipa" if ipa else "active-directory"))
        pairs.append(("client-software", rng.choice(["sssd", "sssd", "winbind"])))
        pkgs = (["ipa-client", "oddjob", "oddjob-mkhomedir", "sssd"] if ipa else
                rng.choice([["oddjob", "oddjob-mkhomedir", "sssd", "adcli", "samba-common-tools"],
                            ["sssd-tools", "sssd", "libnss-sss", "libpam-sss", "adcli", "samba-common-bin"],
                            ["oddjob", "oddjob-mkhomedir", "sssd", "adcli", "samba-common"]]))
        for p in pkgs:
            pairs.append(("required-package", p))
        if joined:
            pairs.append(("login-formats", rng.choice(["%U@" + dom, "%U", dom.split(".")[0].upper() + "\\%U"])))
            pol = rng.choice(["allow-realm-logins", "allow-permitted-logins", "deny-any-login", "allow-any-login"])
            pairs.append(("login-policy", pol))
            if pol == "allow-permitted-logins":
                if rng.random() < .8:
                    users = ", ".join(f"{u}@{dom}" for u in rng.sample(fake.USERS[:8], rng.randint(1, 4)))
                    pairs.append(("permitted-logins", users))
                if rng.random() < .6:
                    grps = ", ".join(rng.sample(["Domain Admins", "linux-admins", "developers", "sysops",
                                                 "Remote Desktop Users", "dba"], rng.randint(1, 3)))
                    pairs.append(("permitted-groups", grps))
        for k, v in pairs:
            d.kv(k, v, indent="  ")
    return d
