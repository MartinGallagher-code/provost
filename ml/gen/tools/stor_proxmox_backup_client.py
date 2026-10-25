"""`proxmox-backup-client snapshot list` / `list` and `proxmox-backup-manager
datastore list`: box-drawn tables (`┌─┬─┐`, `╞═╪═╡` under the header, `├─┼─┤`
between rows), sizes right-aligned, file lists one cell."""
import datetime

from lib import Doc, fake

TOOL = "proxmox-backup-client-list"


def _box(d, header, rows, right=()):
    widths = [max(len(r[i] or "") for r in [header] + rows) for i in range(len(header))]

    def render(cells):
        return "│" + "│".join(" " + ((c or "").rjust(w) if i in right else (c or "").ljust(w)) + " "
                               for i, (c, w) in enumerate(zip(cells, widths))) + "│"

    def rule(l, m, r, ch):
        return l + m.join(ch * (w + 2) for w in widths) + r

    d.skip(rule("┌", "┬", "┐", "─"))
    d.line(render(header), "header", header)
    d.skip(rule("╞", "╪", "╡", "═"))
    for i, r in enumerate(rows):
        d.line(render(r), "row", [c if c else None for c in r])
        if i < len(rows) - 1:
            d.skip(rule("├", "┼", "┤", "─"))
    d.skip(rule("└", "┴", "┘", "─"))


def _groups(rng):
    out = []
    for _ in range(rng.randint(1, 6)):
        kind = rng.choice(["vm", "vm", "ct", "host"])
        ident = str(rng.randint(100, 999)) if kind != "host" else rng.choice(["pve1", "pve2", fake.word(rng), "backup-01"])
        out.append((kind, ident))
    return list(dict.fromkeys(out))


def _files(kind, rng):
    if kind == "vm":
        disks = ["drive-scsi0.img"] + (["drive-scsi1.img"] if rng.random() < .3 else []) + (["drive-efidisk0.img"] if rng.random() < .3 else [])
        return " ".join(["client.log"] * (rng.random() < .5) + disks + ["fw.conf"] * (rng.random() < .3) + ["index.json", "qemu-server.conf"])
    if kind == "ct":
        return " ".join(["catalog.pcat1", "index.json", "pct.conf", "root.pxar"])
    return " ".join(["catalog.pcat1", "index.json"] + rng.sample(["root.pxar", "etc.pxar", "home.pxar", "data.pxar"], rng.randint(1, 2)))


def _size(rng):
    v = rng.uniform(0.01, 999)
    return f"{v:.3f} {rng.choice(['MiB', 'GiB', 'GiB', 'GiB', 'TiB' if v < 5 else 'GiB'])}"


def generate(rng):
    d = Doc()
    mode = rng.choice(["snap", "snap", "list", "ds"])
    if mode == "ds":
        rows = []
        for name in rng.sample(["store1", "backup", "local-zfs", "offsite", "nfs-nas", "archive", fake.word(rng)], rng.randint(1, 4)):
            rows.append([name, rng.choice(["/mnt/datastore/", "/backup/", "/tank/pbs/"]) + name,
                         rng.choice([None, None, "main store", "USB disk", "sync target"])])
        _box(d, ["name", "path", "comment"], rows)
        return d
    groups = _groups(rng)
    now = datetime.datetime(2026, rng.randint(1, 10), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59))
    if mode == "list":
        rows = []
        for kind, ident in groups:
            t = now - datetime.timedelta(hours=rng.randint(0, 200))
            rows.append([f"{kind}/{ident}", t.strftime("%Y-%m-%dT%H:%M:%SZ"), str(rng.randint(1, 60)), _files(kind, rng)])
        _box(d, ["group", "last snapshot", "backup-count", "files"], rows, right=(2,))
        return d
    rows = []
    for kind, ident in groups:
        for k in range(rng.randint(1, 4)):
            t = now - datetime.timedelta(days=k, minutes=rng.randint(0, 600))
            rows.append([f"{kind}/{ident}/{t.strftime('%Y-%m-%dT%H:%M:%SZ')}", _size(rng), _files(kind, rng)])
    _box(d, ["snapshot", "size", "files"], rows, right=(1,))
    return d
