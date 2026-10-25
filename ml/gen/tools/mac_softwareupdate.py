"""macOS `softwareupdate --list`: banner prose, then per update a `* Label:`
line and a tab-indented line of `Key: value,` pairs."""
from lib import Doc, fake

TOOL = "softwareupdate-list"


def generate(rng):
    d = Doc()
    d.skip("Software Update Tool")
    d.blank()
    d.skip("Finding available software")
    if rng.random() < .12:
        d.skip("No new software available.")
        return d
    d.skip("Software Update found the following new or updated software:")
    items = []
    if rng.random() < .8:
        name, maj = rng.choice([("macOS Sonoma", 14), ("macOS Ventura", 13), ("macOS Sequoia", 15), ("macOS Monterey", 12)])
        ver = f"{maj}.{rng.randint(0, 7)}" + (f".{rng.randint(1, 3)}" if rng.random() < .4 else "")
        build = f"{maj + 9}{rng.choice('ABCDEFGH')}{rng.randint(10, 999)}"
        items.append((f"{name} {ver}-{build}", f"{name} {ver}", ver, f"{rng.randint(800000, 13000000)}KiB", "YES", "restart"))
    if rng.random() < .5:
        v = rng.choice(["15.0", "15.1", "15.3", "16.0", "14.3.1"])
        items.append((f"Command Line Tools for Xcode-{v}", "Command Line Tools for Xcode", v,
                      f"{rng.randint(600000, 900000)}KiB", "YES", None))
    if rng.random() < .4:
        v = f"{rng.randint(16, 18)}.{rng.randint(0, 6)}"
        items.append((f"Safari{v}VenturaAuto-{v}", "Safari", v, f"{rng.randint(150000, 250000)}KiB", "", None))
    if rng.random() < .3:
        v = f"{rng.randint(1, 5)}.{rng.randint(0, 99)}"
        items.append((f"BridgeOSUpdateCustomer-{v}", "BridgeOSUpdateCustomer", v, f"{rng.randint(400000, 900000)}KiB", "YES", "shut down"))
    if not items:
        items.append(("XProtectPlistConfigData-5272", "XProtectPlistConfigData", "5272", "2134KiB", "", None))
    for label, title, ver, size, rec, action in items:
        d.line(f"* Label: {label}", "kv", ["Label", label])
        pairs = [("Title", title), ("Version", ver), ("Size", size)]
        if rec:
            pairs.append(("Recommended", rec))
        if action:
            pairs.append(("Action", action))
        text = "\t" + ", ".join(f"{k}: {v}" for k, v in pairs) + ", "
        cells = []
        for k, v in pairs:
            cells += [k, v]
        d.line(text, "row", cells)
    return d
