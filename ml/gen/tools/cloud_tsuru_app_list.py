"""tsuru `app-list`: a bordered tablewriter grid; a cell holding several unit summaries
or addresses wraps onto extra lines (continuation rows), with optional row rules."""
from lib import Doc, fake

TOOL = "tsuru-app-list"


def generate(rng):
    d = Doc()
    with_rules = rng.random() < .6
    old = rng.random() < .3
    hdr = ["Application", "Units State Summary" if old else "Units", "Address"]
    apps = []
    for _ in range(rng.randint(1, 9)):
        name = fake.name(rng)
        if old:
            u = rng.randint(0, 6)
            units = [f"{u} of {u + rng.randint(0, 2)} units in-service"]
        else:
            units = []
            for st in rng.sample(["started", "error", "stopped", "starting", "asleep"], rng.choice([0, 1, 1, 1, 2, 3])):
                k = rng.randint(1, 5)
                units.append(f"{k} unit{'s' if k > 1 else ''}: {k} {st}")
        dom = rng.choice(["cloud.tsuru.io", "tsuru.example.com", "apps.internal", "192.168.50.4.nip.io"])
        addrs = [f"{name}.{dom}"] + [f"{name}.{rng.choice(['example.org', 'io', 'company.net'])}"
                                     for _ in range(rng.choice([0, 0, 0, 1, 2]))]
        if rng.random() < .1:
            addrs = []
        apps.append([name, units, addrs])
    w = [max([len(hdr[0])] + [len(a[0]) for a in apps]),
         max([len(hdr[1])] + [len(x) for a in apps for x in a[1]]),
         max([len(hdr[2])] + [len(x) for a in apps for x in a[2]])]
    rule = "+" + "+".join("-" * (x + 2) for x in w) + "+"

    def render(cells):
        return "| " + " | ".join((c or "").ljust(w[i]) for i, c in enumerate(cells)) + " |"

    d.skip(rule)
    d.line(render(hdr), "header", hdr)
    d.skip(rule)
    for i, (name, units, addrs) in enumerate(apps):
        h = max(1, len(units), len(addrs))
        for j in range(h):
            cells = [name if j == 0 else None, units[j] if j < len(units) else None,
                     addrs[j] if j < len(addrs) else None]
            if j == 0:
                d.line(render(cells), "row", cells)
            else:
                d.line(render(cells), "cont", [c for c in cells if c])
        if with_rules or i == len(apps) - 1:
            d.skip(rule)
    return d
