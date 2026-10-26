"""BSD/macOS `pfctl -si` (`-vsi`): a status line with two key/value pairs,
optional host id lines, interface stats and the state table / counters tables
whose first column carries the title."""
from lib import Doc, fake

TOOL = "pfctl-si"

COUNTERS = ["match", "bad-offset", "fragment", "short", "normalize", "memory", "bad-timestamp",
            "congestion", "ip-option", "proto-cksum", "state-mismatch", "state-insert", "state-limit",
            "src-limit", "synproxy", "map-failed", "translate", "dummynet"]


def rate(rng, total, secs):
    return f"{total / secs:.1f}/s"


def generate(rng):
    d = Doc()
    days, secs = rng.randint(0, 200), rng.randint(1, 86399)
    up = f"Enabled for {days} days {secs // 3600:02d}:{secs % 3600 // 60:02d}:{secs % 60:02d}"
    enabled = rng.random() < .85
    status = up if enabled else "Disabled"
    dbg = rng.choice(["Urgent", "None", "Misc", "Loud"])
    text = f"Status: {status}".ljust(rng.choice([46, 46, 50])) + f"Debug: {dbg}"
    d.line(text, "row", ["Status", status, "Debug", dbg])
    total = days * 86400 + secs
    d.blank()
    if rng.random() < .5:
        d.kvs([("Hostid", f"0x{fake.hexid(rng, 8)}"), ("Checksum", f"0x{fake.hexid(rng, 32)}")], sep=": ", align=True)
        d.blank()
    if rng.random() < .7:
        ifn = rng.choice(["em0", "igb0", "vtnet0", "en0", "re0", "ix1"])
        d.line(f"{'Interface Stats for ' + ifn:<27}{'IPv4':>15}{'IPv6':>17}", "header",
               [f"Interface Stats for {ifn}", "IPv4", "IPv6"])
        for top, subs in (("Bytes In", None), ("Bytes Out", None), ("Packets In", ["Passed", "Blocked"]),
                          ("Packets Out", ["Passed", "Blocked"])):
            if subs is None:
                a, b = str(rng.randint(0, 10 ** 10)), str(rng.choice([0, rng.randint(0, 10 ** 7)]))
                d.line(f"  {top:<25}{a:>15}{b:>17}", "row", [top, a, b])
            else:
                d.line(f"  {top}", "row", [top, None, None])
                for s in subs:
                    a, b = str(rng.randint(0, 10 ** 7)), str(rng.choice([0, rng.randint(0, 10 ** 5)]))
                    d.line(f"    {s:<23}{a:>15}{b:>17}", "row", [s, a, b])
        d.blank()
    d.line(f"{'State Table':<27}{'Total':>15}{'Rate':>17}", "header", ["State Table", "Total", "Rate"])
    cur = str(rng.randint(0, 50000))
    d.line(f"  {'current entries':<25}{cur:>15}", "row", ["current entries", cur, None])
    if rng.random() < .4:
        n = str(rng.randint(0, 20))
        d.line(f"  {'half-open tcp':<25}{n:>15}", "row", ["half-open tcp", n, None])
    for k in ("searches", "inserts", "removals"):
        t = rng.randint(0, 10 ** 9)
        a, r = str(t), rate(rng, t, total)
        d.line(f"  {k:<25}{a:>15}{r:>17}", "row", [k, a, r])
    d.section("Counters")
    for k in COUNTERS[:rng.randint(10, len(COUNTERS))]:
        t = rng.choice([0, 0, 0, rng.randint(0, 10 ** 6)])
        a, r = str(t), rate(rng, t, total)
        d.line(f"  {k:<25}{a:>15}{r:>17}", "row", [k, a, r])
    return d
