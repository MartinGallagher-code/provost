"""Apache OpenWhisk `wsk list` / `wsk action list`: an entity-type heading
(packages, actions, triggers, rules) over headerless, wide-padded rows."""
from lib import Doc, fake

TOOL = "wsk-list"

KINDS = ["nodejs:10", "nodejs:14", "nodejs:18", "python:3", "python:3.9", "java:8", "go:1.15",
         "php:7.4", "ruby:2.5", "swift:5.3", "blackbox", "sequence", "dotnet:3.1"]


def generate(rng):
    d = Doc()
    ns = rng.choice(["guest", "_", f"{fake.user(rng)}@example.com_dev", fake.name(rng)])
    full = rng.random() < .6
    if full:
        shown = rng.choice(["default", ns])
        d.line(f"Entities in namespace: {shown}", "kv", ["Entities in namespace", shown])
        types = ["packages", "actions", "triggers", "rules"]
    else:
        types = [rng.choice(["actions", "actions", "packages", "triggers", "rules"])]
    pad = rng.choice([70, 71, 72])
    pkgs = [fake.word(rng) for _ in range(rng.randint(0, 3))]
    for t in types:
        n = rng.randint(0, 6) if full else rng.randint(1, 10)
        d.section(t)
        for _ in range(n):
            if t == "packages":
                name = rng.choice([f"/{ns}/{fake.word(rng)}", "/whisk.system/utils", "/whisk.system/samples",
                                   f"/{ns}/{fake.name(rng)}"])
            else:
                pre = f"/{ns}/" + (rng.choice(pkgs) + "/" if pkgs and t == "actions" and rng.random() < .4 else "")
                name = pre + rng.choice([fake.name(rng), fake.word(rng), "hello", "everyMinute", "mySequence"])
            vis = rng.choice(["private", "private", "shared"]) if t == "packages" else "private"
            cells = [name, vis]
            text = name.ljust(pad) + " " + vis
            if t == "actions":
                k = rng.choice(KINDS)
                cells.append(k)
                text += " " + k
            if t == "rules" and rng.random() < .5:
                st = rng.choice(["active", "inactive"])
                cells.append(st)
                text += "   " + st
            d.line(text, "row", cells)
    return d
