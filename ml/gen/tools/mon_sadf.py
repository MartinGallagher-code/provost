"""sysstat `sadf -d` (semicolon-separated, one `# hostname;interval;...`
header per activity) or `sadf -p` (tab-separated, headerless
host / interval / timestamp / device / field / value rows)."""
from lib import Doc, fake

TOOL = "sadf"

ACTS = {
    "u": (["CPU", "%user", "%nice", "%system", "%iowait", "%steal", "%idle"], "cpu"),
    "r": (["kbmemfree", "kbavail", "kbmemused", "%memused", "kbbuffers", "kbcached", "kbcommit", "%commit",
           "kbactive", "kbinact", "kbdirty"], None),
    "q": (["runq-sz", "plist-sz", "ldavg-1", "ldavg-5", "ldavg-15", "blocked"], None),
    "b": (["tps", "rtps", "wtps", "dtps", "bread/s", "bwrtn/s", "bdscd/s"], None),
    "n": (["IFACE", "rxpck/s", "txpck/s", "rxkB/s", "txkB/s", "rxcmp/s", "txcmp/s", "rxmcst/s", "%ifutil"], "iface"),
    "d": (["DEV", "tps", "rkB/s", "wkB/s", "dkB/s", "areq-sz", "aqu-sz", "await", "%util"], "dev"),
}


def _vals(rng, act, fields, dev):
    out = []
    for f in fields:
        if f in ("CPU", "IFACE", "DEV"):
            out.append(dev)
        elif f.startswith("kb"):
            out.append(str(rng.randint(1000, 64000000)))
        elif f in ("runq-sz", "blocked"):
            out.append(str(rng.randint(0, 9)))
        elif f == "plist-sz":
            out.append(str(rng.randint(200, 2000)))
        elif f == "%idle":
            out.append(f"{rng.uniform(40, 99.9):.2f}")
        else:
            out.append(f"{rng.choice([0.0, rng.uniform(0, 9), rng.uniform(0, 900)]):.2f}")
    return out


def generate(rng):
    d = Doc()
    host = rng.choice([f"{fake.word(rng)}-{rng.randint(1, 30):02d}", fake.host(rng), "localhost.localdomain"])
    interval = rng.choice([60, 300, 600, 600])
    acts = rng.sample(list(ACTS), rng.randint(1, 3))
    tab = rng.random() < .3
    zone = rng.choice(["UTC", "UTC", ""])
    n = rng.randint(1, 6)
    ncpu = rng.choice([2, 4])
    start = rng.randint(0, 20) * 3600 + rng.choice([0, 1])
    date = f"2026-{rng.randint(1, 10):02d}-{rng.randint(1, 28):02d}"
    ifaces = rng.sample(["lo", "eth0", "ens3", "enp0s31f6", "docker0", "wlan0"], rng.randint(1, 3))
    devs = rng.sample(["sda", "sdb", "nvme0n1", "vda", "dm-0", "dev8-0", "dev253-0"], rng.randint(1, 3))
    for a in acts:
        fields, kind = ACTS[a]
        per_cpu = kind == "cpu" and rng.random() < .4
        if not tab:
            hdr = ["hostname", "interval", "timestamp"] + fields
            d.line("# " + ";".join(hdr), "header", hdr)
        for i in range(1, n + 1):
            t = start + i * interval
            ts = f"{date} {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}" + (f" {zone}" if zone else "")
            if kind == "cpu":
                devlist = ["-1"] + ([str(c) for c in range(ncpu)] if per_cpu else [])
                if tab:
                    devlist = ["all"] + ([f"cpu{c}" for c in range(ncpu)] if per_cpu else [])
            elif kind == "iface":
                devlist = ifaces
            elif kind == "dev":
                devlist = devs
            else:
                devlist = [None]
            for dev in devlist:
                vals = _vals(rng, a, fields, dev)
                if tab:
                    for f, v in zip(fields, vals):
                        if f in ("CPU", "IFACE", "DEV"):
                            continue
                        cells = [host, str(interval), ts, dev if dev else "-", f, v]
                        d.line("\t".join(cells), "row", cells)
                else:
                    cells = [host, str(interval), ts] + vals
                    d.line(";".join(cells), "row", cells)
    return d
