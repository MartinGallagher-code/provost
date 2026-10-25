"""Adaptec/Microsemi `arcconf GETCONFIG 1 AL`: rule-boxed sections of padded
`key : value` lines, per-device subsections, and a completion footer."""
from lib import Doc, fake

TOOL = "arcconf-getconfig"

RULE = "-" * 70
SUB = "   " + "-" * 56


def _kvs(d, pairs, indent, width):
    for k, v in pairs:
        d.kv(k, v, sep=": ", key_width=width, indent=indent)


def _box(d, title):
    d.skip(RULE)
    d.section(title)
    d.skip(RULE)


def _sub(d, title):
    d.skip(SUB)
    d.line("   " + title, "section", [title])
    d.skip(SUB)


def _serial(rng, n=11):
    return "".join(rng.choice("0123456789ABCDEFGHJKLMNPRSTVWXYZ") for _ in range(n))


def generate(rng):
    d = Doc()
    w = rng.choice([40, 41, 44])
    nctl = 1
    d.kv("Controllers found", str(nctl))
    _box(d, "Controller information")
    temp = rng.randint(35, 72)
    pairs = [
        ("Controller Status", rng.choice(["Optimal", "Optimal", "Degraded"])),
        ("Channel description", "SAS/SATA"),
        ("Controller Model", rng.choice(["Adaptec ASR8805", "Adaptec ASR71605", "Adaptec ASR-6405E",
                                         "Microsemi Adaptec SmartRAID 3154-8i", "Adaptec ASR8885Q"])),
        ("Controller Serial Number", _serial(rng)),
        ("Physical Slot", str(rng.randint(1, 6))),
        ("Temperature", f"{temp} C/ {temp * 9 // 5 + 32} F (Normal)"),
        ("Installed memory", rng.choice(["512 MB", "1024 MB", "2048 MB", "4096 MB"])),
        ("Copyback", rng.choice(["Disabled", "Enabled"])),
        ("Background consistency check", rng.choice(["Disabled", "Enabled"])),
        ("Automatic Failover", "Enabled"),
        ("Global task priority", rng.choice(["High", "Medium", "Low"])),
        ("Performance Mode", rng.choice(["Default/Dynamic", "Big Block Bypass", "OLTP/Database"])),
        ("Stayawake period", "Disabled"),
        ("Spinup limit internal drives", "0"),
        ("Spinup limit external drives", "0"),
        ("Defunct disk drive count", str(rng.choice([0, 0, 0, 1]))),
    ]
    nld = rng.randint(1, 3)
    pairs.append(("Logical devices/Failed/Degraded", f"{nld}/0/{rng.choice([0, 0, 1])}"))
    if rng.random() < .5:
        pairs.append(("SSDs assigned to MaxCache", "0"))
    pairs.append(("NCQ status", rng.choice(["Enabled", "Disabled"])))
    if rng.random() < .3:
        pairs.append(("Statistics data collection mode", "Enabled"))
    _kvs(d, pairs, "   ", w)
    _sub(d, "Controller Version Information")
    fw = f"{rng.randint(5, 7)}.{rng.randint(0, 9)}-0 ({rng.randint(19000, 33000)})"
    _kvs(d, [("BIOS", fw), ("Firmware", fw),
             ("Driver", f"1.{rng.randint(1, 2)}-{rng.randint(0, 1)} ({rng.randint(30000, 50000)})"),
             ("Boot Flash", fw)], "   ", w)
    if rng.random() < .6:
        _sub(d, "Controller Battery Information")
        if rng.random() < .5:
            _kvs(d, [("Status", "Not Installed")], "   ", w)
        else:
            _kvs(d, [("Status", "Optimal"), ("Over temperature", "No"),
                     ("Capacity remaining", f"{rng.randint(60, 100)} percent"),
                     ("Time remaining (at current draw)", f"{rng.randint(1, 3)} days, {rng.randint(0, 23)} hours, {rng.randint(0, 59)} minutes")],
                 "   ", w)
    d.blank()

    _box(d, "Logical device information")
    disks = []
    for i in range(nld):
        level = rng.choice(["1", "5", "6", "10", "0"])
        nseg = {"1": 2, "0": rng.randint(1, 4), "5": rng.randint(3, 6), "6": rng.randint(4, 8), "10": 4}[level]
        dsize = rng.choice([286102, 476940, 953869, 1907729, 3815447])
        d.line(f"Logical device number {i}", "section", [f"Logical device number {i}"])
        _kvs(d, [
            ("Logical device name", rng.choice(["system", "data", "backup", "vm", "scratch", fake.word(rng) + str(i)])),
            ("RAID level", level),
            ("Status of logical device", rng.choice(["Optimal", "Optimal", "Degraded", "Rebuilding"])),
            ("Size", f"{dsize * max(1, nseg // 2)} MB"),
            ("Stripe-unit size", rng.choice(["256 KB", "128 KB", "64 KB"])),
            ("Read-cache setting", rng.choice(["Enabled", "Disabled"])),
            ("Write-cache setting", rng.choice(["Enabled (write-back)", "Disabled (write-through)",
                                                "Enabled (write-back) when protected by battery/ZMM"])),
            ("Partitioned", rng.choice(["Yes", "No"])),
            ("Protected by Hot-Spare", rng.choice(["Yes", "No"])),
            ("Bootable", "Yes" if i == 0 else "No"),
            ("Failed stripes", "No"),
            ("Power settings", "Disabled"),
        ], "   ", w)
        _sub(d, "Logical device segment information")
        kind = rng.choice([("SATA", "SSD"), ("SAS", "HDD"), ("SATA", "HDD")])
        for s in range(nseg):
            dev = len(disks)
            serial = _serial(rng, rng.randint(8, 14))
            disks.append((dev, dsize, kind, serial))
            state = rng.choice(["Present"] * 6 + ["Missing", "Rebuilding"])
            v = f"{state} ({dsize}MB, {kind[0]}, {kind[1]}, Connector:{dev // 4}, Device:{dev % 4}) {serial}"
            _kvs(d, [(f"Segment {s}", v)], "   ", w)
        d.blank()

    _box(d, "Physical Device information")
    vendors = [("ATA", "ST4000NM0033-9ZM"), ("ATA", "WDC WD1003FBYX-0"), ("SEAGATE", "ST600MM0088"),
               ("ATA", "Samsung SSD 860"), ("HGST", "HUS726T4TALA6L4"), ("ATA", "INTEL SSDSC2KB48")]
    for dev, dsize, kind, serial in disks[: rng.randint(1, len(disks))]:
        vendor, model = rng.choice(vendors)
        d.line(f"      Device #{dev}", "section", [f"Device #{dev}"])
        d.line("         Device is a Hard drive", "section", ["Device is a Hard drive"])
        pw = w - 6
        pairs = [
            ("State", rng.choice(["Online", "Online", "Ready", "Hot Spare", "Failed"])),
            ("Block Size", "512 Bytes"),
            ("Supported", "Yes"),
            ("Transfer Speed", rng.choice(["SATA 6.0 Gb/s", "SAS 12.0 Gb/s", "SATA 3.0 Gb/s"])),
            ("Reported Channel,Device(T:L)", f"0,{dev}({dev}:0)"),
            ("Reported Location", f"Connector {dev // 4}, Device {dev % 4}"),
            ("Vendor", vendor),
            ("Model", model),
            ("Firmware", rng.choice(["GA0A", "1V02", "RVT04B6Q", "0003", "A3T0"])),
            ("Serial number", serial),
            ("Size", f"{dsize} MB"),
            ("Write Cache", rng.choice(["Enabled (write-back)", "Disabled (write-through)", "Unknown"])),
            ("FRU", "None"),
            ("S.M.A.R.T.", rng.choice(["No", "No", "Yes"])),
        ]
        if rng.random() < .5:
            pairs.append(("S.M.A.R.T. warnings", str(rng.choice([0, 0, 0, 2]))))
        if rng.random() < .5:
            pairs.append(("Power State", rng.choice(["Full rpm", "Powered off"])))
        if kind[1] == "SSD" and rng.random() < .7:
            pairs.append(("SSD", "Yes"))
        _kvs(d, pairs, "         ", pw)
    d.blank()
    d.blank()
    d.skip("Command completed successfully.")
    return d
