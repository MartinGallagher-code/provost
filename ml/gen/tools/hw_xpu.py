"""Intel `xpu-smi discovery` / `xpu-smi stats -d N`: +---+ boxed tables.
discovery wraps each device's details down the second column (cont lines);
stats is a boxed key | value list, multi-tile values as `Tile 0: x; Tile 1: y`."""
from lib import Doc, fake

TOOL = "xpu-smi"

GPUS = [("Intel(R) Data Center GPU Max 1550", 2, 131072), ("Intel(R) Data Center GPU Max 1100", 1, 49152),
        ("Intel(R) Data Center GPU Flex 170", 1, 16384), ("Intel(R) Data Center GPU Flex 140", 1, 6144),
        ("Intel(R) Arc(TM) A770 Graphics", 1, 16384), ("Intel(R) Data Center GPU Max 1450", 2, 131072)]


def box(d, rows, w1, w2, header=None):
    rule = "+" + "-" * (w1 + 2) + "+" + "-" * (w2 + 2) + "+"
    d.skip(rule)
    if header:
        d.line(f"| {header[0].ljust(w1)} | {header[1].ljust(w2)} |", "header", list(header))
        d.skip(rule)
    for group in rows:
        for text, role, cells in group:
            d.line(text, role, cells)
        d.skip(rule)


def discovery(d, rng):
    w1, w2 = 9, rng.choice([84, 86, 92])
    groups = []
    model = rng.choice(GPUS)
    for i in range(rng.randint(1, 8)):
        name, tiles, mem = rng.choice(GPUS) if rng.random() < 0.15 else model
        bdf = f"0000:{rng.choice([0x29, 0x3a, 0x9a, 0xca, 0x18, 0x4d]) + i:02x}:00.0"
        info = [f"Device Name: {name}", "Vendor Name: Intel(R) Corporation",
                f"SOC UUID: 00000000-0000-00{bdf[5:7]}-0000-00{fake.hexid(rng, 6)}8086",
                f"PCI BDF Address: {bdf}", f"DRM Device: /dev/dri/card{i}",
                f"Function Type: {rng.choice(['physical', 'physical', 'virtual'])}"]
        if rng.random() < 0.3:
            info.insert(2, f"UUID: {fake.uuid(rng)}")
        g = []
        for k, txt in enumerate(info):
            if k == 0:
                g.append((f"| {str(i).ljust(w1)} | {txt.ljust(w2)} |", "row", [str(i), txt]))
            else:
                g.append((f"| {''.ljust(w1)} | {txt.ljust(w2)} |", "cont", [txt]))
        groups.append(g)
    box(d, groups, w1, w2, ("Device ID", "Device Information"))


def stats(d, rng):
    name, tiles, mem = rng.choice(GPUS)
    dev = str(rng.randint(0, 7))
    w1, w2 = 27, rng.choice([66, 68])
    items = []

    def per_tile(fn):
        if tiles == 1:
            return fn()
        return [fn() for _ in range(tiles)]

    items.append(("GPU Utilization (%)", per_tile(lambda: str(rng.randint(0, 100)))))
    items.append(("EU Array Active (%)", per_tile(lambda: rng.choice(["N/A", str(rng.randint(0, 100))]))))
    items.append(("EU Array Stall (%)", per_tile(lambda: rng.choice(["N/A", str(rng.randint(0, 30))]))))
    items.append(("EU Array Idle (%)", per_tile(lambda: rng.choice(["N/A", str(rng.randint(0, 100))]))))
    items.append(("GPU Power (W)", str(rng.randint(20, 600))))
    items.append(("GPU Frequency (MHz)", per_tile(lambda: str(rng.choice([300, 900, 1100, 1600, 2050])))))
    items.append(("Media Engine Freq (MHz)", rng.choice(["N/A", str(rng.randint(300, 1600))])))
    items.append(("GPU Core Temperature (C)", per_tile(lambda: str(rng.randint(28, 90)))))
    items.append(("GPU Memory Temperature (C)", per_tile(lambda: rng.choice(["N/A", str(rng.randint(28, 80))]))))
    items.append(("GPU Memory Read (kB/s)", per_tile(lambda: str(rng.randint(0, 9999999)))))
    items.append(("GPU Memory Write (kB/s)", per_tile(lambda: str(rng.randint(0, 9999999)))))
    items.append(("GPU Memory Bandwidth (%)", per_tile(lambda: str(rng.randint(0, 100)))))
    items.append(("GPU Memory Used (MiB)", str(rng.randint(0, mem))))
    items.append(("GPU Memory Util (%)", str(rng.randint(0, 100))))
    if rng.random() < 0.5:
        items.append(("Xe Link Throughput (kB/s)", "N/A"))
    items = [it for it in items if it[0] in ("GPU Utilization (%)", "GPU Power (W)") or rng.random() < 0.85]
    groups = [[(f"| {'Device ID'.ljust(w1)} | {dev.ljust(w2)} |", "kv", ["Device ID", dev])]]
    body = []
    for k, v in items:
        if isinstance(v, list):
            pairs = [(f"Tile {t}", x) for t, x in enumerate(v)]
            txt = "; ".join(f"{a}: {b}" for a, b in pairs)
            cells = [k] + [c for p in pairs for c in p]
            body.append((f"| {k.ljust(w1)} | {txt.ljust(w2)} |", "row", cells))
        else:
            body.append((f"| {k.ljust(w1)} | {v.ljust(w2)} |", "kv", [k, v]))
    groups.append(body)
    box(d, groups, w1, w2)


def generate(rng):
    d = Doc()
    if rng.random() < 0.5:
        discovery(d, rng)
    else:
        stats(d, rng)
    return d
