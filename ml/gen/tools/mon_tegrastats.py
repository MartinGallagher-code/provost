"""NVIDIA Jetson `tegrastats`: one line per interval, space-separated
`NAME value` pairs (RAM, SWAP, CPU [load@freq,...], EMC/GR3D freq), then
`sensor@temp` readings and `RAIL cur/avg` power pairs; newer releases prefix
a timestamp."""
from lib import Doc

TOOL = "tegrastats"

BOARDS = {
    "nano": dict(ram=3964, ncpu=4, temps=["PLL", "CPU", "PMIC", "GPU", "AO", "thermal"],
                 rails=["POM_5V_IN", "POM_5V_GPU", "POM_5V_CPU"], unit="", iram=True, new=False),
    "tx2": dict(ram=7860, ncpu=6, temps=["BCPU", "MCPU", "GPU", "PLL", "Tboard", "Tdiode", "PMIC", "thermal"],
                rails=["VDD_IN", "VDD_CPU", "VDD_GPU", "VDD_SOC", "VDD_WIFI", "VDD_DDR"], unit="", iram=False, new=False),
    "xavier": dict(ram=15692, ncpu=8, temps=["AUX", "CPU", "thermal", "Tdiode", "AO", "GPU", "PMIC", "Tboard"],
                   rails=["GPU", "CPU", "SOC", "CV", "VDDRQ", "SYS5V"], unit="", iram=False, new=False),
    "orin": dict(ram=30536, ncpu=12, temps=["CPU", "SOC2", "SOC0", "CV1", "GPU", "tj", "SOC1", "CV2", "CV0"],
                 rails=["VDD_GPU_SOC", "VDD_CPU_CV", "VIN_SYS_5V0", "VDDQ_VDD2_1V8AO"], unit="mW", iram=False, new=True),
    "orin-nano": dict(ram=7620, ncpu=6, temps=["CPU", "SOC2", "SOC0", "CV1", "GPU", "tj", "SOC1", "CV2", "CV0"],
                      rails=["VDD_IN", "VDD_CPU_GPU_CV", "VDD_SOC"], unit="mW", iram=False, new=True),
}


def generate(rng):
    d = Doc()
    b = BOARDS[rng.choice(list(BOARDS))]
    stamp = b["new"] and rng.random() < .85
    n = rng.randint(2, 14)
    step = rng.choice([1, 1, 2, 5])
    mo, dd, hh, mm, ss = rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    offline = set(rng.sample(range(b["ncpu"]), rng.choice([0, 0, 2]))) if b["ncpu"] > 4 else set()
    ram = rng.randint(800, b["ram"] - 200)
    swap_total = b["ram"] // 2
    avg = {r: rng.randint(100, 4000) for r in b["rails"]}
    dead = {t for t in b["temps"] if t.startswith("CV") or (t == "GPU" and b["new"] and rng.random() < .5)}
    vic = rng.random() < .5
    emc_at = b["new"] or rng.random() < .5
    for i in range(n):
        cells, parts = [], []

        def add(*vals):
            for v in vals:
                parts.append(v)
                cells.append(v)

        if stamp:
            t = hh * 3600 + mm * 60 + ss + i * step
            ts = f"{mo:02d}-{dd:02d}-2026 {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"
            add(ts)
        ram = max(300, min(b["ram"] - 50, ram + rng.randint(-40, 40)))
        add("RAM", f"{ram}/{b['ram']}MB", f"(lfb {rng.randint(1, 400)}x4MB)")
        add("SWAP", f"{rng.choice([0, 0, rng.randint(1, 900)])}/{swap_total}MB", f"(cached {rng.randint(0, 40)}MB)")
        if b["iram"]:
            parts.append(f"IRAM 0/252kB(lfb 252kB)")
            cells.extend(["IRAM", "0/252kB(lfb 252kB)"])
        cpus = ",".join("off" if c in offline else f"{rng.randint(0, 100)}%@{rng.choice([102, 345, 729, 1190, 1479, 1728, 2035])}"
                        for c in range(b["ncpu"]))
        add("CPU", f"[{cpus}]")
        add("EMC_FREQ", f"{rng.randint(0, 40)}%@{rng.choice([1600, 2133, 3199])}" if emc_at
            else f"{rng.randint(0, 40)}%")
        gr = f"{rng.randint(0, 99)}%@{rng.choice([76, 306, 624, 921])}"
        add("GR3D_FREQ", f"{rng.randint(0, 99)}%@[{rng.choice([305, 612, 918])}]" if b["new"] else gr)
        if vic:
            add("VIC_FREQ", str(rng.choice([115, 345, 601])))
        add("APE", str(rng.choice([25, 150, 174])))
        for t in b["temps"]:
            v = "-256C" if t in dead else (f"{rng.uniform(25, 75):.3f}C" if b["new"] else f"{rng.randint(25, 70)}" +
                                           rng.choice(["C", ".5C", "C", ".25C"]))
            parts.append(f"{t}@{v}")
            cells.extend([t, v])
        for r in b["rails"]:
            cur = max(0, avg[r] + rng.randint(-300, 300))
            add(r, f"{cur}{b['unit']}/{avg[r]}{b['unit']}")
        d.line(" ".join(parts), "row", cells)
    return d
