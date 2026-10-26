"""Mac App Store CLI `mas list` / `mas outdated`: headerless rows of an
App Store id, the app name (often several words) and the version in
parentheses; ids are padded (sometimes right-aligned) or single-spaced."""
from lib import Doc

TOOL = "mas-list"

APPS = [("497799835", "Xcode"), ("409183694", "Keynote"), ("409201541", "Pages"), ("409203825", "Numbers"),
        ("1295203466", "Microsoft Remote Desktop"), ("1333542190", "1Password 7"), ("441258766", "Magnet"),
        ("1176895641", "Spark – Email App by Readdle"), ("904280696", "Things 3"), ("803453959", "Slack"),
        ("1352778147", "Bitwarden"), ("1444383602", "Goodnotes 5"), ("462054704", "Microsoft Word"),
        ("462058435", "Microsoft Excel"), ("462062816", "Microsoft PowerPoint"), ("985367838", "Microsoft Outlook"),
        ("1274495053", "Microsoft To Do"), ("425424353", "The Unarchiver"), ("1451685025", "WireGuard"),
        ("937984704", "Amphetamine"), ("1480068668", "Messenger"), ("640199958", "Developer"),
        ("1529448980", "Reeder 5."), ("1475387142", "Tailscale"), ("408981434", "iMovie"), ("682658836", "GarageBand"),
        ("1091189122", "Bear"), ("1289583905", "Pixelmator Pro"), ("1384080005", "Tweetbot 3 for Twitter"),
        ("1569813296", "1Password for Safari"), ("1622835804", "Kagi for Safari")]


def ver(rng):
    return ".".join(str(rng.randint(0, 20)) for _ in range(rng.randint(1, 3)))


def bump(rng, v):
    p = v.split(".")
    i = rng.randrange(len(p))
    p[i] = str(int(p[i]) + rng.randint(1, 9))
    return ".".join(p[:i + 1] + ["0"] * (len(p) - i - 1))


def generate(rng):
    d = Doc()
    apps = rng.sample(APPS, rng.randint(1, 16))
    if rng.random() < .5:
        apps.sort(key=lambda a: a[1].lower())
    outdated = rng.random() < .3
    style = rng.choice(["pad", "pad", "rpad", "single"])
    wid = max(len(i) for i, _ in apps)
    wname = max(len(n) for _, n in apps)
    for ident, name in apps:
        v = ver(rng)
        if outdated:
            new = bump(rng, v)
            vs = f"({v} -> {new})"
            cells = [v, new]
        else:
            vs = f"({v})"
            cells = [v]
        if style == "single":
            text = f"{ident} {name} {vs}"
        else:
            idc = ident.rjust(wid) if style == "rpad" else ident.ljust(wid)
            text = f"{idc}  {name.ljust(wname)}  {vs}"
        d.line(text, "row", [ident, name] + cells)
    if outdated and rng.random() < .3:
        d.skip(f"Warning: Found {rng.randint(1, 3)} apps with no App Store update available")
    return d
