"""`nagiostats`: a copyright banner, then CURRENT STATUS DATA as a long
column-aligned key/value report; many keys carry several values separated by
' / ' (min / max / avg, ok / warn / unk / crit, last 1/5/15 min)."""
from lib import Doc

TOOL = "nagiostats"

W = 40


def _dur(rng, big=True):
    d = rng.randint(0, 400) if big else 0
    return f"{d}d {rng.randint(0, 23)}h {rng.randint(0, 59)}m {rng.randint(0, 59)}s"


def _kv(d, key, vals, indent=""):
    vals = vals if isinstance(vals, list) else [vals]
    text = (indent + key + ":").ljust(W) + " / ".join(vals)
    d.line(text, "kv", [key] + vals)


def _mma(rng, hi, unit, dp=3):
    a, b = sorted([rng.uniform(0, hi), rng.uniform(0, hi)])
    avg = rng.uniform(a, b)
    return [f"{a:.{dp}f}", f"{b:.{dp}f}", f"{avg:.{dp}f} {unit}"]


def _last(rng, n, total):
    out, cur = [], rng.randint(0, max(total // 8, 1))
    for _ in range(n):
        out.append(str(cur))
        cur = min(total, cur + rng.randint(0, max(total // 2, 1)))
    return out


def generate(rng):
    d = Doc()
    flavour = rng.choice(["Nagios", "Nagios", "Nagios", "Naemon"])
    ver = rng.choice(["4.4.6", "4.4.14", "4.5.1", "4.0.8", "3.5.1", "1.4.1"])
    d.skip(f"{flavour} Stats {ver}")
    d.skip("Copyright (c) 2003-2008 Ethan Galstad (www.nagios.org)")
    if rng.random() < .8:
        d.kv("Last Modified", rng.choice(["04-28-2020", "11-24-2015", "06-01-2023", "10-08-2024"]))
    d.kv("License", "GPL")
    d.blank()
    d.section("CURRENT STATUS DATA")
    d.skip("-" * 54)
    root = rng.choice(["/usr/local/nagios/var", "/var/lib/nagios4", "/var/cache/nagios3", "/var/cache/naemon"])
    _kv(d, "Status File", f"{root}/status.dat")
    _kv(d, "Status File Age", _dur(rng, False))
    _kv(d, "Status File Version", ver)
    d.blank()
    _kv(d, "Program Running Time", _dur(rng))
    _kv(d, f"{flavour} PID", str(rng.randint(500, 99999)))
    if rng.random() < .3:
        _kv(d, "Used/High/Total Command Buffers", [str(rng.randint(0, 10)), str(rng.randint(0, 64)), "4096"])
    d.blank()

    for kind, total in (("Service", rng.randint(5, 9000)), ("Host", rng.randint(1, 1500))):
        plural = kind + "s"
        checked = total - rng.randint(0, total // 20)
        passive = rng.randint(0, total // 10)
        _kv(d, f"Total {plural}", str(total))
        _kv(d, f"{plural} Checked", str(checked))
        _kv(d, f"{plural} Scheduled", str(checked - rng.randint(0, checked // 20)))
        _kv(d, f"{plural} Actively Checked", str(total - passive))
        _kv(d, f"{plural} Passively Checked", str(passive))
        _kv(d, f"Total {kind} State Change", _mma(rng, 15, "%"))
        _kv(d, f"Active {kind} Latency", _mma(rng, 4, "sec"))
        _kv(d, f"Active {kind} Execution Time", _mma(rng, 12, "sec"))
        _kv(d, f"Active {kind} State Change", _mma(rng, 15, "%"))
        _kv(d, f"Active {plural} Last 1/5/15/60 min", _last(rng, 4, total - passive))
        _kv(d, f"Passive {kind} Latency", _mma(rng, 1, "sec"))
        _kv(d, f"Passive {kind} State Change", _mma(rng, 5, "%"))
        _kv(d, f"Passive {plural} Last 1/5/15/60 min", _last(rng, 4, passive))
        if kind == "Service":
            bad = [rng.randint(0, total // 10) for _ in range(3)]
            _kv(d, "Services Ok/Warn/Unk/Crit", [str(max(total - sum(bad), 0))] + [str(b) for b in bad])
        else:
            bad = [rng.randint(0, total // 10) for _ in range(2)]
            _kv(d, "Hosts Up/Down/Unreach", [str(max(total - sum(bad), 0))] + [str(b) for b in bad])
        _kv(d, f"{plural} Flapping", str(rng.randint(0, 5)))
        _kv(d, f"{plural} In Downtime", str(rng.choice([0, 0, rng.randint(1, 40)])))
        d.blank()

    blocks = [("Active Host Checks Last 1/5/15 min", ["Scheduled", "On-demand", "Parallel", "Serial", "Cached"]),
              ("Passive Host Checks Last 1/5/15 min", []),
              ("Active Service Checks Last 1/5/15 min", ["Scheduled", "On-demand", "Cached"]),
              ("Passive Service Checks Last 1/5/15 min", []),
              ("External Commands Last 1/5/15 min", [])]
    if rng.random() < .3:
        blocks = blocks[:2] + [("Active Service Checks Last 1/5/15 min", ["Scheduled", "On-demand"])] + blocks[3:]
    for key, subs in blocks:
        _kv(d, key, _last(rng, 3, rng.randint(1, 5000)))
        for s in subs:
            _kv(d, s, _last(rng, 3, rng.randint(0, 4000)), indent="   ")
    d.blank()
    if rng.random() < .3:
        d.blank()
    return d
