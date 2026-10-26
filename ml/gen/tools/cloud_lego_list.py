"""ACME client `lego list` (and --accounts): a 'Found the following certs:' heading,
then indented Certificate Name blocks of key: value lines separated by blank lines."""
from lib import Doc, fake

TOOL = "lego-list"


def generate(rng):
    d = Doc()
    base = rng.choice(["/root/.lego", "/home/" + fake.user(rng) + "/.lego", "/etc/lego", "/var/lib/lego"])
    names_only = rng.random() < .15
    n = rng.choice([0] + [rng.randint(1, 5)] * 8)
    if n == 0:
        d.skip("No certificates found.")
    else:
        d.section("Found the following certs:")
        for _ in range(n):
            dom = f"{rng.choice(['', '', 'www.', 'api.', '*.'])}{fake.word(rng)}.{rng.choice(['com', 'org', 'io', 'net'])}"
            name = dom.replace("*", "_")
            if names_only:
                d.line(name, "row", [name])
                continue
            d.kv("Certificate Name", name, indent="  ")
            sans = [dom] + [f"{s}.{dom.lstrip('*.').split('.', 1)[-1] if dom.startswith(('www.', 'api.')) else dom.lstrip('*.')}"
                            for s in rng.sample(["www", "mail", "cdn", "static"], rng.randint(0, 2))]
            d.kv("Domains", ", ".join(sans), indent="    ")
            y, mo, dd = rng.randint(2024, 2027), rng.randint(1, 12), rng.randint(1, 28)
            ts = f"{y}-{mo:02d}-{dd:02d} {fake.date(rng, 'time')} +0000 UTC"
            d.kv("Expiry Date", ts if rng.random() < .85 else ts + " (EXPIRED)", indent="    ")
            d.kv("Certificate Path", f"{base}/certificates/{name}.crt", indent="    ")
            d.blank()
    if rng.random() < .35 or n == 0:
        if n and names_only:
            d.blank()
        d.section("Found the following accounts:")
        for _ in range(rng.randint(1, 2)):
            email = f"{fake.user(rng)}@{fake.word(rng)}.com"
            srv = rng.choice(["https://acme-v02.api.letsencrypt.org/directory",
                              "https://acme-staging-v02.api.letsencrypt.org/directory",
                              "https://acme.zerossl.com/v2/DV90"])
            d.kv("Email", email, indent="  ")
            d.kv("Server", srv, indent="  ")
            host = srv.split("/")[2]
            d.kv("Path", f"{base}/accounts/{host}/{email}", indent="  ")
            d.blank()
    return d
