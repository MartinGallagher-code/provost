"""OpenFaaS `faas-cli list` (and -v): printf-padded columns joined by tabs, so a long
function name or image pushes the rest of its row out of line."""
from lib import Doc, fake

TOOL = "faas-cli-list"


def generate(rng):
    d = Doc()
    verbose = rng.random() < .45
    created = verbose and rng.random() < .5
    if rng.random() < .25:
        d.skip(f"Handling connection for {rng.choice(['8080', '31112'])}")
    hdr = ["Function"] + (["Image"] if verbose else []) + ["Invocations", "Replicas"] + (["CreatedAt"] if created else [])
    widths = [30] + ([30] if verbose else []) + [15, 5] + ([5] if created else [])

    def render(cells):
        return "\t".join(c.ljust(widths[i]) for i, c in enumerate(cells))

    d.line(render(hdr), "header", hdr)
    for _ in range(rng.randint(1, 12)):
        name = rng.choice([fake.word(rng), fake.name(rng),
                           rng.choice(["figlet", "nodeinfo", "env", "sentimentanalysis", "markdown",
                                       "cows", "certinfo", "shasum", "alpine", "colorization"])])
        if rng.random() < .1:
            name = name + "-" + fake.name(rng) + "-" + fake.name(rng)
        cells = [name]
        if verbose:
            reg = rng.choice(["ghcr.io/openfaas/", "functions/", "docker.io/alexellis2/", "registry.local:5000/", ""])
            cells.append(f"{reg}{name}:{rng.choice(['latest', fake.version(rng), '0.' + str(rng.randint(1, 20))])}")
        cells += [str(rng.choice([0, 0, rng.randint(1, 99), rng.randint(100, 999999)])), str(rng.choice([0, 1, 1, 1, 2, 5, 20]))]
        if created:
            cells.append(f"{fake.date(rng, 'datetime')} +0000 UTC")
        d.line(render(cells), "row", cells)
    return d
