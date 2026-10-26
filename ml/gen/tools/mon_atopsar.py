"""`atopsar -c|-m|-d|-p`: a uname banner, a dashed `analysis date` line, then
per report a header whose first field is the start time and whose last is
the report tag (`_cpu_`), and rows per interval; per-CPU / per-disk rows
leave the time column empty."""
from lib import Doc, fake

TOOL = "atopsar"


def _t(sec):
    return f"{sec // 3600 % 24:02d}:{sec // 60 % 60:02d}:{sec % 60:02d}"


def _cpu(rng, ncpu, per):
    out = []
    tot = ncpu * 100
    for c in (["all"] + ([str(i) for i in range(ncpu)] if per else [])):
        scale = tot if c == "all" else 100
        usr, sys_, wait = rng.randint(0, scale // 3), rng.randint(0, scale // 8), rng.randint(0, scale // 10)
        irq = rng.randint(0, 2)
        idle = max(scale - usr - sys_ - wait - irq, 0)
        out.append((c, [str(usr), str(rng.randint(0, 2)), str(sys_), str(irq), str(rng.randint(0, 3)), "0", "0",
                        str(wait), str(idle)]))
    return out


REPORTS = {
    "cpu": (["cpu", "%usr", "%nice", "%sys", "%irq", "%softirq", "%steal", "%guest", "%wait", "%idle"], "_cpu_"),
    "mem": (["memtotal", "memfree", "buffers", "cached", "dirty", "slabmem", "swptotal", "swpfree"], "_mem_"),
    "dsk": (["disk", "busy", "read/s", "KB/read", "writ/s", "KB/writ", "avque", "avserv"], "_dsk_"),
    "prc": (["procs", "running", "sleep", "sleep_d", "zombie", "clones", "exits"], "_prc_"),
    "swp": (["pagescan/s", "swapin/s", "swapout/s", "oomkill", "commitspc", "commitlim"], "_mem_"),
}


def _M(rng, hi):
    return f"{rng.randint(1, hi)}M"


def generate(rng):
    d = Doc()
    host = f"{fake.word(rng)}-{rng.randint(1, 30):02d}"
    kern, build = rng.choice([("5.15.0-88-generic", "#98-Ubuntu SMP Mon Oct 2 15:18:56 UTC 2023"),
                              ("6.1.0-18-amd64", "#1 SMP PREEMPT_DYNAMIC Debian 6.1.76-1 (2024-02-01)"),
                              ("4.18.0-513.el8.x86_64", "#1 SMP Thu Nov 16 10:04:13 UTC 2023"),
                              ("6.8.0-45-generic", "#45-Ubuntu SMP PREEMPT_DYNAMIC Fri Aug 30 12:02:04 UTC 2024")])
    y, mo, dd = 2026, rng.randint(1, 12), rng.randint(1, 28)
    date = f"{y}/{mo:02d}/{dd:02d}"
    if rng.random() < .7:
        d.blank()
    d.skip(f"{host}  {kern}  {build}  x86_64  {date}")
    d.blank()
    lead = "-" * 26
    d.line(f"{lead} analysis date: {date} {lead}", "kv", ["analysis date", date])
    ncpu = rng.choice([2, 4, 8])
    disks = rng.sample(["sda", "sdb", "nvme0n1", "nvme1n1", "vda", "dm-0", "md0"], rng.randint(1, 3))
    memtot = rng.choice([1987, 3936, 7951, 15876, 64302])
    start = rng.randint(0, 20) * 3600 + rng.choice([1, 0])
    step = rng.choice([60, 300, 600])
    n = rng.randint(2, 8)
    for rep in rng.sample(list(REPORTS), rng.randint(1, 2)):
        cols, tag = REPORTS[rep]
        header = [_t(start)] + cols + [tag]
        rows = []
        for i in range(1, n + 1):
            ts = _t(start + i * step)
            if rep == "cpu":
                per = rng.random() < .3
                for k, (c, v) in enumerate(_cpu(rng, ncpu, per)):
                    rows.append([ts if k == 0 else None, c] + v + [None])
            elif rep == "mem":
                free = rng.randint(50, memtot)
                rows.append([ts, f"{memtot}M", f"{free}M", _M(rng, 300), _M(rng, memtot // 2), f"{rng.randint(0, 90)}M",
                             _M(rng, 400), f"{memtot // 2}M", f"{rng.randint(0, memtot // 2)}M", None])
            elif rep == "dsk":
                for k, dk in enumerate(disks):
                    rows.append([ts if k == 0 else None, dk, f"{rng.randint(0, 99)}%", f"{rng.uniform(0, 900):.1f}",
                                 f"{rng.uniform(4, 128):.1f}", f"{rng.uniform(0, 900):.1f}", f"{rng.uniform(4, 128):.1f}",
                                 f"{rng.uniform(1, 9):.1f}", f"{rng.uniform(0.01, 20):.2f} ms", None])
            elif rep == "prc":
                tot = rng.randint(100, 900)
                rows.append([ts, str(tot), str(rng.randint(0, 9)), str(tot - rng.randint(1, 20)), str(rng.randint(0, 3)),
                             str(rng.randint(0, 3)), f"{rng.uniform(0, 90):.2f}", f"{rng.uniform(0, 90):.2f}", None])
            else:
                rows.append([ts, f"{rng.uniform(0, 9):.2f}", f"{rng.uniform(0, 9):.2f}", f"{rng.uniform(0, 9):.2f}",
                             str(rng.choice([0, 0, 0, 1])), f"{rng.randint(500, memtot * 2)}M", f"{memtot + memtot // 2}M", None])
        width = [max(len(x or "") for x in [header[c]] + [r[c] for r in rows]) for c in range(len(header))]

        def render(cells):
            out = []
            for c, v in enumerate(cells):
                v = v or ""
                if c == 0:
                    out.append(v.ljust(width[c]))
                elif c == len(cells) - 1 or (rep in ("cpu", "dsk") and c == 1):
                    out.append(v.ljust(width[c]))
                else:
                    out.append(v.rjust(width[c]))
            return "  ".join(out).rstrip()

        d.blank()
        d.line(render(header), "header", header)
        for r in rows:
            d.line(render(r), "row", r)
    return d
