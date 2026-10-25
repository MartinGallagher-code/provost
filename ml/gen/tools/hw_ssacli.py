"""HPE `ssacli ctrl all show config`: controllers, arrays and drives as an
indented outline padded with blank lines."""
from lib import Doc, fake

TOOL = "ssacli-ctrl-all-show-config"

CTRLS = ["Smart Array P440ar", "Smart Array P840", "Smart Array P420i", "Smart Array P408i-a SR Gen10",
         "Smart Array P816i-a SR Gen10", "Smart Array E208i-a SR Gen10", "HPE Smart Array P440", "Smart HBA H240ar",
         "Smart Array P410i", "HPE MR416i-a Gen10+"]
SIZES = {"SAS HDD": ["300 GB", "600 GB", "900 GB", "1.2 TB", "1.8 TB", "2.4 TB"],
         "SATA HDD": ["1 TB", "2 TB", "4 TB", "8 TB"],
         "SAS SSD": ["400 GB", "800 GB", "1.6 TB", "3.84 TB"],
         "SATA SSD": ["240 GB", "480 GB", "960 GB", "1.92 TB"]}


def serial(rng, n=14):
    return "".join(rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789") for _ in range(n))


def blanks(d, rng, lo=1, hi=2):
    for _ in range(rng.randint(lo, hi)):
        d.blank()


def drive_line(d, rng, port, box, bay, kind, size):
    state = rng.choices(["OK", "Predictive Failure", "Failed", "Rebuilding"], [20, 1, 1, 1])[0]
    ident = f"{port}:{box}:{bay}"
    loc = f"port {port}:box {box}:bay {bay}"
    d.line(f"      physicaldrive {ident} ({loc}, {kind}, {size}, {state})", "row",
           ["physicaldrive", ident, loc, kind, size, state])


def controller(d, rng, slot):
    name = rng.choice(CTRLS)
    where = "Slot 0 (Embedded)" if slot == 0 else f"Slot {slot}"
    head = f"{name} in {where}"
    sn = serial(rng)
    text = f"{head}   (sn: {sn})"
    d.line(text, "section", [text])
    blanks(d, rng, 2, 2)
    ports = rng.choice([["1I", "2I"], ["1I", "2I"], ["1I"], ["1I", "2I", "3I", "4I"]])
    for p in ports:
        cage = f"Internal Drive Cage at Port {p}"
        state = rng.choices(["OK", "Redundant Path Degraded"], [9, 1])[0]
        d.line(f"   {cage}, Box 1, {state}", "row", [cage, "Box 1", state])
        blanks(d, rng, 2, 3)
    for p in ports:
        d.line(f"   Port Name: {p}", "kv", ["Port Name", p])
        d.blank()
    bays = [(p, b) for p in ports for b in range(1, 5)]
    rng.shuffle(bays)
    hba = "HBA" in name or rng.random() < 0.15
    if hba:
        d.section("   HBA Drives")
        d.blank()
        kind = rng.choice(list(SIZES))
        for p, b in sorted(bays[:rng.randint(1, len(bays))]):
            drive_line(d, rng, p, 1, b, kind, rng.choice(SIZES[kind]))
        d.blank()
    else:
        ldn = 0
        for a in range(rng.randint(1, 3)):
            if not bays:
                break
            kind = rng.choice(list(SIZES))
            size = rng.choice(SIZES[kind])
            unused = rng.choice(["0", "0", str(rng.randint(1000, 3000000))])
            letter = "ABCDEF"[a]
            t = f"Array {letter} ({kind.split()[0]}, Unused Space: {unused}  MB)"
            d.line("   " + t, "section", [t])
            d.blank()
            n = min(len(bays), rng.choice([2, 2, 3, 4, 6]))
            members, bays = sorted(bays[:n]), bays[n:]
            for ld in range(rng.choice([1, 1, 1, 2])):
                raid = rng.choice(["RAID 1", "RAID 1+0", "RAID 5", "RAID 6", "RAID 0", "RAID 1(+0)"])
                cap = f"{rng.uniform(100, 9000):.2f} {rng.choice(['GB', 'GB', 'TB'])}"
                stt = rng.choices(["OK", "Interim Recovery Mode", "Recovering, 37% complete"], [12, 1, 1])[0]
                ldn += 1
                num = str(ldn)
                d.line(f"      logicaldrive {num} ({cap}, {raid}, {stt})", "row",
                       ["logicaldrive", num, cap, raid, stt])
                d.blank()
            for p, b in members:
                drive_line(d, rng, p, 1, b, kind, size)
            d.blank()
        if bays and rng.random() < 0.4:
            d.section("   Unassigned")
            d.blank()
            kind = rng.choice(list(SIZES))
            for p, b in sorted(bays[:rng.randint(1, 3)]):
                drive_line(d, rng, p, 1, b, kind, rng.choice(SIZES[kind]))
            d.blank()
    if rng.random() < 0.7:
        vendor, model = rng.choice([("PMCSIERA", "SRCv8x6G"), ("HPE", "Smart Adapter"), ("HP", "Gen8 ServBP 12+2")])
        num = str(rng.randint(370, 390))
        wwid = fake.hexid(rng, 16).upper()
        d.line(f"   SEP (Vendor ID {vendor}, Model {model}) {num}  (WWID: {wwid})", "row",
               ["SEP", f"Vendor ID {vendor}", f"Model {model}", num, "WWID", wwid])
        d.blank()
    if rng.random() < 0.3:
        num = str(rng.randint(370, 390))
        wwid = fake.hexid(rng, 16).upper()
        d.line(f"   Expander {num}  (WWID: {wwid})", "row", ["Expander", num, "WWID", wwid])
        d.blank()


def generate(rng):
    d = Doc()
    d.blank()
    slots = [0] + ([rng.randint(1, 6)] if rng.random() < 0.3 else [])
    for s in slots:
        controller(d, rng, s)
        d.blank()
    return d
