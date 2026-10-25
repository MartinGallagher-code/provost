"""StackExchange `dnscontrol preview`: per-domain `******** Domain:` banners, provider
progress lines (v3 `----- DNS Provider: x...N corrections` or v4 `N corrections (x)`),
numbered correction lines, and a `Done.` footer."""
from lib import Doc, fake

TOOL = "dnscontrol-preview"

PROVIDERS = ["cloudflare", "route53", "gcloud", "digitalocean", "bind", "ns1", "gandi_v5", "hetzner", "azure_dns"]


def _corr(rng, dom, i, v4):
    typ = rng.choice(["A", "A", "CNAME", "TXT", "MX", "AAAA"])
    sub = rng.choice(["@", "www", "api", "mail", "cdn", fake.word(rng), "_dmarc"])
    fq = dom if sub == "@" else f"{sub}.{dom}"
    def val():
        return {"A": fake.ip(rng), "AAAA": fake.ip(rng, v6=True), "CNAME": f"{fake.word(rng)}.{rng.choice(['herokudns.com', 'netlify.app', 'example.net'])}.",
                "TXT": f"\"{rng.choice(['v=spf1 -all', 'google-site-verification=' + fake.token(rng, 12), 'v=DMARC1; p=none'])}\"",
                "MX": f"{rng.choice([1, 5, 10, 20])} {rng.choice(['mx1', 'mx2', 'aspmx.l'])}.{rng.choice(['google.com', dom])}."}[typ]
    ttl = str(rng.choice([1, 60, 300, 3600, 86400]))
    verb = rng.choice(["CREATE", "CREATE", "MODIFY", "DELETE"])
    mark = {"CREATE": "+", "MODIFY": "±", "DELETE": "-"}[verb]
    n = f"#{i}"
    pre = f"{n}: {mark} {verb}" if v4 else f"{n}: {verb}"
    head = [n, mark, verb] if v4 else [n, verb]
    if verb == "MODIFY":
        old, new = val(), val()
        ttl2 = rng.choice([ttl, str(rng.choice([300, 600, 3600]))])
        text = f"{pre} {typ} {fq}: ({old} ttl={ttl}) -> ({new} ttl={ttl2})"
        return text, head + [typ, fq, old, "ttl", ttl, new, "ttl", ttl2]
    v = val()
    return f"{pre} {typ} {fq} {v} ttl={ttl}", head + [typ, fq, v, "ttl", ttl]


def generate(rng):
    d = Doc()
    v4 = rng.random() < .55
    doms = [f"{fake.word(rng)}{rng.choice(['', '-' + fake.word(rng)])}.{rng.choice(['com', 'org', 'io', 'net', 'dev'])}"
            for _ in range(rng.randint(1, 4))]
    if v4:
        d.skip(f"CONCURRENTLY gathering records of {len(doms)} zone(s)")
        if rng.random() < .5:
            d.skip("SERIALLY gathering records of 0 zone(s)")
    total = 0
    for dom in doms:
        d.line(f"******************** Domain: {dom}", "section", [f"Domain: {dom}"])
        provs = rng.sample(PROVIDERS, rng.choice([1, 1, 2]))
        for p in provs:
            n = rng.choice([0, 0, rng.randint(1, 6)])
            if not v4:
                if rng.random() < .5:
                    d.kv("Getting nameservers from", p, indent="----- ")
                d.line(f"----- DNS Provider: {p}...{n} correction{'s' if n != 1 else ''}", "kv",
                       ["DNS Provider", p, f"{n} correction{'s' if n != 1 else ''}"])
            elif n:
                s = f"{n} correction{'s' if n != 1 else ''}"
                d.line(f"{s} ({p})", "section", [f"{s} ({p})"])
            for i in range(1, n + 1):
                t, c = _corr(rng, dom, total + i, v4)
                d.line(t, "row", c)
            total += n
        if rng.random() < .15:
            d.skip(f"WARNING: {dom}: record {rng.choice(['www', 'api'])} TTL is below the provider minimum; raised to 60")
        if not v4:
            reg = rng.choice(["none", "namecheap", "gandi_v5", "route53"])
            d.line(f"----- Registrar: {reg}...0 corrections", "kv", ["Registrar", reg, "0 corrections"])
    d.skip(f"Done. {total} corrections.")
    return d
