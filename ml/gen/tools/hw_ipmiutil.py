"""`ipmiutil sel`: banner, BMC/SEL summary lines, then the event log as a
fixed-layout table and a completion footer."""
from lib import Doc

TOOL = "ipmiutil-sel"

EVENTS = [("System Event", "Initialized System Boot", "INF", "BMC", "6f"),
          ("System Event", "OEM System Boot Event", "INF", "BIOS", "6f"),
          ("Event Log Disabled", "Log area reset/cleared", "INF", "BMC", "6f"),
          ("Memory", "Correctable ECC, DIMM A1", "MIN", "BIOS", "6f"),
          ("Memory", "Uncorrectable ECC, DIMM B2", "CRT", "BIOS", "6f"),
          ("Processor", "Presence detected", "INF", "BMC", "6f"),
          ("Processor", "Thermal Trip", "CRT", "BMC", "6f"),
          ("Power Supply", "Presence detected", "INF", "BMC", "6f"),
          ("Power Supply", "Failure detected", "MAJ", "BMC", "6f"),
          ("Power Supply", "Power Supply AC lost", "MAJ", "BMC", "6f"),
          ("Temperature", "Upper Non-critical going high", "MIN", "BMC", "01"),
          ("Temperature", "Upper Critical going high", "CRT", "BMC", "01"),
          ("Fan", "Lower Critical going low", "CRT", "BMC", "01"),
          ("Fan", "Redundancy Lost", "MAJ", "BMC", "0b"),
          ("Voltage", "Lower Non-critical going low", "MIN", "BMC", "01"),
          ("Physical Security", "Chassis intrusion", "MAJ", "BMC", "6f"),
          ("Watchdog 2", "Hard reset", "MAJ", "BMC", "6f"),
          ("OS Boot", "boot completed - device not specified", "INF", "SMS", "6f"),
          ("System ACPI Power State", "S0/G0 Working", "INF", "BMC", "6f"),
          ("Power Unit", "Power Off/Down", "INF", "BMC", "6f")]


def generate(rng):
    d = Doc()
    ver = rng.choice(["3.17", "3.1.9", "3.0.7", "3.1.3"])
    d.skip(f"ipmiutil sel version {ver}")
    bmc = rng.choice(["1.17", "2.75", "0.59", "3.48"])
    ipmi = rng.choice(["2.0", "1.5"])
    d.line(f"-- BMC version {bmc}, IPMI version {ipmi} ", "row", ["BMC version", bmc, "IPMI version", ipmi])
    size = rng.choice([3639, 512, 1024, 2048])
    n = rng.randint(3, 25)
    used = n + rng.randint(0, 40)
    sv = rng.choice(["51", "1.5"])
    sup = rng.choice(["0f", "0a", "02"])
    d.line(f"SEL Ver {sv} Support {sup}, Size = {size} records (Used={used}, Free={size - used})", "row",
           ["SEL Ver", sv, "Support", sup, "Size", f"{size} records", "Used", str(used), "Free", str(size - used)])
    head = ["RecId", "Date/Time_______", "SEV", "Src_", "Evt_Type___", "Sens#", "Evt_detail", "Trig", "[Evt_data]"]
    d.line("RecId Date/Time_______ SEV Src_ Evt_Type___ Sens# Evt_detail - Trig [Evt_data]", "header", head)
    rec = rng.randint(1, 60)
    y, mo, dd = rng.randint(19, 26), rng.randint(1, 12), rng.randint(1, 28)
    h, m = rng.randint(0, 23), rng.randint(0, 59)
    pre = rng.random() < 0.3
    for i in range(n):
        if pre and i < 2:
            when = f"Pre-Init  {rng.randint(0, 99999):010d}"
        else:
            m += rng.randint(0, 300)
            h, m = (h + m // 60) % 24, m % 60
            when = f"{mo:02d}/{dd:02d}/{y:02d} {h:02d}:{m:02d}:{rng.randint(0, 59):02d}"
        etype, detail, sev, src, trig = rng.choice(EVENTS)
        sens = f"#{rng.randint(0, 255):02x}"
        data = "[" + " ".join(f"{rng.randint(0, 255):02x}" for _ in range(3)) + "]"
        rid = f"{rec:04x}"
        rec += rng.choice([1, 1, 1, 2, 16])
        d.line(f"{rid} {when} {sev} {src.ljust(4)} {etype} {sens} {detail} {trig} {data}", "row",
               [rid, when, sev, src, etype, sens, detail, trig, data])
    d.skip("ipmiutil sel, completed successfully")
    return d
