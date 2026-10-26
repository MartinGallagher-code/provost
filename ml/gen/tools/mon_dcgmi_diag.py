"""NVIDIA DCGM `dcgmi diag -r 1|2|3`: a status line, then an ASCII box
table (Diagnostic | Result) split into named groups by rule lines that carry
the group name (`|-----  Deployment  ---+---|`); per-GPU results continue on
lines with an empty first column."""
import textwrap

from lib import Doc

TOOL = "dcgmi-diag"

DEPLOY = ["Denylist", "NVML Library", "CUDA Main Library", "Permissions and OS Blocks", "Persistence Mode",
          "Environment Variables", "Page Retirement/Row Remap", "Graphics Processes", "Inforom"]
LEVELS = {1: [("Deployment", DEPLOY)],
          2: [("Deployment", DEPLOY), ("Integration", ["PCIe"]), ("Hardware", ["GPU Memory"])],
          3: [("Deployment", DEPLOY), ("Integration", ["PCIe"]), ("Hardware", ["GPU Memory", "Diagnostic"]),
              ("Stress", ["Targeted Stress", "Targeted Power", "Memory Bandwidth", "SM Stress"])]}


def generate(rng):
    d = Doc()
    level = rng.choice([1, 2, 3])
    ngpu = rng.choice([1, 2, 4, 8])
    kw, vw = 27, 48
    if rng.random() < .8:
        d.skip("Successfully ran diagnostic for group.")
    rule = "+" + "-" * kw + "+" + "-" * vw + "+"
    d.skip(rule)

    def row(k, v, role="row"):
        text = "| " + k.ljust(kw - 1) + "| " + v.ljust(vw - 1) + "|"
        d.line(text, role, [k, v] if role == "row" else [v])

    def warn(msg):
        parts = textwrap.wrap(msg, vw - 2)
        row("Warning", parts[0])
        for p in parts[1:]:
            row("", p, "cont")

    d.line("| " + "Diagnostic".ljust(kw - 1) + "| " + "Result".ljust(vw - 1) + "|", "header", ["Diagnostic", "Result"])
    d.skip("+" + "=" * kw + "+" + "=" * vw + "+")

    def group(name, end="|"):
        lead = "-----  " + name + "  "
        t = ("|" if end == "|" else "+") + lead.ljust(kw, "-") + "+" + "-" * vw + end
        d.line(t, "section", [name])

    group("Metadata")
    row("DCGM Version", rng.choice(["3.3.5", "3.1.8", "3.3.9", "2.4.7"]))
    if rng.random() < .8:
        row("Driver Version Detected", rng.choice(["535.104.05", "550.54.15", "525.85.12"]))
    ids = ",".join([rng.choice(["20b0", "20b2", "2330", "1db5", "20f1"])] * ngpu)
    row("GPU Device IDs Detected", ids)
    for gi, (gname, tests) in enumerate(LEVELS[level]):
        group(gname, "|" if gi == 0 else "+")
        for t in tests:
            if gname == "Deployment":
                res = "Pass" if rng.random() < .93 else rng.choice(["Fail", "Skip", "Warn"])
                row(t, res)
                if res in ("Fail", "Warn"):
                    warn(rng.choice(["Persistence mode for GPU 0 is disabled. Enable persistence mode with "
                                     "nvidia-smi -pm 1 to avoid issues.",
                                     f"A graphics process is running on GPU {rng.randint(0, ngpu - 1)}",
                                     "Found 1 uncorrectable ECC error on GPU 0. Drain the GPU and reset it or reboot the node."]))
                continue
            fails = {g for g in range(ngpu) if rng.random() < .1}
            skipped = rng.random() < .1
            if skipped:
                row(t, "Skip - All")
            elif not fails:
                row(t, "Pass - All")
            else:
                passing = [g for g in range(ngpu) if g not in fails]
                first = True
                if passing:
                    row(t, "Pass - GPUs: " + ", ".join(map(str, passing)) if len(passing) > 1 else f"Pass - GPU: {passing[0]}")
                    first = False
                for g in sorted(fails):
                    if first:
                        row(t, f"Fail - GPU: {g}")
                        first = False
                    else:
                        row("", f"Fail - GPU: {g}", "cont")
                for g in sorted(fails):
                    msg = rng.choice([f"GPU {g} Error: {rng.randint(1, 900)} DBE detected", f"GPU {g} PCIe bandwidth below threshold",
                                      f"GPU {g} clocks throttled: HW slowdown", f"GPU {g} Memory bandwidth {rng.randint(400, 900)} GB/s is below the {rng.randint(1000, 1500)} GB/s "
                                      "required by the test configuration"])
                    warn(msg)
    d.skip(rule)
    return d
