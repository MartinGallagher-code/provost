"""libqmi `qmicli -d /dev/cdc-wdm0 --nas-get-signal-info | --dms-get-ids |
--nas-get-serving-system | --dms-get-operating-mode`: a status banner, then
tab-indented `Key: 'value'` lines under nested headings."""
from lib import Doc, fake

TOOL = "qmicli"



def kvq(d, depth, key, val, quoted=True, pad=0):
    """`<tabs>Key: 'val'` labelled with the quotes dropped."""
    text = "\t" * depth + key.rjust(pad) + ": " + (f"'{val}'" if quoted else val)
    d.line(text, "kv", [key, val])


def signal(d, rng, dev):
    d.skip(f"[{dev}] Successfully got signal info")
    techs = rng.sample(["WCDMA", "LTE", "5G", "GSM"], rng.randint(1, 3))
    for t in ["GSM", "WCDMA", "LTE", "5G"]:
        if t not in techs:
            continue
        d.section(f"{t}:")
        if t == "GSM":
            kvq(d, 1, "RSSI", f"{rng.randint(-110, -50)} dBm")
        elif t == "WCDMA":
            kvq(d, 1, "RSSI", f"{rng.randint(-110, -50)} dBm")
            kvq(d, 1, "ECIO", f"{rng.uniform(-20, -1):.1f} dBm")
        elif t == "LTE":
            kvq(d, 1, "RSSI", f"{rng.randint(-100, -45)} dBm")
            kvq(d, 1, "RSRQ", f"{rng.randint(-20, -3)} dB")
            kvq(d, 1, "RSRP", f"{rng.randint(-125, -70)} dBm")
            kvq(d, 1, "SNR", f"{rng.uniform(-5, 30):.1f} dB")
        else:
            kvq(d, 1, "RSRP", f"{rng.randint(-125, -70)} dBm")
            kvq(d, 1, "SNR", f"{rng.uniform(-5, 30):.1f} dB")
            if rng.random() < .7:
                kvq(d, 1, "RSRQ", f"{rng.randint(-20, -3)} dB")


def ids(d, rng, dev):
    d.skip(f"[{dev}] Device IDs retrieved:")
    pairs = [("ESN", rng.choice(["0", "80" + fake.hexid(rng, 6)])),
             ("IMEI", "35" + "".join(rng.choice("0123456789") for _ in range(13))),
             ("MEID", rng.choice(["unknown", "A1000" + fake.hexid(rng, 9).upper()]))]
    if rng.random() < .7:
        pairs.append(("IMEI SV", str(rng.randint(1, 99))))
    w = max(len(k) for k, _ in pairs)
    for k, v in pairs:
        kvq(d, 1, k, v, pad=w)


def serving(d, rng, dev):
    d.skip(f"[{dev}] Successfully got serving system:")
    reg = rng.choice(["registered", "not-registered-searching", "registration-denied", "registered"])
    kvq(d, 1, "Registration state", reg)
    kvq(d, 1, "CS", rng.choice(["attached", "detached"]))
    kvq(d, 1, "PS", rng.choice(["attached", "detached"]))
    kvq(d, 1, "Selected network", rng.choice(["3gpp", "3gpp2", "unknown"]))
    radios = rng.sample(["lte", "umts", "gsm", "5gnr"], rng.randint(1, 2))
    kvq(d, 1, "Radio interfaces", str(len(radios)))
    for i, r in enumerate(radios):
        kvq(d, 2, f"[{i}]", r)
    kvq(d, 1, "Roaming status", rng.choice(["off", "on"]))
    caps = rng.sample(["lte", "hsdpa", "hsupa", "wcdma", "edge", "gprs"], rng.randint(1, 3))
    kvq(d, 1, "Data service capabilities", str(len(caps)))
    for i, r in enumerate(caps):
        kvq(d, 2, f"[{i}]", r)
    mcc, mnc = rng.choice([("234", "10"), ("310", "260"), ("262", "1"), ("208", "1"), ("505", "2")])
    desc = rng.choice(["O2 - UK", "T-Mobile", "Telekom.de", "Orange F", "Optus", ""])
    d.section("\tCurrent PLMN:")
    kvq(d, 2, "MCC", mcc)
    kvq(d, 2, "MNC", mnc)
    if desc:
        kvq(d, 2, "Description", desc)
    else:
        d.line("\t\tDescription: ''", "kv", ["Description"])
    if rng.random() < .6:
        d.section("\tRoaming indicators:")
        for r in radios:
            v = rng.choice(["off", "on"])
            text = f"\t\t{r}: '{v}' (current)"
            d.line(text, "kv", [r, f"'{v}' (current)"])
    if rng.random() < .7:
        off = rng.choice([0, 60, -300, 120])
        d.line(f"\t3GPP time zone offset: '{off}' minutes", "kv", ["3GPP time zone offset", f"'{off}' minutes"])
        dst = rng.randint(0, 1)
        d.line(f"\t3GPP daylight saving time adjustment: '{dst}' hours", "kv",
               ["3GPP daylight saving time adjustment", f"'{dst}' hours"])
    kvq(d, 1, "3GPP location area code", str(rng.randint(1, 65534)))
    kvq(d, 1, "3GPP cell ID", str(rng.randint(1000, 268435455)))
    if rng.random() < .6:
        d.section("\tDetailed status:")
        kvq(d, 2, "Status", rng.choice(["available", "limited", "none"]))
        kvq(d, 2, "Capability", rng.choice(["cs-ps", "ps", "cs"]))
        kvq(d, 2, "HDR Status", "none")
        kvq(d, 2, "HDR Hybrid", "no")
        kvq(d, 2, "Forbidden", "no")
    kvq(d, 1, "LTE tracking area code", str(rng.randint(1, 65534)))
    if rng.random() < .5:
        d.section("\tFull operator code info:")
        kvq(d, 2, "MCC", mcc)
        kvq(d, 2, "MNC", mnc.zfill(2))
        kvq(d, 2, "MNC with PCS digit", rng.choice(["no", "yes"]))
    if rng.random() < .4:
        kvq(d, 1, "LTE voice support", rng.choice(["no", "yes"]))


def opmode(d, rng, dev):
    d.skip(f"[{dev}] Operating mode retrieved:")
    kvq(d, 1, "Mode", rng.choice(["online", "low-power", "offline", "persistent-low-power"]))
    kvq(d, 1, "HW restricted", rng.choice(["no", "yes"]))


def generate(rng):
    d = Doc()
    dev = rng.choice(["/dev/cdc-wdm0", "/dev/cdc-wdm1", "/dev/wwan0qmi0"])
    op = rng.choice([signal, ids, serving, serving, opmode, signal])
    op(d, rng, dev)
    if rng.random() < .25:
        d.skip(f"[{dev}] Client ID not released:")
        kvq(d, 1, "Service", rng.choice(["nas", "dms", "wds", "uim"]), pad=7)
        kvq(d, 1, "CID", str(rng.randint(1, 20)), pad=7)
    return d
