"""`ryzenadj --info`: a few key: value facts about the APU, then the power
table as a pipe table (Name | Value | Parameter)."""
from lib import Doc

TOOL = "ryzenadj-info"

FAMILIES = [("Raven", "1e0004", 11), ("Picasso", "1e0005", 11), ("Renoir", "370005", 13), ("Cezanne", "400005", 13),
            ("Rembrandt", "450005", 18), ("Phoenix", "4c0006", 19), ("Vangogh", "3f0004", 17),
            ("Mendocino", "460004", 18), ("Lucienne", "370003", 13), ("Hawk Point", "4c0008", 19)]
ROWS = [("STAPM LIMIT", "stapm-limit", 5, 54), ("STAPM VALUE", None, 0, 40), ("PPT LIMIT FAST", "fast-limit", 10, 65),
        ("PPT VALUE FAST", None, 0, 50), ("PPT LIMIT SLOW", "slow-limit", 10, 54), ("PPT VALUE SLOW", None, 0, 45),
        ("StapmTimeConst", "stapm-time", 50, 500), ("SlowPPTTimeConst", "slow-time", 5, 30),
        ("PPT LIMIT APU", "apu-slow-limit", 15, 54), ("PPT VALUE APU", None, 0, 30),
        ("TDC LIMIT VDD", "vrm-current", 30, 90), ("TDC VALUE VDD", None, 0, 60),
        ("TDC LIMIT SOC", "vrmsoc-current", 10, 30), ("TDC VALUE SOC", None, 0, 20),
        ("EDC LIMIT VDD", "vrmmax-current", 60, 140), ("EDC VALUE VDD", None, 0, 120),
        ("EDC LIMIT SOC", "vrmsocmax-current", 10, 40), ("EDC VALUE SOC", None, 0, 30),
        ("THM LIMIT CORE", "tctl-temp", 70, 100), ("THM VALUE CORE", None, 35, 95),
        ("STT LIMIT APU", "apu-skin-temp", 40, 50), ("STT VALUE APU", None, 30, 50),
        ("STT LIMIT dGPU", "dgpu-skin-temp", 40, 50), ("STT VALUE dGPU", None, 0, 50),
        ("CCLK Boost SETPOINT", "power-saving /", 0, 100), ("CCLK BUSY VALUE", "max-performance", 0, 100)]


def generate(rng):
    d = Doc()
    fam, pm, smu = rng.choice(FAMILIES)
    if rng.random() < 0.15:
        d.skip("Unable to get memory access, retrying with /dev/mem")
    d.kv("CPU Family", fam)
    d.kv("SMU BIOS Interface Version", str(smu))
    ver = rng.choice(["v0.11.1", "v0.13.0", "v0.14.0", "v0.15.0", "v0.12.0"])
    d.line(f"Version: {ver} ", "kv", ["Version", ver])
    d.kv("PM Table Version", pm)
    w = (21, 11, 20)

    d.line("|" + "|".join(h.center(n) for h, n in zip(["Name", "Value", "Parameter"], w)) + "|",
           "header", ["Name", "Value", "Parameter"])
    d.skip("|" + "|".join("-" * n for n in w) + "|")
    rows = ROWS if rng.random() < 0.7 else ROWS[:rng.randint(8, len(ROWS))]
    nan = rng.random() < 0.4
    for name, param, lo, hi in rows:
        if nan and ("dGPU" in name or "APU" in name and "STT" in name) and rng.random() < 0.7:
            val = "nan"
        else:
            val = f"{rng.uniform(lo, hi):.3f}"
            if "LIMIT" in name or "TimeConst" in name:
                val = f"{round(rng.uniform(lo, hi)):.3f}"
        line = f"| {name.ljust(w[0] - 2)} | {val.rjust(w[1] - 2)} | {(param or '').ljust(w[2] - 2)} |"
        d.line(line, "row", [name, val, param])
    return d
