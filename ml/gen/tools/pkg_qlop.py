"""Gentoo portage-utils `qlop`: emerge history as fixed-layout log lines
(`timestamp >>> category/pkg-ver[: duration]`, `<<<` for unmerges, `***`
for syncs), or per-package averages with a total line."""
from lib import Doc

TOOL = "qlop"

ATOMS = ["sys-libs/glibc", "sys-devel/gcc", "dev-lang/python", "dev-lang/rust", "sys-kernel/gentoo-sources",
         "www-client/firefox", "app-editors/vim", "dev-vcs/git", "media-libs/mesa", "x11-libs/gtk+",
         "dev-libs/openssl", "net-misc/curl", "sys-apps/portage", "app-shells/bash", "sys-apps/systemd",
         "dev-qt/qtbase", "kde-plasma/plasma-workspace", "media-video/ffmpeg", "dev-libs/glib",
         "sys-devel/llvm", "net-libs/nodejs", "app-misc/tmux", "sys-apps/coreutils", "dev-db/sqlite",
         "dev-python/setuptools", "dev-python/pip", "app-portage/gentoolkit", "sys-libs/zlib"]


def pver(rng):
    v = ".".join(str(rng.randint(0, 40)) for _ in range(rng.randint(2, 3)))
    return v + (f"-r{rng.randint(1, 5)}" if rng.random() < .35 else "")


def dur(rng, secs=None):
    s = secs if secs is not None else rng.randint(4, 5400)
    h, m, s = s // 3600, s % 3600 // 60, s % 60
    if h:
        return f"{h}:{m:02d}′{s:02d}″"
    if m:
        return f"{m}′{s:02d}″"
    return f"{s}″"


def stamp(rng, style, t):
    import datetime
    dt = datetime.datetime(2023, 1, 1) + datetime.timedelta(seconds=t)
    if style == "iso":
        return dt.strftime("%Y-%m-%dT%H:%M:%S")
    return dt.strftime("%a %b ") + f"{dt.day:2d}" + dt.strftime(" %H:%M:%S %Y")


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        atoms = rng.sample(ATOMS, rng.randint(2, 12))
        w = max(len(a) for a in atoms) + 1
        tot, cnt = 0, 0
        for a in atoms:
            n = rng.randint(1, 30)
            secs = rng.randint(4, 5400)
            du = dur(rng, secs)
            cnt += n
            tot += secs * n
            pad = "" if rng.random() < .5 else " " * (w - len(a) - 1)
            text = f"{a}:{pad} {du} average for {n} merge{'s' if n > 1 else ''}"
            d.line(text, "row", [a, du, f"average for {n} merge{'s' if n > 1 else ''}"])
        if rng.random() < .8:
            du = dur(rng, tot)
            d.line(f"total: {du} for {cnt} merges", "row", ["total", du, f"for {cnt} merges"])
        return d
    style = "iso" if rng.random() < .75 else "ctime"
    timed = rng.random() < .5
    t = rng.randint(0, 10 ** 8)
    for _ in range(rng.randint(3, 25)):
        t += rng.randint(20, 90000)
        ts = stamp(rng, style, t)
        r = rng.random()
        if r < .07:
            repo = rng.choice(["gentoo", "guru", "steam-overlay"])
            cells = [ts, "***", repo] + ([dur(rng)] if timed else [])
            text = f"{ts} *** {repo}" + (f": {cells[-1]}" if timed else "")
            d.line(text, "row", cells)
            continue
        mark = "<<<" if r < .18 else ">>>"
        atom = f"{rng.choice(ATOMS)}-{pver(rng)}"
        if timed:
            du = dur(rng)
            d.line(f"{ts} {mark} {atom}: {du}", "row", [ts, mark, atom, du])
        else:
            d.line(f"{ts} {mark} {atom}", "row", [ts, mark, atom])
    return d
