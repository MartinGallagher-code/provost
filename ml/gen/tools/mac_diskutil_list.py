"""macOS `diskutil list`: one section per disk, each a right/left aligned
partition table; APFS containers add a `Physical Store` continuation line."""
from lib import Doc, fake

TOOL = "diskutil-list"

VOLS = ["Macintosh HD", "Macintosh HD - Data", "Preboot", "Recovery", "VM", "Update",
        "xART", "iSCPreboot", "Hardware", "Backups of Macintosh", "Data", "Untitled",
        "Time Machine", "Projects", "Photos Library Archive 2023"]


def gb(rng, lo=0.1, hi=2000):
    v = rng.uniform(lo, hi)
    if v < 1:
        return f"{v * 1000:.1f} MB"
    if v >= 1000:
        return f"{v / 1000:.1f} TB"
    return f"{v:.1f} GB"


def trunc(name):
    return name if len(name) <= 23 else name[:20] + "..."


def row(d, idx, typ, name, size, ident):
    if size[0] in "*+":   # the marker hangs one column left of SIZE
        text = f"{idx:>4}: {typ:>26} {trunc(name or ''):<22} {size:<11} {ident}"
    else:
        text = f"{idx:>4}: {typ:>26} {trunc(name or ''):<23} {size:<10} {ident}"
    d.line(text.rstrip(), "row", [str(idx), typ, trunc(name) if name else None, size, ident])


def header(d):
    d.line(f"{'#':>4}: {'TYPE':>26} {'NAME':<23} {'SIZE':<10} IDENTIFIER", "header",
           ["#", "TYPE", "NAME", "SIZE", "IDENTIFIER"])


def generate(rng):
    d = Doc()
    n = 0
    containers = []
    # internal physical disk
    disks = [("internal, physical", "GUID_partition_scheme")]
    if rng.random() < .5:
        disks.append(("external, physical", rng.choice(["GUID_partition_scheme", "FDisk_partition_scheme"])))
    if rng.random() < .3:
        disks.append(("disk image", "GUID_partition_scheme"))
    nextdisk = len(disks)
    first = True
    for kind, scheme in disks:
        dev = f"disk{n}"
        if not first:
            d.blank()
        first = False
        d.section(f"/dev/{dev} ({kind}):", f"/dev/{dev} ({kind})")
        header(d)
        row(d, 0, scheme, None, "*" + gb(rng, 1, 4000), dev)
        k = 1
        if scheme == "FDisk_partition_scheme":
            for _ in range(rng.randint(1, 2)):
                row(d, k, rng.choice(["Windows_FAT_32", "DOS_FAT_32", "Windows_NTFS", "Linux"]),
                    rng.choice(["UNTITLED", "USB", "BOOT", "KINGSTON", None]), gb(rng, .1, 256), f"{dev}s{k}")
                k += 1
        else:
            if kind == "internal, physical" and rng.random() < .6:
                c = nextdisk; nextdisk += 1
                row(d, k, "Apple_APFS_ISC", f"Container disk{c}", gb(rng, .3, .6), f"{dev}s{k}")
                containers.append((c, f"{dev}s{k}", ["iSCPreboot", "xART", "Hardware"]))
                k += 1
            elif kind != "disk image" and rng.random() < .5:
                row(d, k, "EFI", "EFI", "209.7 MB", f"{dev}s{k}")
                k += 1
            for j in range(rng.randint(1, 2)):
                if rng.random() < .75 or (j == 0 and kind == "internal, physical"):
                    c = nextdisk; nextdisk += 1
                    row(d, k, "Apple_APFS", f"Container disk{c}", gb(rng, 20, 2000), f"{dev}s{k}")
                    vols = (["Macintosh HD", "Macintosh HD - Data", "Preboot", "Recovery", "VM", "Update"]
                            if kind == "internal, physical" and not any(x[2][0] == "Macintosh HD" for x in containers)
                            else rng.sample(VOLS[6:], rng.randint(1, 3)))
                    containers.append((c, f"{dev}s{k}", vols))
                else:
                    row(d, k, rng.choice(["Apple_HFS", "Microsoft Basic Data", "Linux Filesystem", "Apple_Boot"]),
                        rng.choice(VOLS[8:] + [None]), gb(rng, 1, 900), f"{dev}s{k}")
                k += 1
            if kind == "internal, physical" and rng.random() < .5:
                c = nextdisk; nextdisk += 1
                row(d, k, "Apple_APFS_Recovery", f"Container disk{c}", gb(rng, 5, 6), f"{dev}s{k}")
                containers.append((c, f"{dev}s{k}", ["Recovery"]))
        n += 1
    for c, store, vols in sorted(containers):
        d.blank()
        d.section(f"/dev/disk{c} (synthesized):", f"/dev/disk{c} (synthesized)")
        header(d)
        row(d, 0, "APFS Container Scheme", "-", "+" + gb(rng, 1, 2000), f"disk{c}")
        d.line(" " * 33 + f"Physical Store {store}", "cont", [f"Physical Store {store}"])
        k = 1
        for v in vols:
            row(d, k, "APFS Volume", v, gb(rng, .01, 600), f"disk{c}s{k}")
            if v == "Macintosh HD" and rng.random() < .7:
                row(d, k, "APFS Snapshot", f"com.apple.os.update-{fake.hexid(rng, 40).upper()}",
                    gb(rng, 8, 12), f"disk{c}s{k}s1")
            k += 1
    return d
