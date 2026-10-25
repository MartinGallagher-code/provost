"""`mokutil --list-enrolled` (or --list-new / --db): per key a `[key N]`
heading, the SHA1 fingerprint, then an openssl-style indented certificate
dump: nested headings, `Key: value` lines, and hex blocks under headings."""
from lib import Doc, fake

TOOL = "mokutil"

ORGS = [("GB", "Isle of Man", "Douglas", "Canonical Ltd.", "Canonical Ltd. Master Certificate Authority"),
        ("US", "Washington", "Redmond", "Microsoft Corporation", "Microsoft Windows Production PCA 2011"),
        ("US", "Washington", "Redmond", "Microsoft Corporation", "Microsoft Corporation UEFI CA 2011"),
        ("US", "North Carolina", "Raleigh", "Red Hat, Inc.", "Red Hat Secure Boot CA 5"),
        ("DE", "Bavaria", "Nuremberg", "SUSE LINUX Products GmbH", "SUSE Linux Enterprise Secure Boot CA"),
        (None, None, None, None, "DKMS module signing key"),
        (None, None, None, "Debian", "Debian Secure Boot CA"),
        ("US", None, None, "NVIDIA Corporation", "NVIDIA Secure Boot Signing")]
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def hexbytes(rng, n, upper=False):
    h = [f"{rng.randint(0, 255):02x}" for _ in range(n)]
    return [x.upper() for x in h] if upper else h


def dn(org):
    c, st, l, o, cn = org
    parts = [("C", c), ("ST", st), ("L", l), ("O", o), ("CN", cn)]
    return ", ".join(f"{k}={v}" for k, v in parts if v)


def gmt(rng, y):
    return f"{rng.choice(MON)} {rng.randint(1, 28):2d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {y} GMT"


def hexblock(d, rng, nbytes, indent, per=15, lead00=False, cells=True):
    b = hexbytes(rng, nbytes)
    if lead00:
        b[0] = "00"
    for i in range(0, len(b), per):
        chunk = ":".join(b[i:i + per]) + (":" if i + per < len(b) else "")
        d.line(indent + chunk, "row", [chunk])


def generate(rng):
    d = Doc()
    opt_sha1 = rng.random() < .8
    sig_label = rng.choice(["Signature Value", "Signature Algorithm"])
    for k in range(1, rng.randint(1, 3) + 1):
        org = rng.choice(ORGS)
        issuer = org if rng.random() < .6 else rng.choice(ORGS)
        d.section(f"[key {k}]", f"key {k}")
        if opt_sha1:
            fp = ":".join(hexbytes(rng, 20))
            d.kv("SHA1 Fingerprint", fp)
        d.section("Certificate:")
        d.section("    Data:", "Data")
        d.line("        Version: 3 (0x2)", "kv", ["Version", "3 (0x2)"])
        if rng.random() < .3:
            sn = str(rng.randint(1, 2 ** 31))
            d.line(f"        Serial Number: {sn} ({hex(int(sn))})", "kv", ["Serial Number", f"{sn} ({hex(int(sn))})"])
        else:
            d.section("        Serial Number:", "Serial Number")
            hexblock(d, rng, rng.choice([8, 9, 10, 16, 19, 20]), "            ", per=20)
        alg = rng.choice(["sha256WithRSAEncryption", "sha256WithRSAEncryption", "sha1WithRSAEncryption",
                          "sha384WithRSAEncryption"])
        d.kv("Signature Algorithm", alg, indent="        ")
        d.kv("Issuer", dn(issuer), indent="        ")
        d.section("        Validity", "Validity")
        y = rng.randint(2010, 2024)
        nb, na = gmt(rng, y), gmt(rng, y + rng.choice([10, 15, 20, 30, 100]))
        d.line(f"            Not Before: {nb}", "kv", ["Not Before", nb])
        d.line(f"            Not After : {na}", "kv", ["Not After", na])
        d.kv("Subject", dn(org), indent="        ")
        d.section("        Subject Public Key Info:", "Subject Public Key Info")
        d.kv("Public Key Algorithm", "rsaEncryption", indent="            ")
        bits = rng.choice([2048, 2048, 4096, 3072])
        d.line(f"                Public-Key: ({bits} bit)", "kv", ["Public-Key", f"({bits} bit)"])
        d.section("                Modulus:", "Modulus")
        hexblock(d, rng, bits // 8 + 1, "                    ", lead00=True)
        d.line("                Exponent: 65537 (0x10001)", "kv", ["Exponent", "65537 (0x10001)"])
        d.section("        X509v3 extensions:", "X509v3 extensions")
        exts = [("X509v3 Subject Key Identifier", None, "ski"),
                ("X509v3 Authority Key Identifier", None, "aki"),
                ("X509v3 Basic Constraints", "critical", "bc"),
                ("X509v3 Key Usage", rng.choice(["critical", None]), "ku"),
                ("X509v3 Extended Key Usage", None, "eku"),
                ("Netscape Comment", None, "nc")]
        for name, crit, kind in [e for e in exts if rng.random() < .7]:
            if crit:
                d.line(f"            {name}: {crit}", "kv", [name, crit])
            else:
                d.line(f"            {name}: ", "section", [name])
            ind = "                "
            if kind == "ski":
                v = ":".join(hexbytes(rng, 20, upper=True))
            elif kind == "aki":
                v = ("keyid:" if rng.random() < .5 else "") + ":".join(hexbytes(rng, 20, upper=True))
            elif kind == "bc":
                v = rng.choice(["CA:TRUE", "CA:FALSE", "CA:TRUE, pathlen:0"])
            elif kind == "ku":
                v = rng.choice(["Digital Signature", "Certificate Sign, CRL Sign",
                                "Digital Signature, Certificate Sign, CRL Sign"])
            elif kind == "eku":
                v = rng.choice(["Code Signing", "Code Signing, 1.3.6.1.4.1.2312.16.1.2", "1.3.6.1.4.1.311.10.3.6"])
            else:
                v = rng.choice(["OpenSSL Generated Certificate", "Secure Boot Module Signature key"])
            d.line(ind + v, "row", [v])
        d.kv("Signature Algorithm", alg, indent="    ")
        if sig_label == "Signature Value":
            d.section("    Signature Value:", "Signature Value")
            hexblock(d, rng, bits // 8, "        ", per=18)
        else:
            hexblock(d, rng, bits // 8, "         ", per=18)
    return d
