"""BSD/macOS `pfctl -si` (and `-vsi`): a status line with two key/value
pairs, Hostid/Checksum key/values, then aligned Total/Rate tables (interface
stats, state table, counters) with indented sub-headings."""
from lib import Doc, fake

TOOL = "pfctl-si"

COUNTERS = ["match", "bad-offset", "fragment", "short", "normalize", "memory", "bad-timestamp",
            "congestion", "ip-option", "proto-cksum", "state-mismatch", "state-insert", "state-limit",
            "src-limit", "synproxy", "translate", "no-route"]
LIMITS = ["max states per rule", "max-src-states", "max-src-nodes", "max-src-conn", "max-src-conn-rate",
          "overload table insertion", "overload flush states", "synfloods detected", "syncookies sent",
          "syncookies validated"]


def _rate(rng, total, secs):
    return f"{total / max(secs, 1):.1f}/s"


def generate(rng):
    d = Doc()
    secs = rng.randint(30, 90 * 86400)
    days, rem = divmod(secs, 86400)
    up = f"{days} days {rem // 3600:02d}:{rem % 3600 // 60:02d}:{rem % 60:02d}"
    enabled = rng.random() < .9
    state = f"Enabled for {up}" if enabled else "Disabled"
    debug = rng.choice(["Urgent", "Urgent", "Misc", "None", "Loud", "err", "notice"])
    d.line(f"Status: {state}".ljust(rng.choice([46, 47, 50])) + f"Debug: {debug}", "row",
           ["Status", state, "Debug", debug])
    d.blank()
    hid = f"0x{fake.hexid(rng, 8)}"
    if rng.random() < .8:
        d.line(f"Hostid:   {hid}", "kv", ["Hostid", hid])
        ck = f"0x{fake.hexid(rng, 32)}"
        d.line(f"Checksum: {ck}", "kv", ["Checksum", ck])
        d.blank()

    def trow(name, total, rate, ind=2):
        text = (" " * ind + name).ljust(27) + str(total).rjust(14)
        if rate is not None:
            text += rate.rjust(17)
        else:
            text += " " * rng.choice([0, 15])
        d.line(text, "row", [name, str(total), rate])

    if rng.random() < .6:
        ifc = rng.choice(["em0", "en0", "vtnet0", "igb0", "re0", "pppoe0", "bge0"])
        title = f"Interface Stats for {ifc}"
        d.line(title.ljust(27) + "IPv4".rjust(14) + "IPv6".rjust(17), "header", [title, "IPv4", "IPv6"])
        v6 = rng.random() < .5
        b4, b6 = rng.randint(10 ** 5, 10 ** 11), rng.randint(0, 10 ** 9) if v6 else 0
        d.line("  Bytes In".ljust(27) + str(b4).rjust(14) + str(b6).rjust(17), "row", ["Bytes In", str(b4), str(b6)])
        o4, o6 = rng.randint(10 ** 5, 10 ** 11), rng.randint(0, 10 ** 9) if v6 else 0
        d.line("  Bytes Out".ljust(27) + str(o4).rjust(14) + str(o6).rjust(17), "row", ["Bytes Out", str(o4), str(o6)])
        for io in ("In", "Out"):
            d.line(f"  Packets {io}", "section", [f"Packets {io}"])
            for k in ("Passed", "Blocked"):
                p4 = rng.randint(0, 10 ** 8) if k == "Passed" else rng.randint(0, 10 ** 4)
                p6 = rng.randint(0, 10 ** 6) if v6 else 0
                d.line(f"    {k}".ljust(27) + str(p4).rjust(14) + str(p6).rjust(17), "row", [k, str(p4), str(p6)])
        d.blank()

    d.line("State Table".ljust(27) + "Total".rjust(14) + "Rate".rjust(17), "header", ["State Table", "Total", "Rate"])
    cur = rng.randint(0, 50000)
    trow("current entries", cur, None)
    if rng.random() < .4:
        trow("half-open tcp", rng.randint(0, 200), None)
    ins = rng.randint(cur, cur + 10 ** 7)
    for name, tot in (("searches", rng.randint(ins, ins * 40 + 10)), ("inserts", ins), ("removals", ins - cur)):
        trow(name, tot, _rate(rng, tot, secs))
    d.line("Counters" if rng.random() < .8 else "Counters".ljust(rng.randint(9, 80)), "section", ["Counters"])
    for c in COUNTERS[:rng.randint(12, len(COUNTERS))]:
        tot = rng.randint(0, 10 ** 7) if c in ("match", "state-mismatch") else rng.choice([0, 0, 0, rng.randint(0, 9999)])
        trow(c, tot, _rate(rng, tot, secs))
    if rng.random() < .4:
        d.line("Limit Counters", "section", ["Limit Counters"])
        for c in LIMITS[:rng.randint(4, len(LIMITS))]:
            tot = rng.choice([0, 0, rng.randint(0, 500)])
            trow(c, tot, _rate(rng, tot, secs))
    return d
