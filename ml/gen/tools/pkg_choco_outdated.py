"""Chocolatey `choco outdated`: banner, a prose line naming the columns,
`name|current|available|pinned` rows with bare pipes, a summary sentence."""
from lib import Doc

TOOL = "choco-outdated"

PKGS = ["chocolatey", "git", "git.install", "vscode", "vscode.install", "googlechrome", "firefox", "7zip",
        "7zip.install", "nodejs", "nodejs.install", "python3", "python311", "notepadplusplus",
        "notepadplusplus.install", "vlc", "putty", "putty.install", "sysinternals", "dotnet-6.0-runtime",
        "vcredist140", "KB2919355", "KB3033929", "adobereader", "zoom", "microsoft-teams", "jre8", "curl",
        "wget", "procexp", "openssh", "terraform", "kubernetes-cli", "awscli", "golang", "docker-desktop"]


def ver(rng):
    return ".".join(str(rng.randint(0, 120 if i == 0 else 40)) for i in range(rng.randint(2, 4)))


def bump(rng, v):
    p = v.split(".")
    i = rng.randrange(len(p))
    p[i] = str(int(p[i]) + rng.randint(1, 9))
    return ".".join(p[:i + 1] + ["0"] * (len(p) - i - 1))


def generate(rng):
    d = Doc()
    d.skip(f"Chocolatey v{rng.choice(['0.10.15', '1.1.0', '1.4.0', '2.0.0', '2.2.2', '2.3.0'])}")
    if rng.random() < .3:
        d.skip("Chocolatey detected you are not running from an elevated command shell")
        d.skip(" (cmd/powershell).")
    d.skip("Outdated Packages")
    d.line(" Output is package name | current version | available version | pinned?", "header",
           ["package name", "current version", "available version", "pinned?"])
    d.blank()
    pkgs = sorted(rng.sample(PKGS, rng.randint(0, 12)))
    warned = 0
    for p in pkgs:
        cur = ver(rng)
        if rng.random() < .08:
            new, warned = cur, warned + 1
        else:
            new = bump(rng, cur)
        pin = "true" if rng.random() < .12 else "false"
        d.line(f"{p}|{cur}|{new}|{pin}", "row", [p, cur, new, pin])
    d.blank()
    n = len(pkgs) - warned
    d.skip(f"Chocolatey has determined {n} package(s) are outdated. ")
    if warned:
        d.skip(f" {warned} package(s) had warnings.")
        if rng.random() < .6:
            d.section(" Warnings:")
            for p in pkgs[:warned]:
                d.skip(f" - {p} - {p} is not found on the source(s) designated, ignoring.")
    return d
