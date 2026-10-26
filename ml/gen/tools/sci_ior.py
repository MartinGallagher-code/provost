"""IOR parallel I/O benchmark: a run header of `Key : value` lines, an
`Options:` block, a `Results:` table with a dashed rule, `Max Write/Read`
lines, and a wide right-aligned `Summary of all tests:` table."""
from lib import Doc, fake

TOOL = "ior"

DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def _ts(t):
    import time
    g = time.gmtime(t)
    return f"{DAYS[g.tm_wday]} {MONS[g.tm_mon - 1]} {g.tm_mday:2d} {g.tm_hour:02d}:{g.tm_min:02d}:{g.tm_sec:02d} {g.tm_year}"


def _kv(d, k, v):
    d.line(f"{k:<20}: {v}", "kv", [k, v])


def _human(nbytes):
    for u, f in (("TiB", 2 ** 40), ("GiB", 2 ** 30), ("MiB", 2 ** 20), ("KiB", 2 ** 10)):
        if nbytes >= f:
            v = nbytes / f
            return f"{v:.0f} {u}" if v == int(v) else f"{v:.2f} {u}"
    return f"{nbytes} bytes"


def generate(rng):
    d = Doc()
    ver = rng.choice(["3.3.0", "3.3.0", "3.2.1", "4.0.0", "3.4.0+dev"])
    d.skip(f"IOR-{ver}: MPI Coordinated Test of Parallel I/O")
    t = rng.randint(1_500_000_000, 1_790_000_000)
    api = rng.choice(["POSIX", "POSIX", "MPIIO", "HDF5"])
    fpp = rng.random() < 0.5
    xfer = rng.choice([2 ** 16, 2 ** 18, 2 ** 20, 2 ** 20, 4 * 2 ** 20, 16 * 2 ** 20])
    block = xfer * rng.choice([16, 64, 256, 1024, 4096])
    nodes = rng.choice([1, 2, 4, 8, 16, 32])
    tpn = rng.choice([1, 4, 8, 16, 32, 48, 64])
    tasks = nodes * tpn
    reps = rng.choice([1, 1, 1, 2, 3])
    fsroot = rng.choice(["/scratch", "/lustre/scratch", "/gpfs/projects", "/mnt/beegfs", "/p/gpfs1"])
    user = rng.choice(fake.USERS[1:7] + ["jsmith", "mkhan"])
    path = f"{fsroot}/{user}/ior"
    fname = f"{path}/{rng.choice(['testfile', 'ior.dat', 'iorfile'])}"
    ops = rng.choice([["write", "read"], ["write", "read"], ["write"], ["read"]])
    cmd = ["ior", "-a", api, "-b", _human(block).replace(" ", "").replace("iB", "").lower(), "-t",
           _human(xfer).replace(" ", "").replace("iB", "").lower()]
    if fpp:
        cmd.append("-F")
    cmd += ["-C", "-e"] + (["-w"] if "write" in ops else []) + (["-r"] if "read" in ops else []) + \
        (["-i", str(reps)] if reps > 1 else []) + ["-o", fname]
    _kv(d, "Began", _ts(t))
    _kv(d, "Command line", " ".join(cmd))
    _kv(d, "Machine", f"Linux {rng.choice(['node', 'nid', 'c', 'cn'])}{rng.randint(1, 9999):04d}")
    _kv(d, "TestID", "0")
    _kv(d, "StartTime", _ts(t))
    _kv(d, "Path", path if rng.random() < 0.6 else fname)
    fs = f"{rng.uniform(1, 999):.1f} {rng.choice(['TiB', 'PiB', 'GiB'])}"
    ufs = f"{rng.uniform(1, 99):.1f}%"
    ino = f"{rng.uniform(1, 9999):.1f} {rng.choice(['Mi', 'Gi'])}"
    uino = f"{rng.uniform(0, 99):.1f}%"
    d.line(f"{'FS':<20}: {fs}   Used FS: {ufs}   Inodes: {ino}   Used Inodes: {uino}", "row",
           ["FS", fs, "Used FS", ufs, "Inodes", ino, "Used Inodes", uino])
    d.blank()
    d.section("Options: ")
    _kv(d, "api", api)
    if api == "MPIIO":
        _kv(d, "apiVersion", rng.choice(["(3.1)", "(3.0)"]))
    elif api == "HDF5":
        _kv(d, "apiVersion", rng.choice(["1.12.2", "1.10.7", "1.14.3"]))
    _kv(d, "test filename", fname)
    _kv(d, "access", "file-per-process" if fpp else "single-shared-file")
    _kv(d, "type", rng.choice(["independent", "independent", "collective"]))
    _kv(d, "segments", "1")
    _kv(d, "ordering in a file", "sequential")
    _kv(d, "ordering inter file", rng.choice(["constant task offset", "no tasks offsets"]))
    _kv(d, "task offset", "1")
    _kv(d, "nodes", str(nodes))
    _kv(d, "tasks", str(tasks))
    _kv(d, "clients per node", str(tpn))
    _kv(d, "repetitions", str(reps))
    _kv(d, "xfersize", _human(xfer))
    _kv(d, "blocksize", _human(block))
    _kv(d, "aggregate filesize", _human(block * tasks))
    if rng.random() < 0.3:
        _kv(d, "stonewallingTime", str(rng.choice([30, 60, 300])))
        _kv(d, "stoneWallingWearOut", "0")
    d.blank()
    d.section("Results: ")
    d.blank()
    hdr = ["access", "bw(MiB/s)", "IOPS", "Latency(s)", "block(KiB)", "xfer(KiB)", "open(s)", "wr/rd(s)", "close(s)",
           "total(s)", "iter"]
    w = 10

    def render(vals):
        return "".join(f"{v:<{w}} " for v in vals)
    d.line(render(hdr).rstrip() if rng.random() < 0.5 else render(hdr), "header", hdr)
    d.skip(render(["-" * len(h) for h in hdr]))
    agg = block * tasks / 2 ** 20
    best = {}
    allbw = {o: [] for o in ops}
    for it in range(reps):
        for op in ops:
            bw = rng.uniform(150, 4000) * nodes ** 0.8 if op not in best else best[op] * rng.uniform(0.85, 1.15)
            best.setdefault(op, bw)
            allbw[op].append(bw)
            total = agg / bw
            iops = bw * 2 ** 20 / xfer * rng.uniform(1.0, 1.01)
            lat = total / (block / xfer) * rng.uniform(0.6, 1.0)
            o = total * rng.uniform(0.0005, 0.05)
            c = total * rng.uniform(0.0005, 0.08)
            vals = [op, f"{bw:.2f}", f"{iops:.2f}", f"{lat:.6f}", f"{block // 1024}", f"{xfer / 1024:.2f}",
                    f"{o:.6f}", f"{total - o - c:.2f}", f"{c:.6f}", f"{total:.2f}", str(it)]
            d.line(render(vals), "row", vals)
        if rng.random() < 0.6:
            vals = ["remove"] + ["-"] * 8 + [f"{rng.uniform(0.01, 20):.2f}", str(it)]
            d.line(render(vals), "row", vals)
    for op in ops:
        m = max(allbw[op])
        k = f"Max {op.capitalize()}"
        a, b = f"{m:.2f} MiB/sec", f"({m * 1.048576:.2f} MB/sec)"
        d.line(f"{k + ':':<11}{a} {b}", "kv", [k, a, b])
    d.blank()
    d.section("Summary of all tests:")
    sh = ["Operation", "Max(MiB)", "Min(MiB)", "Mean(MiB)", "StdDev", "Max(OPs)", "Min(OPs)", "Mean(OPs)", "StdDev",
          "Mean(s)", "Stonewall(s)", "Stonewall(MiB)", "Test#", "#Tasks", "tPN", "reps", "fPP", "reord", "reordoff",
          "reordrand", "seed", "segcnt", "blksiz", "xsize", "aggs(MiB)", "API", "RefNum"]
    rows = []
    for op in ops:
        b = allbw[op]
        mean = sum(b) / len(b)
        sd = (sum((x - mean) ** 2 for x in b) / len(b)) ** 0.5
        f = 2 ** 20 / xfer
        rows.append([op, f"{max(b):.2f}", f"{min(b):.2f}", f"{mean:.2f}", f"{sd:.2f}", f"{max(b) * f:.2f}",
                     f"{min(b) * f:.2f}", f"{mean * f:.2f}", f"{sd * f:.2f}", f"{agg / mean:.5f}", "NA", "NA", "0",
                     str(tasks), str(tpn), str(reps), "1" if fpp else "0", "1", "1", "0", "0", "1", str(block),
                     str(xfer), f"{agg:.1f}", api, "0"])
    d.table(sh, rows, gap=1, right=tuple(range(1, len(sh) - 2)) + (len(sh) - 1,))
    _kv(d, "Finished", _ts(t + rng.randint(5, 3600)))
    return d
