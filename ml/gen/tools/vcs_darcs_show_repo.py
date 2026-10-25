"""darcs `darcs show repo`: a key/value report with the keys right-aligned."""
from lib import Doc, fake

TOOL = "darcs-show-repo"


def generate(rng):
    d = Doc()
    user = fake.user(rng)
    proj = fake.name(rng)
    root = f"/home/{user}/src/{proj}"
    remote = rng.choice([f"http://darcs.net/{proj}", f"{user}@hub.darcs.net:{proj}",
                         f"https://hub.darcs.net/{user}/{proj}", f"/srv/darcs/{proj}"])
    pairs = [("Type", "darcs"),
             ("Format", rng.choice(["hashed, darcs-2", "hashed", "darcs-1.0", "hashed, darcs-3"])),
             ("Root", root),
             ("PristineType", rng.choice(["HashedPristine", "NoPristine", "PlainPristine"])),
             ("Cache", ", ".join([f"thisrepo:{root}"] +
                                  ([f"cache:/home/{user}/.cache/darcs"] if rng.random() < .8 else []) +
                                  ([f"repo:{remote}"] if rng.random() < .6 else [])))]
    if rng.random() < .7:
        pairs.append(("Default Remote", remote))
    if rng.random() < .4:
        pairs.append(("Boring", rng.choice(["_darcs/prefs/boring", ".boring"])))
    if rng.random() < .3:
        pairs.append(("Weak Hash", fake.hexid(rng, 40)))
    if rng.random() < .85:
        pairs.append(("Num Patches", str(rng.randint(1, 25000))))
    w = max(len(k) for k, _ in pairs) + rng.choice([0, 1, 2])
    for k, v in pairs:
        d.line(k.rjust(w) + ": " + v, "kv", [k, v])
    return d
