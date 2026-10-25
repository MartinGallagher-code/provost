"""Doppler CLI `doppler configs`: a box-drawn table (┌─┬─┐ │ ├─┼─┤ └─┴─┘) with
upper-case multi-word headers and RFC 3339 timestamps."""
from lib import Doc, fake

TOOL = "doppler-configs"


def generate(rng):
    d = Doc()
    project = rng.choice([fake.word(rng), fake.name(rng), "example-project"])
    newer = rng.random() < .5
    hdr = ["NAME", "ROOT", "LOCKED", "ENVIRONMENT", "PROJECT", "CREATED AT"] + (["INHERITABLE", "INHERITS"] if newer else [])
    envs = rng.sample(["dev", "stg", "prd", "ci", "qa"], rng.randint(1, 4))
    rows = []
    for e in envs:
        rows.append((e, "true", rng.choice(["true", "false"]), e))
        for _ in range(rng.choice([0, 0, 1, 2, 3])):
            rows.append((f"{e}_{rng.choice([fake.user(rng), fake.word(rng), 'personal', 'local'])}", "false", "false", e))
    out = []
    for name, root, locked, env in rows:
        y, mo, dd = rng.randint(2020, 2026), rng.randint(1, 12), rng.randint(1, 28)
        ts = f"{y}-{mo:02d}-{dd:02d}T{fake.date(rng, 'time')}.{rng.randint(0, 999):03d}Z"
        r = [name, root, locked, env, project, ts]
        if newer:
            inh = rng.choice(["false", "false", "true"]) if root == "true" else "false"
            r += [inh, rng.choice(["", "", "", f"{project}.{rng.choice(envs)}"])]
        out.append(r)
    w = [max(len(x[c]) for x in [hdr] + out) for c in range(len(hdr))]

    def rule(l, m, r):
        return l + m.join("─" * (x + 2) for x in w) + r

    def render(cells):
        return "│ " + " │ ".join(c.ljust(w[i]) for i, c in enumerate(cells)) + " │"

    d.skip(rule("┌", "┬", "┐"))
    d.line(render(hdr), "header", hdr)
    d.skip(rule("├", "┼", "┤"))
    for r in out:
        d.line(render(r), "row", [c or None for c in r])
    d.skip(rule("└", "┴", "┘"))
    return d
