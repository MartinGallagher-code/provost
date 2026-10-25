"""Node Version Manager `nvm ls`: installed versions (the current one marked
`->`), then alias lines `name -> target (-> resolved)` with `(default)`
flags, including the lts/* codename aliases."""
from lib import Doc

TOOL = "nvm-ls"

LTS = [("argon", 4, "4.9.1"), ("boron", 6, "6.17.1"), ("carbon", 8, "8.17.0"), ("dubnium", 10, "10.24.1"),
       ("erbium", 12, "12.22.12"), ("fermium", 14, "14.21.3"), ("gallium", 16, "16.20.2"),
       ("hydrogen", 18, None), ("iron", 20, None), ("jod", 22, None)]


def nv(rng, major):
    return f"v{major}.{rng.randint(0, 20)}.{rng.randint(0, 12)}"


def generate(rng):
    d = Doc()
    majors = sorted(rng.sample([10, 12, 14, 16, 18, 19, 20, 21, 22, 23], rng.randint(1, 6)))
    installed = sorted({nv(rng, m) for m in majors for _ in range(rng.randint(1, 2))},
                       key=lambda v: [int(x) for x in v[1:].split(".")])
    system = rng.random() < .4
    cur = rng.choice(installed + (["system"] if system else []))
    star = rng.random() < .3
    for v in installed + (["system"] if system else []):
        mark = "->" if v == cur else "  "
        pad = v.rjust(15)
        tail = " *" if star and v != "system" and rng.random() < .3 else ""
        d.line(f"{mark}{pad}{tail}", "row", [v])
    by_major = {int(v[1:].split(".")[0]): v for v in installed}
    newest = installed[-1]
    dmaj = rng.choice(majors)
    dflt = by_major[dmaj]

    def alias(name, target, resolved, flag=False):
        text = f"{name} -> {target}"
        cells = [name, target]
        if resolved is not None:
            text += f" (-> {resolved})"
            cells.append(resolved)
        if flag:
            text += " (default)"
            cells.append("(default)")
        d.line(text, "kv", cells)

    if rng.random() < .9:
        tgt = rng.choice([str(dmaj), dflt, "node"])
        alias("default", tgt, newest if tgt == "node" else dflt)
    alias("iojs", "N/A", None, True)
    alias("unstable", "N/A", None, True)
    alias("node", "stable", newest, True)
    alias("stable", ".".join(newest[1:].split(".")[:2]), newest, True)
    known = {int(v[1:].split(".")[0]): v for v in installed}
    lts = [l for l in LTS if l[1] <= 22]
    top = lts[-rng.randint(1, 3)]
    alias("lts/*", f"lts/{top[0]}", known.get(top[1], "N/A"))
    for name, major, last in lts:
        latest = last or nv(rng, major)[1:]
        alias(f"lts/{name}", f"v{latest}", known.get(major, "N/A") if rng.random() < .9 or major not in known else f"v{latest}")
        if name == top[0]:
            break
    return d
