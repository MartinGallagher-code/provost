"""Dokku `<plugin>:report [app]`: per app an `=====> app <plugin>
information` heading, then indented `Key:` lines padded to a fixed column;
empty values leave the key alone on its line."""
from lib import Doc, fake

TOOL = "dokku-report"


def fields(rng, plugin, app):
    cid = lambda: fake.hexid(rng, 11)  # noqa: E731
    dom = rng.choice(["example.com", "dokku.me", fake.word(rng) + ".io", "apps.internal"])
    if plugin == "ps":
        n = rng.randint(0, 4)
        deployed = n > 0 or rng.random() < .3
        out = [("Deployed", str(deployed).lower()), ("Processes", str(n)), ("Ps can scale", "true"),
               ("Ps computed procfile path", "Procfile"), ("Ps global procfile path", "Procfile"),
               ("Ps procfile path", rng.choice(["", "", "Procfile.prod"])),
               ("Ps restart policy", rng.choice(["on-failure:10", "unless-stopped", "always", "no"])),
               ("Restore", rng.choice(["true", "false"])), ("Running", "true" if n else rng.choice(["false", "mixed"]))]
        for p in range(n):
            ptype = "web" if p < 2 else rng.choice(["worker", "clock", "release"])
            out.append((f"Status {ptype} {p + 1}", f"{rng.choice(['running', 'running', 'exited (1)', 'restarting'])} (CID: {cid()})"))
        return out
    if plugin == "domains":
        vh = [f"{app}.{dom}"] + ([f"www.{app}.{dom}"] if rng.random() < .4 else [])
        return [("Domains app enabled", "true"), ("Domains app vhosts", " ".join(vh)),
                ("Domains global enabled", rng.choice(["true", "false"])), ("Domains global vhosts", dom)]
    if plugin == "network":
        return [("Network attach post create", ""), ("Network attach post deploy", rng.choice(["", fake.word(rng) + "-net"])),
                ("Network bind all interfaces", rng.choice(["false", "true"])),
                ("Network computed attach post create", ""), ("Network computed initial network", ""),
                ("Network computed tld", ""), ("Network initial network", ""),
                ("Network static web listener", ""), ("Network tld", ""),
                ("Network web listeners", " ".join(f"{fake.ip(rng)}:5000" for _ in range(rng.randint(0, 2))))]
    if plugin == "git":
        return [("Git deploy branch", rng.choice(["master", "main", "deploy"])),
                ("Git global deploy branch", "master"), ("Git keep git dir", "false"),
                ("Git rev env var", "GIT_REV"), ("Git sha", fake.hexid(rng, 40) if rng.random() < .8 else ""),
                ("Git source image", ""), ("Git last updated at", str(rng.randint(1600000000, 1790000000)))]
    return [("Proxy enabled", "true"), ("Proxy port map", " ".join(rng.sample(["http:80:5000", "https:443:5000", "http:8080:8080"],
                                                                              rng.randint(1, 2)))),
            ("Proxy type", rng.choice(["nginx", "nginx", "caddy", "traefik", "haproxy"]))]


def generate(rng):
    d = Doc()
    plugin = rng.choice(["ps", "ps", "domains", "network", "git", "proxy"])
    apps = rng.sample(["api", "web", "blog", "node-js-app", "python-getting-started", fake.name(rng), fake.word(rng) + "-app",
                       "ruby-sample", "docs"], rng.randint(1, 4))
    width = rng.choice([30, 30, 35, 40])
    for i, app in enumerate(apps):
        d.section(f"=====> {app} {plugin} information", f"{app} {plugin} information")
        for k, v in fields(rng, plugin, app):
            text = "       " + (k + ":").ljust(width) + v
            if v:
                d.line(text, "kv", [k, v])
            else:
                d.line(text, "kv", [k])
    return d
