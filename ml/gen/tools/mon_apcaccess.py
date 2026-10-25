"""apcupsd `apcaccess status`: one `KEY      : value` line per UPS
variable (keys padded to nine columns), values carrying units (Volts,
Percent, Minutes) and timestamps, closed by `END APC`."""
from lib import Doc, fake

TOOL = "apcaccess"


def _ts(rng):
    return (f"2026-{rng.randint(1, 10):02d}-{rng.randint(1, 28):02d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:"
            f"{rng.randint(0, 59):02d} {rng.choice(['+0000', '+0100', '-0500', '+0200'])}")


def generate(rng):
    d = Doc()
    model = rng.choice(["Back-UPS XS 1500G", "Smart-UPS 1500", "Back-UPS ES 700G", "Smart-UPS X 3000",
                        "Back-UPS RS 900MI", "Smart-UPS C 1000", "Back-UPS CS 650"])
    smart = "Smart" in model
    volts = rng.choice([120.0, 230.0, 230.0, 240.0])
    on_batt = rng.random() < .15
    status = rng.choice(["ONBATT", "ONBATT LOWBATT"]) if on_batt else rng.choice(["ONLINE", "ONLINE", "ONLINE", "ONLINE CHARGING", "COMMLOST"])
    charge = rng.uniform(5, 99) if on_batt else rng.choice([100.0, 100.0, rng.uniform(60, 100)])
    pairs = [("APC", "001,0{}".format(rng.randint(27, 52)) + f",{rng.randint(600, 1400):04d}"),
             ("DATE", _ts(rng) + rng.choice(["", "  "])),
             ("HOSTNAME", rng.choice([fake.host(rng).split(".")[0], "nas", "pve", "homeserver"])),
             ("VERSION", rng.choice(["3.14.14 (31 May 2016) debian", "3.14.14 (31 May 2016) redhat", "3.14.10 (13 September 2011) unknown"])),
             ("UPSNAME", rng.choice(["ups1", "apcups", "rack-ups", fake.word(rng)])),
             ("CABLE", rng.choice(["USB Cable", "Custom Cable Smart", "Ethernet Link"])),
             ("DRIVER", rng.choice(["USB UPS Driver", "APC Smart UPS (any)", "NETWORK UPS Driver", "MODBUS UPS Driver"])),
             ("UPSMODE", "Stand Alone"), ("STARTTIME", _ts(rng) + rng.choice(["", "  "])),
             ("MODEL", model + rng.choice(["", " "])), ("STATUS", status + " ")]
    if status != "COMMLOST":
        pairs += [("LINEV", f"{0.0 if on_batt else volts + rng.uniform(-6, 6):.1f} Volts"),
                  ("LOADPCT", f"{rng.uniform(3, 85):.1f} Percent"),
                  ("BCHARGE", f"{charge:.1f} Percent"),
                  ("TIMELEFT", f"{rng.uniform(2, 120):.1f} Minutes"),
                  ("MBATTCHG", f"{rng.choice([5, 10, 15])} Percent"),
                  ("MINTIMEL", f"{rng.choice([3, 5, 10])} Minutes"),
                  ("MAXTIME", f"{rng.choice([0, 0, 300])} Seconds")]
        if smart:
            pairs += [("MAXLINEV", f"{volts + rng.uniform(0, 10):.1f} Volts"), ("MINLINEV", f"{volts - rng.uniform(0, 15):.1f} Volts"),
                      ("OUTPUTV", f"{volts:.1f} Volts"), ("ITEMP", f"{rng.uniform(20, 40):.1f} C"),
                      ("LINEFREQ", f"{rng.choice([50.0, 60.0])} Hz")]
        pairs += [("SENSE", rng.choice(["Medium", "High", "Low"])),
                  ("LOTRANS", f"{volts * rng.uniform(.68, .8):.1f} Volts"),
                  ("HITRANS", f"{volts * rng.uniform(1.1, 1.22):.1f} Volts"),
                  ("ALARMDEL", rng.choice(["30 Seconds", "No alarm", "5 Seconds"])),
                  ("BATTV", f"{rng.uniform(12, 28):.1f} Volts"),
                  ("LASTXFER", rng.choice(["Automatic or explicit self test", "Low line voltage", "High line voltage",
                                           "Unacceptable line voltage changes", "No transfers since turnon"])),
                  ("NUMXFERS", str(rng.randint(0, 40))),
                  ("XONBATT", rng.choice(["N/A", _ts(rng) + "  "])),
                  ("TONBATT", f"{rng.randint(0, 900) if on_batt else 0} Seconds"),
                  ("CUMONBATT", f"{rng.randint(0, 90000)} Seconds"),
                  ("XOFFBATT", rng.choice(["N/A", _ts(rng) + "  "])),
                  ("LASTSTEST", _ts(rng) + "  "),
                  ("SELFTEST", rng.choice(["NO", "OK", "NG", "BT"])),
                  ("STESTI", rng.choice(["14 days", "7 days", "None", "336"])),
                  ("STATFLAG", f"0x{rng.choice([0x05000008, 0x05000010, 0x07000008, 0x05060010]):08X} ")]
        if rng.random() < .6:
            pairs += [("MANDATE", f"20{rng.randint(15, 24)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}")]
        pairs += [("SERIALNO", f"{rng.randint(1, 9)}B{rng.randint(1000, 9999)}X{rng.randint(10000, 99999)}  "),
                  ("BATTDATE", f"20{rng.randint(15, 25)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}"),
                  ("NOMINV", f"{int(volts)} Volts"), ("NOMBATTV", f"{rng.choice([12.0, 24.0, 48.0])} Volts"),
                  ("NOMPOWER", f"{rng.choice([390, 410, 540, 865, 900, 980, 2700])} Watts"),
                  ("FIRMWARE", rng.choice(["947.d10 .I USB FW:d10", "UPS 09.3 / ID=18", "925.T2 .I USB FW:T2", "COM 03.6 / UPS 04.1"]))]
    else:
        pairs += [("NOMINV", f"{int(volts)} Volts")]
    pairs.append(("END APC", _ts(rng) + rng.choice(["", "  "])))
    for k, v in pairs:
        d.line(k.ljust(9) + ": " + v, "kv", [k, v.strip()])
    return d
