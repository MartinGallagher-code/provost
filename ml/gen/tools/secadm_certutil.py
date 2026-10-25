"""NSS `certutil -L -d sql:...` (certificate nicknames with a two-line
`Trust Attributes` header, padded to column 61) or `certutil -K` (private
keys: `< N> type keyid nickname`, after a token banner)."""
from lib import Doc, fake

TOOL = "certutil"

NICKS = ["Server-Cert", "myCA", "Corporate Root CA", "Corporate Issuing CA 2", "ipa.internal IPA CA",
         "caSigningCert cert-pki-ca", "ocspSigningCert cert-pki-ca", "subsystemCert cert-pki-ca",
         "auditSigningCert cert-pki-ca", "Server-Cert cert-pki-ca", "IPA CA", "EXAMPLE.COM IPA CA",
         "Let's Encrypt R3", "ISRG Root X1", "DigiCert Global Root G2", "ldap-client", "smime-alice",
         "alice@example.com", "Firefox Code Signing", "web01.example.com", "vpn-gateway", "Builtin Object Token:GlobalSign"]


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        token = rng.choice(["NSS Certificate DB", "NSS FIPS 140-2 Certificate DB", "internal"])
        slot = rng.choice(["NSS User Private Key and Certificate Services", "NSS FIPS 140-2 User Private Key Services"])
        d.skip(f'certutil: Checking token "{token}" in slot "{slot}"')
        for i in range(rng.randint(1, 7)):
            kt = rng.choice(["rsa", "rsa", "rsa", "ec", "dsa"])
            kid = fake.hexid(rng, 40)
            nick = rng.choice([rng.choice(NICKS), "(orphan)"]) if rng.random() < .2 else rng.choice(NICKS)
            if nick != "(orphan)" and rng.random() < .4:
                nick = f"{token}:{nick}"
            d.line(f"<{i:2d}> {kt:<8} {kid}   {nick}", "row", [str(i), kt, kid, nick])
        return d
    d.blank()
    w = 60 if rng.random() < .85 else 64
    d.line("Certificate Nickname".ljust(w) + " Trust Attributes", "header", ["Certificate Nickname", "Trust Attributes"])
    d.line(" " * (w + 1) + "SSL,S/MIME,JAR/XPI", "header", [None, "SSL,S/MIME,JAR/XPI"])
    d.blank()
    nicks = rng.sample(NICKS, rng.randint(1, 10))
    for n in nicks:
        if rng.random() < .1:
            n = n + " - " + fake.word(rng).capitalize() + " " + fake.word(rng).capitalize() + " Intermediate Certificate Authority"
        trust = rng.choice(["u,u,u", "u,u,u", "CT,C,C", "CTu,Cu,Cu", "CT,c,", "C,,", ",,", "c,c,c", "P,,", "u,u,Pu", "CTu,u,u"])
        d.line(n.ljust(w) + " " + trust, "row", [n, trust])
    if rng.random() < .3:
        d.blank()
    return d
