"""Red Hat VDO `vdostats`: a df-like table (1K-blocks, --human-readable or
--si) with right-aligned numbers and a multi-word `Space saving%` header, or
`--verbose`: one `device :` section per volume of padded `key : value` lines."""
from lib import Doc, fake

TOOL = "vdostats"

VERBOSE = ["version", "release version", "data blocks used", "overhead blocks used", "logical blocks used",
           "physical blocks", "logical blocks", "1K-blocks", "1K-blocks used", "1K-blocks available",
           "used percent", "saving percent", "block map cache size", "write policy", "block size",
           "completed recovery count", "read-only recovery count", "operating mode", "recovery progress (%)",
           "compressed fragments written", "compressed blocks written", "compressed fragments in packer",
           "slab count", "slabs opened", "slabs reopened", "journal disk full count", "journal commits requested count",
           "journal entries batching", "journal entries started", "journal entries writing", "journal entries written",
           "dedupe advice valid", "dedupe advice stale", "concurrent data matches", "concurrent hash collisions",
           "bios in read", "bios in write", "bios in discard", "bios in flush", "bios out read", "bios out write",
           "KVDO module bytes used", "KVDO module peak bytes used", "instance", "512 byte emulation",
           "current VDO IO requests in progress", "maximum VDO IO requests in progress"]


def _devs(rng):
    out = []
    for _ in range(rng.randint(1, 4)):
        out.append(rng.choice(["/dev/mapper/vdo", "/dev/mapper/", "/dev/mapper/vg_" + fake.word(rng) + "-vpool"]) +
                   rng.choice([str(len(out)), fake.word(rng), fake.word(rng) + "_vdo", "0-vpool"]))
    return list(dict.fromkeys(out))


def _human(kb, si):
    base = 1000 if si else 1024
    v = kb * 1024 / base
    for u in "KMGTP":
        if v < base:
            return f"{v:.1f}{u}"
        v /= base
    return f"{v:.1f}E"


def generate(rng):
    d = Doc()
    devs = _devs(rng)
    stats = []
    for dev in devs:
        size = rng.choice([10, 50, 100, 250, 1000, 4000, 16000]) * 1024 * 1024
        used = int(size * rng.uniform(0.02, 0.97))
        save = rng.choice([f"{rng.randint(0, 95)}%", f"{rng.randint(0, 95)}%", "N/A"])
        stats.append((dev, size, used, save))
    mode = rng.choice(["k", "k", "h", "h", "si", "v"])
    if mode == "v":
        for dev, size, used, save in stats:
            d.line(f"{dev} : ", "section", [dev])
            keys = VERBOSE[:12] + rng.sample(VERBOSE[12:], rng.randint(6, len(VERBOSE) - 12))
            keys = [k for k in VERBOSE if k in keys]
            w = max(len(k) for k in VERBOSE) + rng.choice([2, 6, 8])
            for k in keys:
                v = {"version": rng.choice(["31", "41"]), "release version": rng.choice(["133524", "131337"]),
                     "write policy": rng.choice(["sync", "async", "auto"]), "block size": "4096",
                     "operating mode": rng.choice(["normal", "normal", "recovering", "read-only"]),
                     "512 byte emulation": rng.choice(["off", "on"]), "1K-blocks": str(size),
                     "1K-blocks used": str(used), "1K-blocks available": str(size - used),
                     "used percent": str(used * 100 // size),
                     "saving percent": save.rstrip("%") if save != "N/A" else "N/A",
                     "recovery progress (%)": "N/A"}.get(k, str(rng.choice([0, 0, rng.randint(1, 999), rng.randint(1000, 99999999)])))
                d.line(f"  {k.ljust(w)}: {v}", "kv", [k, v])
        return d
    hd = {"k": "1K-blocks", "h": "Size", "si": "Size"}[mode]
    rows = []
    for dev, size, used, save in stats:
        if mode == "k":
            vals = [str(size), str(used), str(size - used)]
        else:
            vals = [_human(size, mode == "si"), _human(used, mode == "si"), _human(size - used, mode == "si")]
        rows.append([dev] + vals + [f"{used * 100 // size}%", save])
    d.table(["Device", hd, "Used", "Available", "Use%", "Space saving%"], rows, gap=1, right=(1, 2, 3, 4, 5))
    return d
