"""Windows `winget upgrade`: an aligned table (one space between columns, a
single dash rule as wide as the header), an "N upgrades available." footer,
sometimes a second table of pinned/explicit-target packages."""
from lib import Doc

TOOL = "winget-upgrade"

APPS = [
    ("Microsoft Visual Studio Code", "Microsoft.VisualStudioCode"),
    ("Microsoft Edge", "Microsoft.Edge"),
    ("Git", "Git.Git"),
    ("7-Zip 22.01 (x64)", "7zip.7zip"),
    ("Mozilla Firefox (x64 en-US)", "Mozilla.Firefox"),
    ("Node.js", "OpenJS.NodeJS.LTS"),
    ("Python 3.11.4 (64-bit)", "Python.Python.3.11"),
    ("PowerShell 7-x64", "Microsoft.PowerShell"),
    ("Docker Desktop", "Docker.DockerDesktop"),
    ("Notepad++ (64-bit x64)", "Notepad++.Notepad++"),
    ("Zoom", "Zoom.Zoom"),
    ("Slack", "SlackTechnologies.Slack"),
    ("Microsoft Teams classic", "Microsoft.Teams.Classic"),
    ("Google Chrome", "Google.Chrome"),
    ("VLC media player", "VideoLAN.VLC"),
    ("Windows Terminal", "Microsoft.WindowsTerminal"),
    ("Microsoft .NET SDK 7.0.306 (x64)", "Microsoft.DotNet.SDK.7"),
    ("Microsoft Visual C++ 2015-2022 Redistributable (x64) - 14.36.32532", "Microsoft.VCRedist.2015+.x64"),
    ("Steam", "Valve.Steam"),
    ("OBS Studio", "OBSProject.OBSStudio"),
    ("GitHub CLI", "GitHub.cli"),
    ("Discord", "Discord.Discord"),
    ("KeePassXC", "KeePassXCTeam.KeePassXC"),
    ("WinSCP 6.1.1", "WinSCP.WinSCP"),
    ("PuTTY release 0.78 (64-bit)", "PuTTY.PuTTY"),
]


def ver(rng):
    parts = [str(rng.randint(0, 120)), str(rng.randint(0, 30))]
    for _ in range(rng.randint(0, 2)):
        parts.append(str(rng.randint(0, 9999)))
    return ".".join(parts)


def bump(rng, v):
    p = v.split(".")
    i = rng.randrange(len(p))
    p[i] = str(int(p[i]) + rng.randint(1, 9))
    return ".".join(p[:i + 1] + ["0"] * (len(p) - i - 1))


def make_rows(rng, apps, truncate):
    rows = []
    for name, ident in apps:
        if truncate and len(name) > 30:
            name = name[:29] + "…"
        cur = ver(rng)
        r = rng.random()
        cur = "< " + cur if r < .1 else ("Unknown" if r < .15 else cur)
        new = bump(rng, cur.replace("< ", "")) if cur != "Unknown" else ver(rng)
        src = "winget" if rng.random() < .93 else rng.choice(["msstore", None])
        rows.append([name, ident, cur, new, src])
    return rows


def emit(d, rng, rows):
    hdr = ["Name", "Id", "Version", "Available", "Source"]
    d.table(hdr, rows, gap=1, rule="-")
    i = len(d.lines) - len(rows) - 1
    d.lines[i] = "-" * (len(d.lines[i - 1]) + rng.choice([0, 1]))


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        d.skip("   - ")
    apps = rng.sample(APPS, rng.randint(1, 11))
    truncate = rng.random() < .6
    rows = make_rows(rng, apps, truncate)
    emit(d, rng, rows)
    n = len(rows)
    d.skip(f"{n} upgrade{'s' if n != 1 else ''} available.")
    if rng.random() < .35:
        d.blank()
        k = rng.randint(1, 3)
        d.skip(f"{k} package(s) have version numbers that cannot be determined. "
               "Use --include-unknown to see all results.")
    if rng.random() < .3:
        d.blank()
        d.skip("The following packages have an upgrade available, but require explicit targeting for upgrade:")
        rest = [a for a in APPS if a not in apps]
        rows2 = make_rows(rng, rng.sample(rest, rng.randint(1, 3)), truncate)
        emit(d, rng, rows2)
    return d
