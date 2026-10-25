"""Lustre `lfs df` (`-h`, `-i`): per-MDT/OST usage rows under a right-aligned
header ending in the two-word `Mounted on`, a `filesystem_summary:` row, and
one block per mounted filesystem."""
from lib import Doc, fake

TOOL = "lfs-df"


def _h(kb):
    v = kb * 1024.0
    for u in ("P", "T", "G", "M", "K"):
        f = 1024 ** {"P": 5, "T": 4, "G": 3, "M": 2, "K": 1}[u]
        if v >= f:
            return f"{v / f:.1f}{u}"
    return f"{int(v)}"


def generate(rng):
    d = Doc()
    mode = rng.choice(["k", "k", "h", "i"])
    col1 = {"k": "1K-blocks", "h": "bytes", "i": "Inodes"}[mode]
    used, avail, pct = ({"i": ("IUsed", "IFree", "IUse%")}).get(mode, ("Used", "Available", "Use%"))
    hdr = ["UUID", col1, used, avail, pct, "Mounted on"]
    pw = len(pct)

    def render(v):
        return f"{v[0]:<20} {v[1]:>12} {v[2]:>12} {v[3]:>12} {v[4]:>{pw}} {v[5]}"

    fss = rng.sample(["lustre", "scratch", "home", "project", "lfs01", "work", "fs1", "nobackup"], rng.choice([1, 1, 1, 2, 3]))
    for fi, fs in enumerate(fss):
        mnt = rng.choice([f"/mnt/{fs}", f"/mnt/{fs}", f"/{fs}", f"/lustre/{fs}"])
        d.line(render(hdr), "header", hdr)
        nmdt = rng.choice([1, 1, 2, 4])
        nost = rng.choice([2, 4, 6, 8, 12, 16, 24])
        tot = [0, 0, 0]
        for kind, n in (("MDT", nmdt), ("OST", nost)):
            for i in range(n):
                uuid = f"{fs}-{kind}{i:04x}_UUID"
                if kind == "OST" and rng.random() < 0.06:
                    msg = rng.choice(["inactive device", "Resource temporarily unavailable"])
                    uid = uuid if msg == "inactive device" else uuid[:-5]
                    d.line(f"{uid:<20}{' ' * 12}: {msg}", "row", [uid, msg, None, None, None, None])
                    continue
                if mode == "i":
                    size = rng.choice([2 ** 28, 2 ** 30, 805306368]) if kind == "MDT" else rng.choice([2 ** 24, 2 ** 25, 50331648])
                else:
                    size = rng.choice([11523528, 2.8e9, 7.6e9, 1.5e10]) if kind == "MDT" else rng.choice([7650684880, 3.8e10, 1.1e11, 2.9e10])
                    size = int(size * rng.uniform(0.98, 1.0))
                u = int(size * rng.uniform(0.01, 0.97))
                a = int((size - u) * rng.uniform(0.93, 1.0)) if mode != "i" else size - u
                p = f"{int(round(100.0 * u / (u + a))) if u + a else 0}%"
                tag = f"{mnt}[{kind}:{i}]"
                if kind == "OST":
                    tot[0] += size; tot[1] += u; tot[2] += a
                elif mode == "i":
                    tot_i = (size, u, a)
                fmt = _h if mode == "h" else str
                vals = [uuid, fmt(size), fmt(u), fmt(a), p, tag]
                d.line(render(vals), "row", vals)
        d.blank()
        if mode == "i":
            tot = list(tot_i)
        fmt = _h if mode == "h" else str
        p = f"{int(round(100.0 * tot[1] / (tot[1] + tot[2]))) if tot[1] + tot[2] else 0}%"
        vals = ["filesystem_summary:", fmt(tot[0]), fmt(tot[1]), fmt(tot[2]), p, mnt]
        cells = list(vals)
        cells[0] = "filesystem_summary"
        d.line(render(vals), "row", cells)
        d.blank()
    if rng.random() < 0.5 and d.lines and d.lines[-1] == "":
        d.lines.pop(); d.labels.pop()
    return d
