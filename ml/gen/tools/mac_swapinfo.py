"""FreeBSD `swapinfo` (`-h`, `-k`, `-m`): one row per swap device and a
`Total` row when there is more than one."""
from lib import Doc, fake

TOOL = "swapinfo"


def human(kb):
    for u, f in (("T", 1 << 30), ("G", 1 << 20), ("M", 1 << 10)):
        if kb >= f:
            v = kb / f
            return (f"{v:.1f}" if v < 10 else f"{v:.0f}") + u
    return f"{kb}K" if kb else "0B"


def generate(rng):
    d = Doc()
    mode = rng.choice(["k", "k", "h", "m", "512"])
    sizecol = {"k": "1K-blocks", "h": "Size", "m": "1M-blocks", "512": "512-blocks"}[mode]
    devs = []
    for i in range(rng.choice([1, 1, 2, 3])):
        name = rng.choice([f"/dev/ada{i}p3", f"/dev/nvd{i}p3", f"/dev/gpt/swap{i}", f"/dev/md{99 - i}",
                           f"/dev/mirror/swap", f"/dev/ada{i}p2.eli", f"/dev/da{i}s1b"])
        size = rng.choice([1, 2, 4, 8, 16, 32]) * 1048576
        used = rng.choice([0, 0, rng.randint(0, size // 2), rng.randint(0, size)])
        devs.append((name, size, used))

    def fmt(v):
        if mode == "h":
            return human(v)
        if mode == "m":
            return str(v // 1024)
        if mode == "512":
            return str(v * 2)
        return str(v)

    rows = [[n, fmt(s), fmt(u), fmt(s - u), f"{100 * u // s}%"] for n, s, u in devs]
    if len(devs) > 1:
        ts, tu = sum(x[1] for x in devs), sum(x[2] for x in devs)
        rows.append(["Total", fmt(ts), fmt(tu), fmt(ts - tu), f"{100 * tu // ts}%"])
    hdr = ["Device", sizecol, "Used", "Avail", "Capacity"]
    w = [max(15, max(len(r[0]) for r in rows))] + [max(8, len(sizecol), max(len(r[1]) for r in rows))] + \
        [max(8, max(len(r[c]) for r in rows)) for c in (2, 3)] + [8]

    def render(r):
        return f"{r[0]:<{w[0]}} {r[1]:>{w[1]}} {r[2]:>{w[2]}} {r[3]:>{w[3]}} {r[4]:>{w[4]}}"
    d.line(render(hdr), "header", hdr)
    for r in rows:
        d.line(render(r), "row", r)
    return d
