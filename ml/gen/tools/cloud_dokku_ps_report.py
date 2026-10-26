"""dokku `ps:report`: one `=====> app ... information`
banner per app, then indented, colon-padded key/value lines (some with no value)."""
from lib import Doc, fake

TOOL = "dokku-ps-report"


def _app(rng):
    return rng.choice([fake.word(rng), fake.name(rng)])


def _ps(rng, app):
    procs = rng.sample(["web", "worker", "clock", "release", "scheduler"], rng.randint(1, 3))
    scale = {p: rng.randint(0 if p != "web" else 1, 4) for p in procs}
    running = rng.random() < .85
    pairs = [("Deployed", rng.choice(["true", "true", "false"])),
             ("Processes", str(sum(scale.values()))),
             ("Ps can scale", rng.choice(["true", "false"])),
             ("Ps computed procfile path", "Procfile"),
             ("Ps global procfile path", "Procfile"),
             ("Ps procfile path", rng.choice(["", "", "Procfile.prod"])),
             ("Ps restart policy", rng.choice(["on-failure:10", "always", "unless-stopped", "no"])),
             ("Restore", "true"),
             ("Running", "true" if running else rng.choice(["false", "mixed"]))]
    for p in procs:
        for i in range(1, scale[p] + 1):
            st = "running" if running else rng.choice(["exited", "running", "restarting"])
            pairs.append((f"Status {p} {i}", f"{st} (CID: {fake.hexid(rng, rng.choice([11, 12]))})"))
    return pairs


def generate(rng):
    d = Doc()
    kind, fn = "ps", _ps
    width = rng.choice([31, 33, 35, 39])
    for n in range(rng.choice([1, 1, 2, 3])):
        if n:
            if rng.random() < .3:
                d.blank()
        app = _app(rng)
        d.line(f"=====> {app} {kind} information", "section", [f"{app} {kind} information"])
        for k, v in fn(rng, app):
            text = "       " + (k + ":").ljust(width) + (" " + v if v else "")
            d.line(text.rstrip() if not v else text, "kv", [k, v] if v else [k])
    return d
