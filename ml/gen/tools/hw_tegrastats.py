"""NVIDIA Jetson `tegrastats`: one fixed-layout status line per interval
(RAM, SWAP, per-core CPU load, clocks, temperatures, rail power)."""
from lib import Doc

TOOL = "tegrastats"

BOARDS = {
    "nano": dict(cores=4, ram=3964, new=False, temps=["PLL", "CPU", "PMIC", "GPU", "AO", "thermal"],
                 rails=["POM_5V_IN", "POM_5V_GPU", "POM_5V_CPU"], iram=True),
    "tx2": dict(cores=6, ram=7860, new=False, temps=["BCPU", "MCPU", "GPU", "PLL", "Tboard", "Tdiode", "PMIC", "thermal"],
                rails=["VDD_IN", "VDD_CPU", "VDD_GPU", "VDD_SOC", "VDD_WIFI", "VDD_DDR"], iram=False),
    "xavier": dict(cores=8, ram=15692, new=True, temps=["CPU", "GPU", "AUX", "AO", "Tboard", "Tdiode", "thermal"],
                   rails=["GPU", "CPU", "SOC", "CV", "VDDRQ", "SYS5V"], iram=False),
    "orin": dict(cores=12, ram=30536, new=True, temps=["CPU", "GPU", "SOC0", "SOC1", "SOC2", "CV0", "CV1", "CV2", "tj"],
                 rails=["VDD_GPU_SOC", "VDD_CPU_CV", "VIN_SYS_5V0", "VDDQ_VDD2_1V8AO"], iram=False),
}


def generate(rng):
    d = Doc()
    b = BOARDS[rng.choice(list(BOARDS))]
    cores = b["cores"] if rng.random() < 0.8 else max(2, b["cores"] - 2)
    offline = set(rng.sample(range(cores), rng.randint(0, cores // 2))) if rng.random() < 0.3 else set()
    swap_total = rng.choice([0, b["ram"] // 2, 1982, 4096])
    show_swap = rng.random() < 0.85
    stamp = b["new"] and rng.random() < 0.7
    temps = [t for t in b["temps"] if rng.random() < 0.85] or b["temps"][:2]
    rails = b["rails"]
    used = rng.randint(b["ram"] // 6, b["ram"] - 200)
    two_gpc = b is BOARDS["orin"] and rng.random() < 0.5
    avg = {r: rng.randint(0, 6000) for r in rails}
    sec = rng.randint(0, 50)
    for i in range(rng.randint(3, 14)):
        parts, cells = [], []

        def add(key, val, sep=" "):
            parts.append(f"{key}{sep}{val}")
            cells.extend([key, val])

        if stamp:
            ts = f"10-25-2026 10:{(sec + i) // 60 + 12:02d}:{(sec + i) % 60:02d}"
            parts.append(ts)
            cells.append(ts)
        used = max(100, min(b["ram"] - 50, used + rng.randint(-40, 40)))
        add("RAM", f"{used}/{b['ram']}MB")
        lfb = f"(lfb {rng.randint(1, 900)}x4MB)"
        parts.append(lfb)
        cells.append(lfb)
        if show_swap:
            add("SWAP", f"{rng.randint(0, swap_total // 10) if swap_total else 0}/{swap_total}MB")
            c = f"(cached {rng.randint(0, 20)}MB)"
            parts.append(c)
            cells.append(c)
        if b["iram"]:
            parts.append("IRAM 0/252kB(lfb 252kB)")
            cells.extend(["IRAM", "0/252kB", "(lfb 252kB)"])
        freq = rng.choice([102, 729, 1479, 1190, 2035])
        cpu = ",".join("off" if k in offline else f"{rng.randint(0, 100)}%@{freq}" for k in range(cores))
        add("CPU", f"[{cpu}]")
        add("EMC_FREQ", f"{rng.randint(0, 60)}%@{rng.choice([1600, 2133, 3199])}")
        g = rng.choice([76, 305, 921, 1300])
        add("GR3D_FREQ", f"{rng.randint(0, 99)}%@[{g},{g}]" if two_gpc else f"{rng.randint(0, 99)}%@{g}")
        if b["new"] and rng.random() < 0.5:
            add("VIC_FREQ", str(rng.choice([115, 729])))
        add("APE", str(rng.choice([25, 150, 174, 233])))
        for t in temps:
            if t.startswith("CV") and b is BOARDS["orin"]:
                v = "-256C"
            elif t == "PMIC":
                v = "100C"
            else:
                v = f"{rng.uniform(30, 75):.{rng.choice([0, 1, 2])}f}C".replace(".0C", "C")
            add(t, v, "@")
        for r in rails:
            cur = max(0, avg[r] + rng.randint(-300, 300))
            avg[r] = (avg[r] * 3 + cur) // 4
            add(r, f"{cur}mW/{avg[r]}mW" if b["new"] else f"{cur}/{avg[r]}")
        d.line(" ".join(parts), "row", cells)
    return d
