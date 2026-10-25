"""macOS `softwareupdate --list`: tool banner and progress prose, then for
each update a `* Label: ...` line and a tab-indented line of
`Key: value, ` pairs (Title, Version, Size, Recommended, Action). The
pre-Catalina layout (`   * name-` / `\tTitle (ver), 1234K [recommended]`)
also appears."""
from lib import Doc

TOOL = "softwareupdate-list"

OS = {"Ventura": (13, "22G"), "Sonoma": (14, "23G"), "Monterey": (12, "21G"), "Sequoia": (15, "24G")}


def os_ver(rng, name):
    return f"{OS[name][0]}.{rng.randint(0, 7)}" + (f".{rng.randint(1, 3)}" if rng.random() < .5 else "")


def update(rng):
    """-> (title, label suffix or None, version, size KiB, needs restart)"""
    k = rng.randrange(8)
    if k < 3:
        name = rng.choice(list(OS))
        v = os_ver(rng, name)
        return f"macOS {name} {v}", f"{OS[name][1]}{rng.randint(10, 999)}", v, rng.randint(900000, 13000000), True
    if k == 3:
        name = rng.choice(list(OS))
        v = os_ver(rng, name)
        return (f"Rapid Security Response macOS {name} {v} (a)", f"{OS[name][1]}{rng.randint(10, 999)}a",
                f"{v} (a)", rng.randint(80000, 400000), True)
    if k == 4:
        v = f"{rng.randint(14, 16)}.{rng.randint(0, 4)}"
        return "Command Line Tools for Xcode", v, v, rng.randint(600000, 900000), False
    if k == 5:
        v = f"{rng.randint(16, 18)}.{rng.randint(0, 6)}"
        return "Safari", f"{v}{rng.choice(list(OS))}Auto", v, rng.randint(100000, 250000), False
    if k == 6:
        n = str(rng.randint(2100, 5300))
        return "XProtectPlistConfigData", f"{n}", n, rng.randint(80, 900), False
    n = str(rng.randint(1, 200))
    return rng.choice(["MRTConfigData", "Gatekeeper Configuration Data"]), n, f"1.{n}", rng.randint(80, 9000), False


def generate(rng):
    d = Doc()
    d.skip("Software Update Tool")
    d.blank()
    d.skip("Finding available software")
    picks = {}
    for _ in range(rng.randint(0, 5)):
        u = update(rng)
        picks.setdefault(u[0].split(" ")[0] + u[0].split(" ")[-1], u)
    picks = list(picks.values())
    if not picks:
        d.skip("No new software available.")
        return d
    d.skip("Software Update found the following new or updated software:")
    old = rng.random() < .2
    for title, build, v, kib, restart in picks:
        size = f"{kib}K" + ("iB" if not old else "")
        rec = rng.random() < .8
        if old:
            label = f"{title}-{build}" if build else f"{title}-"
            d.line(f"   * {label}", "section", [label])
            tags = (" [recommended]" if rec else "") + (" [restart]" if restart else "")
            vv = f"({v})" if rng.random() < .7 else "( )"
            text = f"\t{title} {vv}, {size}{tags}"
            cells = [title, vv if vv != "( )" else None, size,
                     "[recommended]" if rec else None, "[restart]" if restart else None]
            d.line(text, "row", cells)
            continue
        label = f"{title}-{build}" if build else title
        d.line(f"* Label: {label}", "kv", ["Label", label])
        pairs = [("Title", title), ("Version", v), ("Size", size), ("Recommended", "YES" if rec else "NO")]
        if rng.random() < .3:
            pairs.insert(3, ("Deferred", "NO"))
        if restart:
            pairs.append(("Action", rng.choice(["restart", "restart", "shut down"])))
        text = "\t" + "".join(f"{k}: {val}, " for k, val in pairs)
        d.line(text, "row", [x for kv in pairs for x in kv])
    return d
