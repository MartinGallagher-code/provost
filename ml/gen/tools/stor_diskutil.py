"""macOS `diskutil list`: one section per disk, each a fixed-width table
with a right-aligned TYPE column, an often-empty NAME, a size with a `*`/`+`
marker, and `Physical Store` continuation lines under APFS containers."""
from lib import Doc, fake

TOOL = "diskutil-list"

VOLNAMES = ["Macintosh HD", "Macintosh HD - Data", "Preboot", "Recovery", "VM", "Update", "Backups",
            "Untitled", "Time Machine", "Photos Archive", "EXTDRIVE", "My Passport", "Install macOS",
            "xART", "iSCPreboot", "Hardware", "BOOTCAMP", "Data"]


def _sz(rng, lo, hi):
    v = rng.uniform(lo, hi)
    if v >= 1000 ** 4:
        return f"{v / 1000 ** 4:.1f} TB"
    if v >= 1000 ** 3:
        return f"{v / 1000 ** 3:.1f} GB"
    if v >= 1000 ** 2:
        return f"{v / 1000 ** 2:.1f} MB"
    return f"{v / 1000:.1f} KB"


def _row(d, n, typ, name, mark, size, ident):
    text = f"{n:>4}: {typ:>26} {name or '':<23}{mark}{size:<10} {ident}"
    d.line(text, "row", [str(n), typ, name or None, mark + size if mark.strip() else size, ident])


def _header(d):
    d.line(f"{'#':>4}: {'TYPE':>26} {'NAME':<23} {'SIZE':<10} IDENTIFIER",
           "header", ["#", "TYPE", "NAME", "SIZE", "IDENTIFIER"])


def generate(rng):
    d = Doc()
    disk = 0
    nphys = rng.randint(1, 3)
    for p in range(nphys):
        dn = disk
        disk += 1
        internal = p == 0
        apple = rng.random() < (.85 if internal else .4)
        kind = "internal, physical" if internal else rng.choice(["external, physical", "external, physical", "disk image"])
        d.section(f"/dev/disk{dn} ({kind}):")
        _header(d)
        total = rng.uniform(120e9, 4.1e12) if not internal else rng.choice([251.0e9, 500.3e9, 1.0e12, 2.0e12, 121.3e9])
        tot = _sz(rng, total, total)
        scheme = rng.choice(["GUID_partition_scheme"] * 4 + ["FDisk_partition_scheme"])
        if scheme != "GUID_partition_scheme":
            apple = False
        _row(d, 0, scheme, None, "*", tot, f"disk{dn}")
        parts = []
        if scheme == "GUID_partition_scheme":
            if internal and rng.random() < .3:
                parts.append(("Apple_APFS_ISC", "Container disk" + str(disk), _sz(rng, 524e6, 524e6)))
            else:
                parts.append(("EFI", "EFI", "209.7 MB"))
        containers = []
        if apple:
            parts.append(("Apple_APFS", f"Container disk{disk}", _sz(rng, total * .6, total * .95)))
            containers.append(len(parts))
            if internal and rng.random() < .3:
                parts.append(("Apple_APFS_Recovery", f"Container disk{disk + 1}", "5.4 GB"))
        else:
            for _ in range(rng.randint(1, 3)):
                t = rng.choice(["Microsoft Basic Data", "Apple_HFS", "Windows_NTFS", "DOS_FAT_32", "Linux Filesystem", "Apple_Boot"])
                parts.append((t, rng.choice(VOLNAMES + [None]), _sz(rng, 1e9, total / 2)))
        for i, (t, name, size) in enumerate(parts, 1):
            _row(d, i, t, name, " ", size, f"disk{dn}s{i}")
        d.blank()
        for c in containers:
            cn = disk
            disk += 1
            d.section(f"/dev/disk{cn} (synthesized):")
            _header(d)
            ctot = parts[c - 1][2]
            _row(d, 0, "APFS Container Scheme", "-", "+", ctot, f"disk{cn}")
            store = f"Physical Store disk{dn}s{c}"
            d.line(" " * 33 + store, "cont", [store])
            vols = ["Macintosh HD", "Macintosh HD - Data", "Preboot", "Recovery", "VM"] if internal else \
                rng.sample(VOLNAMES, rng.randint(1, 3))
            if internal and rng.random() < .5:
                vols = vols[:2] + ["Update"] + vols[2:]
            j = 0
            for v in vols:
                j += 1
                size = _sz(rng, 2e4, 4e11) if "Data" in v else _sz(rng, 2e4, 2.5e10)
                _row(d, j, "APFS Volume", v, " ", size, f"disk{cn}s{j}")
                if v == "Macintosh HD" and rng.random() < .7:
                    d.line(f"{'':>4}  {'APFS Snapshot':>26} {'com.apple.os.update-...':<23} {size:<10} disk{cn}s{j}s1",
                           "row", [None, "APFS Snapshot", "com.apple.os.update-...", size, f"disk{cn}s{j}s1"])
            d.blank()
    return d
