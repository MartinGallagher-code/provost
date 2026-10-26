"""HPE `hpasmcli -s "show temp; show fans; ..."`: each command's report after
a blank line: dashed-rule tables (temp, fans) or key: value blocks
(power supplies, DIMMs)."""
from lib import Doc

TOOL = "hpasmcli"

ZONES = ["AMBIENT", "CPU#1", "CPU#2", "MEMORY_BD", "MEMORY_BD", "SYSTEM_BD", "SYSTEM_BD", "POWER_SUPPLY",
         "POWER_SUPPLY", "I/O_ZONE", "I/O_ZONE", "PROCESSOR_ZONE", "PROCESSOR_ZONE", "CHASSIS", "STORAGE_BAY"]


def f_of(c):
    return round(c * 9 / 5 + 32)


def temps(d, rng):
    d.line("Sensor   Location              Temp       Threshold", "header", ["Sensor", "Location", "Temp", "Threshold"])
    d.skip("------   --------              ----       ---------")
    zones = ZONES[:rng.randint(4, len(ZONES))]
    for i, z in enumerate(zones, 1):
        if rng.random() < 0.15:
            t, th = "-", "-"
        else:
            c = rng.randint(18, 75)
            lim = rng.choice([42, 70, 82, 87, 95, 105, 110])
            t, th = f"{c}C/{f_of(c)}F", f"{lim}C/{f_of(lim)}F"
        sid = f"#{i}"
        d.line(f"{sid.ljust(9)} {z.ljust(20)} {t.ljust(10)} {th}", "row", [sid, z, t, th])


def fans(d, rng):
    head = ["Fan", "Location", "Present", "Speed", "of max", "Redundant", "Partner", "Hot-pluggable"]
    d.line("Fan  Location        Present Speed  of max  Redundant  Partner  Hot-pluggable", "header", head)
    d.skip("---  --------        ------- -----  ------  ---------  -------  -------------")
    n = rng.choice([2, 4, 6, 8])
    for i in range(1, n + 1):
        present = rng.choices(["Yes", "No"], [9, 1])[0]
        loc = rng.choice(["SYSTEM", "PROCESSOR_ZONE", "I/O_ZONE", "POWER_SUPPLY", "VIRTUAL"])
        if present == "Yes":
            speed = rng.choices(["NORMAL", "HIGH", "LOW"], [8, 2, 1])[0]
            pct = f"{rng.randint(10, 100)}%"
            red = rng.choice(["Yes", "Yes", "No", "N/A"])
            partner = str(i + 1 if i % 2 else i - 1) if red == "Yes" else "N/A"
            hp = rng.choice(["Yes", "Yes", "No"])
        else:
            speed, pct, red, partner, hp = "-", "-", "-", "-", "-"
        sid = f"#{i}"
        line = (f"{sid.ljust(4)} {loc.ljust(15)} {present.ljust(7)} {speed.ljust(6)} {pct.ljust(7)} "
                f"{red.ljust(10)} {partner.ljust(8)} {hp}")
        d.line(line, "row", [sid, loc, present, speed, pct, red, partner, hp])


def power(d, rng):
    for i in range(1, rng.choice([1, 2, 2, 4]) + 1):
        d.section(f"Power supply #{i}")
        present = rng.choices(["Yes", "No"], [9, 1])[0]
        pairs = [("Present  ", present)]
        if present == "Yes":
            pairs += [("Redundant", rng.choice(["Yes", "No"])),
                      ("Condition", rng.choices(["Ok", "FAILED", "Degraded"], [8, 1, 1])[0]),
                      ("Hotplug  ", rng.choice(["Supported", "Not supported"]))]
            if rng.random() < 0.8:
                pairs.append(("Power    ", f"{rng.randint(40, 900)} Watts"))
        for k, v in pairs:
            d.line(f"\t{k}: {v}", "kv", [k.strip(), v])


def dimms(d, rng):
    d.section("DIMM Configuration")
    d.skip("------------------")
    cpus = rng.choice([1, 2])
    per = rng.choice([2, 4, 6, 8, 12])
    size = rng.choice([4096, 8192, 16384, 32768, 65536])
    speed = rng.choice([1333, 1600, 2133, 2400, 2666, 2933, 3200])
    mtype = rng.choice(["DDR3(10h)", "DDR4(1ah)", "DDR4(1ah)", "N/A"])
    kw = rng.choice([26, 30])
    for c in range(1, cpus + 1):
        for m in sorted(rng.sample(range(1, per * 2 + 1), per)):
            pairs = []
            if rng.random() < 0.3:
                pairs.append(("Cartridge #", "0"))
            pairs += [("Processor #", str(c)), ("Module #", str(m)), ("Present", "Yes"),
                      ("Form Factor", rng.choice(["9h", "Bh"])), ("Memory Type", mtype),
                      ("Size", f"{size} MB"), ("Speed", f"{speed} MHz")]
            if rng.random() < 0.5:
                pairs += [("Supports Lock Step", "No"), ("Configured for Lock Step", "No")]
            pairs.append(("Status", rng.choices(["Ok", "Degraded", "N/A"], [10, 1, 1])[0]))
            for k, v in pairs:
                d.line((k + ":").ljust(kw) + v, "kv", [k, v])
            d.blank()


def generate(rng):
    d = Doc()
    cmds = rng.sample([temps, fans, power, dimms], rng.choice([1, 1, 2, 3]))
    for k, fn in enumerate(cmds):
        if k or rng.random() < 0.8:
            d.blank()
        fn(d, rng)
    if rng.random() < 0.5:
        d.blank()
    return d
