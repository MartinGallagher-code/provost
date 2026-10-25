"""Cloud Foundry `cf apps` (v6 and v7+): a 'Getting apps in org ...' banner, then an
aligned table with multi-word headers ("requested state") and comma-joined routes."""
from lib import Doc, fake

TOOL = "cf-apps"


def _route(rng, app):
    dom = rng.choice(["cfapps.io", "apps.internal", "cfapps.eu10.hana.ondemand.com", "apps.example.com"])
    return f"{app}.{dom}" if rng.random() < .7 else f"{app}-{fake.token(rng, 5)}.{dom}"


def generate(rng):
    d = Doc()
    org, space = fake.name(rng), rng.choice(["dev", "staging", "prod", "sandbox", fake.word(rng)])
    who = rng.choice(["admin", f"{fake.user(rng)}@example.com", f"{fake.user(rng)}@corp.io"])
    d.skip(f"Getting apps in org {org} / space {space} as {who}...")
    v6 = rng.random() < .45
    if v6:
        d.skip("OK")
    d.blank()
    n = rng.choice([0] + [rng.randint(1, 12)] * 6)
    if n == 0:
        d.skip("No apps found")
        return d
    rows = []
    for _ in range(n):
        app = fake.name(rng)
        state = rng.choice(["started", "started", "started", "stopped"])
        routes = ", ".join(_route(rng, app) for _ in range(rng.choice([0, 1, 1, 1, 2, 3])))
        if v6:
            inst = rng.randint(1, 6)
            up = inst if state == "started" and rng.random() < .8 else rng.randint(0, inst)
            rows.append([app, state, f"{up}/{inst}", rng.choice(["256M", "512M", "1G", "2G", "64M"]),
                         rng.choice(["1G", "2G", "512M"]), routes])
        else:
            procs = []
            for p in ["web"] + rng.sample(["worker", "clock", "task"], rng.randint(0, 2)):
                inst = rng.randint(0, 4)
                up = inst if state == "started" else 0
                procs.append(f"{p}:{up}/{inst}")
            rows.append([app, state, ", ".join(procs), routes])
    hdr = (["name", "requested state", "instances", "memory", "disk", "urls"] if v6
           else ["name", "requested state", "processes", "routes"])
    d.table(hdr, rows, gap=3)
    return d
