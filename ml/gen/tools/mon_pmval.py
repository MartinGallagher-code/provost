"""PCP `pmval [-t interval] [-s samples] metric`: a key/value preamble
(metric, host, semantics, units, samples, interval), then either a single
value column or a table whose header names the instances over an unnamed
timestamp column."""
from lib import Doc, fake

TOOL = "pmval"

METRICS = [
    ("kernel.all.load", "instantaneous value", "none", ["1 minute", "5 minute", "15 minute"], (0, 8), 2),
    ("mem.util.free", "instantaneous value", "Kbyte", None, (100000, 9000000), 0),
    ("mem.util.used", "instantaneous value", "Kbyte", None, (100000, 9000000), 0),
    ("disk.dev.read", "cumulative counter (converting to rate)", "count / sec", "disks", (0, 900), 2),
    ("disk.dev.write_bytes", "cumulative counter (converting to rate)", "Kbyte / sec", "disks", (0, 90000), 2),
    ("network.interface.in.bytes", "cumulative counter (converting to rate)", "byte / sec", "nics", (0, 9e6), 1),
    ("kernel.all.cpu.user", "cumulative counter (converting to rate)", "millisec / sec", None, (0, 4000), 1),
    ("kernel.percpu.cpu.idle", "cumulative counter (converting to rate)", "millisec / sec", "cpus", (0, 1000), 1),
    ("filesys.full", "instantaneous value", "none", "fs", (0, 100), 3),
    ("proc.nprocs", "instantaneous value", "none", None, (80, 900), 0),
    ("hinv.ncpu", "discrete instantaneous value", "none", None, (1, 64), 0),
]


def generate(rng):
    d = Doc()
    metric, sem, units, inst, (lo, hi), dp = rng.choice(METRICS)
    if inst == "disks":
        inst = rng.sample(["sda", "sdb", "nvme0n1", "nvme1n1", "vda", "dm-0"], rng.randint(1, 4))
    elif inst == "nics":
        inst = rng.sample(["lo", "eth0", "eth1", "ens3", "enp0s31f6", "wlp2s0", "docker0"], rng.randint(1, 4))
    elif inst == "cpus":
        inst = [f"cpu{i}" for i in range(rng.choice([2, 4, 8]))]
    elif inst == "fs":
        inst = rng.sample(["/dev/sda1", "/dev/mapper/vg0-root", "/dev/nvme0n1p2", "/dev/vdb"], rng.randint(1, 3))
    host = rng.choice([fake.host(rng), "localhost", f"{fake.word(rng)}-{rng.randint(1, 30):02d}"])
    samples = rng.randint(2, 15)
    interval = rng.choice(["1.00", "1.00", "2.00", "5.00", "10.00", "0.50"])
    pairs = [("metric", metric), ("host", host), ("semantics", sem), ("units", units),
             ("samples", str(samples) if rng.random() < .6 else "all")]
    if rng.random() < .85:
        pairs.append(("interval", f"{interval} sec"))
    if rng.random() < .15:
        pairs.insert(0, ("archive", f"/var/log/pcp/pmlogger/{host}/20261025.00.10"))
        pairs.append(("start", f"Sun Oct 25 {rng.randint(0, 9):02d}:00:{rng.randint(10, 59)} 2026"))
    d.kvs(pairs)
    h, m, s = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)
    frac = rng.randint(0, 999)
    step = float(interval)
    rate = "rate" in sem
    sp, rj = rng.choice([3, 4, 6]), rng.choice([1, 8, 10, 12])
    if inst:
        w = max(14, max(len(i) for i in inst) + 2)
        d.line(" " * 12 + "".join(i.rjust(w) for i in inst), "header", [None] + inst)
    else:
        d.blank() if rng.random() < .3 else None
    for k in range(samples):
        t = h * 3600 + m * 60 + s + k * step + frac / 1000
        ts = f"{int(t) // 3600 % 24:02d}:{int(t) // 60 % 60:02d}:{int(t) % 60:02d}.{int(round((t % 1) * 1000)) % 1000:03d}"
        n = len(inst) if inst else 1
        if rate and k == 0 and rng.random() < .5:
            vals = ["?"] * n
        else:
            vals = [f"{rng.uniform(lo, hi):.{dp}f}" if dp else str(rng.randint(int(lo), int(hi))) for _ in range(n)]
            if dp == 3 or (dp and rng.random() < .3):
                vals = [f"{float(v):.4g}" for v in vals]
        if inst:
            d.line(ts.ljust(12) + "".join(v.rjust(w) for v in vals), "row", [ts] + vals)
        else:
            d.line(ts + " " * sp + vals[0].rjust(rj), "row", [ts, vals[0]])
    return d
