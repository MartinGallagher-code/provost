"""Grid Engine `qhost`: per-host load and memory as a fixed-width table under a
dashed rule, with a leading `global` pseudo-host of dashes."""
from lib import Doc, fake

TOOL = "qhost"


def _mem(rng, hi):
    v = rng.uniform(0, hi)
    if v >= 1000:
        return f"{v / 1024:.1f}T"
    if v < 1:
        return f"{v * 1024:.1f}M"
    return f"{v:.1f}G"


def generate(rng):
    d = Doc()
    topo = rng.random() < 0.7
    names = ["HOSTNAME", "ARCH", "NCPU"] + (["NSOC", "NCOR", "NTHR"] if topo else []) + \
            ["LOAD", "MEMTOT", "MEMUSE", "SWAPTO", "SWAPUS"]

    def render(v):
        s = f"{v[0]:<23} {v[1]:<13.13}{v[2]:>4}"
        rest = v[3:]
        if topo:
            s += f" {rest[0]:>4} {rest[1]:>4} {rest[2]:>4}"
            rest = rest[3:]
        s += f" {rest[0]:>5} {rest[1]:>7} {rest[2]:>7} {rest[3]:>7} {rest[4]:>7}"
        return s

    head = render(names)
    d.line(head, "header", names)
    d.skip("-" * len(head))
    d.line(render(["global"] + ["-"] * (len(names) - 1)), "row", ["global"] + ["-"] * (len(names) - 1))
    prefix = rng.choice(["node", "compute-0-", "c", "n", "gpu", "hpc-n", "sge-exec"])
    pad = rng.choice([2, 3, 3, 4])
    dom = rng.choice(["", "", ".cluster", ".local", ".hpc.example.edu"])
    arch = rng.choice(["lx-amd64", "lx-amd64", "linux-x64", "lx26-amd64", "lx-arm64"])
    start = rng.randint(1, 40)
    for i in range(rng.randint(2, 18)):
        host = f"{prefix}{start + i:0{pad}d}{dom}"
        soc = rng.choice([1, 2, 2, 4])
        cor = rng.choice([4, 6, 8, 12, 16, 24, 32])
        thr = soc * cor * rng.choice([1, 2])
        mem = rng.choice([31.3, 62.8, 125.8, 251.9, 503.8, 1007.7])
        down = rng.random() < 0.12
        vals = [host, arch, str(thr)]
        if topo:
            vals += [str(soc), str(soc * cor), str(thr)]
        if down:
            vals += ["-", f"{mem:.1f}G" if mem < 1000 else f"{mem / 1024:.1f}T", "-",
                     f"{rng.choice([2.0, 4.0, 8.0, 16.0]):.1f}G", "-"]
        else:
            load = f"{rng.uniform(0, thr * 1.1):.2f}"
            swap = rng.choice([2.0, 4.0, 8.0, 16.0, 32.0])
            vals += [load, f"{mem:.1f}G" if mem < 1000 else f"{mem / 1024:.1f}T", _mem(rng, mem),
                     f"{swap:.1f}G", rng.choice(["0.0", "0.0", _mem(rng, swap)])]
        text = render(vals)
        cells = list(vals)
        cells[1] = cells[1][:13]
        d.line(text, "row", cells)
    return d
