"""OSU Micro-Benchmarks `osu_latency`: `#` banner and column-name lines, then
one row per message size (left-aligned size, right-aligned microseconds)."""
from lib import Doc, fake

TOOL = "osu_latency"


def generate(rng):
    d = Doc()
    v7 = rng.random() < 0.5
    ver = rng.choice(["7.0.1", "7.1", "7.2", "7.3", "7.4"]) if v7 else rng.choice(["5.6.2", "5.6.3", "5.7", "5.7.1", "5.8", "5.9"])
    flavour = rng.choice(["", "", " CUDA", " ROCm"]) if rng.random() < 0.3 else ""
    d.skip(f"# OSU MPI{flavour} Latency Test v{ver}")
    if flavour and rng.random() < 0.8:
        sb, rb = rng.choice(["DEVICE (D)", "HOST (H)"]), rng.choice(["DEVICE (D)", "HOST (H)"])
        d.line(f"# Send Buffer on {sb} and Receive Buffer on {rb}", "row",
               ["Send Buffer on", sb, "Receive Buffer on", rb])
    full = v7 and rng.random() < 0.4
    validate = rng.random() < 0.15
    if v7:
        dt = rng.choice(["MPI_CHAR", "MPI_CHAR", "MPI_INT", "MPI_FLOAT"])
        d.line(f"# Datatype: {dt}.", "kv", ["Datatype", dt])
        cols = ["Avg Latency(us)"] + (["Min Latency(us)", "Max Latency(us)", "Iterations"] if full else [])
    else:
        cols = ["Latency (us)"]
    if validate:
        cols.append("Validation")
    head = "# Size".ljust(10) + "".join(c.rjust(18) for c in cols)
    d.line(head, "header", ["Size"] + cols)
    base = rng.choice([rng.uniform(0.15, 0.6), rng.uniform(0.9, 2.5), rng.uniform(3, 12), rng.uniform(15, 40)])
    bw = rng.uniform(2000, 25000)  # bytes/us
    lo = rng.choice([0, 0, 1, 1])
    hi = rng.choice([22, 22, 22, 20, 16, 23, 24, rng.randint(10, 22)])
    sizes = ([0] if lo == 0 else []) + [2 ** k for k in range(0, hi + 1)]
    dp = 2
    for s in sizes:
        lat = base * rng.uniform(0.97, 1.05) + s / bw
        if s >= 8192:
            lat += base * rng.uniform(0.3, 1.5)  # rendezvous switch
        vals = [f"{lat:.{dp}f}"]
        if full:
            vals += [f"{lat * rng.uniform(0.85, 0.99):.{dp}f}", f"{lat * rng.uniform(1.01, 2.5):.{dp}f}",
                     str(10000 if s <= 8192 else 1000)]
        if validate:
            vals.append(rng.choice(["Pass", "Pass", "Pass", "Pass", "Fail"]))
        text = str(s).ljust(10) + "".join(v.rjust(18) for v in vals)
        d.line(text, "row", [str(s)] + vals)
    return d
