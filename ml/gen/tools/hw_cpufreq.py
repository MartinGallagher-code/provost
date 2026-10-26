"""cpufrequtils `cpufreq-info`: banner, then a block per CPU of key: value
lines (limits, steps, governors, policy prose, frequency, stats)."""
from lib import Doc

TOOL = "cpufreq-info"


def ghz(mhz):
    return f"{mhz / 1000:.2f} GHz" if mhz >= 1000 else f"{mhz} MHz"


def generate(rng):
    d = Doc()
    if rng.random() < 0.85:
        d.skip("cpufrequtils 008: cpufreq-info (C) Dominik Brodowski 2004-2009")
        d.skip("Report errors and bugs to cpufreq@vger.kernel.org, please.")
    driver = rng.choice(["acpi-cpufreq", "intel_pstate", "intel_cpufreq", "amd-pstate", "amd-pstate-epp", "cppc_cpufreq"])
    lo = rng.choice([400, 800, 1200, 1400, 1600])
    hi = rng.choice([2400, 3000, 3400, 3600, 4200, 4700, 5100])
    steps = sorted({hi} | {rng.randrange(lo, hi, 100) for _ in range(rng.randint(2, 8))} | {lo}, reverse=True)
    govs = (["conservative", "ondemand", "userspace", "powersave", "performance", "schedutil"]
            if driver in ("acpi-cpufreq", "intel_cpufreq", "cppc_cpufreq") else ["performance", "powersave"])
    gov = rng.choice(govs)
    ncpu = rng.choice([1, 2, 4, 4, 8])
    smt = rng.random() < 0.5
    latency = rng.choice(["4294.55 ms", "10.0 us", "20.0 us", "0.97 ms", "1 us"])
    for c in range(ncpu):
        d.section(f"analyzing CPU {c}:")
        if driver == "cppc_cpufreq" and rng.random() < 0.05:
            d.skip("  no or unknown cpufreq driver is active on this CPU")
            continue
        d.kv("driver", driver, indent="  ")
        same = f"{c} {c + ncpu}" if smt else str(c)
        d.kv("CPUs which run at the same hardware frequency", same, indent="  ")
        d.kv("CPUs which need to have their frequency coordinated by software", same, indent="  ")
        d.line(f"  maximum transition latency: {latency}.", "kv", ["maximum transition latency", latency])
        d.line(f"  hardware limits: {ghz(lo)} - {ghz(hi)}", "kv", ["hardware limits", ghz(lo), ghz(hi)])
        if driver in ("acpi-cpufreq", "intel_cpufreq"):
            d.kv("available frequency steps", ", ".join(ghz(s) for s in steps), indent="  ")
        d.kv("available cpufreq governors", ", ".join(govs), indent="  ")
        pmin = rng.choice([lo, lo, steps[-2] if len(steps) > 1 else lo])
        pol = f"frequency should be within {ghz(pmin)} and {ghz(hi)}"
        d.line(f"  current policy: {pol}.", "kv", ["current policy", pol])
        d.skip(f"                  The governor \"{gov}\" may decide which speed to use")
        d.skip("                  within this range.")
        cur = ghz(rng.choice(steps) if driver in ("acpi-cpufreq", "intel_cpufreq") else rng.randrange(lo, hi, 10))
        if rng.random() < 0.6:
            v = f"{cur} (asserted by call to hardware)"
        else:
            v = cur
        d.line(f"  current CPU frequency is {v}.", "kv", ["current CPU frequency", v])
        if driver in ("acpi-cpufreq", "intel_cpufreq") and rng.random() < 0.8:
            w = [rng.random() ** 2 for _ in steps]
            tot = sum(w)
            pairs = [(ghz(s), f"{x / tot * 100:.2f}%") for s, x in zip(steps, w)]
            trans = f"({rng.randint(10, 999999)})"
            text = "  cpufreq stats: " + ", ".join(f"{a}:{b}" for a, b in pairs) + f"  {trans}"
            d.line(text, "row", ["cpufreq stats"] + [x for p in pairs for x in p] + [trans])
    return d
