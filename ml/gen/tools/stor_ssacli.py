"""HPE Smart Array `ssacli ctrl all show config`: an indented tree of
controller, ports, cages, arrays, logical and physical drives, with blank
lines between nodes."""
from lib import Doc, fake

TOOL = "ssacli-ctrl-show-config"

CTRLS = ["Smart Array P440ar", "Smart Array P420i", "Smart Array P840", "Smart Array P408i-a SR Gen10",
         "Smart HBA H240ar", "Smart Array P816i-a SR Gen10", "Smart Array P410i"]


def _sn(rng, n=14):
    return "".join(rng.choice("0123456789ABCDEFGHJKLMNPQRSTUVWXYZ") for _ in range(n))


def generate(rng):
    d = Doc()
    d.blank()
    for c in range(rng.choice([1, 1, 1, 2])):
        ctrl = rng.choice(CTRLS)
        slot = rng.choice(["Slot 0 (Embedded)", "Slot 0 (Embedded)", f"Slot {rng.randint(1, 4)}"])
        sn = _sn(rng)
        head = f"{ctrl} in {slot}"
        d.line(f"{head}{' ' * rng.choice([3, 3, 4])}(sn: {sn})", "row", [head, "sn", sn])
        d.blank()
        ports = rng.sample(["1I", "2I", "3I", "4I", "1E"], rng.randint(1, 3))
        ports.sort()
        if rng.random() < .8:
            d.blank()
            for p in ports:
                d.line(f"   Port Name: {p}", "kv", ["Port Name", p])
                d.blank()
        for p in ports:
            box = rng.choice(["1", "1", "2", "3"])
            text = f"   Internal Drive Cage at Port {p}, Box {box}, OK"
            d.line(text, "row", [f"Internal Drive Cage at Port {p}", f"Box {box}", "OK"])
            d.blank()
        d.blank()
        bay = 1
        ldn = 0
        narr = rng.randint(1, 3)
        for a in range(narr):
            kind = rng.choice([("Solid State SATA", "SATA SSD", ["240 GB", "480 GB", "960 GB", "1.9 TB"]),
                               ("SAS", "SAS HDD", ["300 GB", "600 GB", "900 GB", "1.2 TB", "1.8 TB"]),
                               ("SATA", "SATA HDD", ["1 TB", "2 TB", "4 TB", "8 TB"])])
            free = rng.choice(["0  MB", "0  MB", f"{rng.randint(1000, 900000)}  MB"])
            letter = "ABCDEFG"[a]
            title = f"Array {letter} ({kind[0]}, Unused Space: {free})"
            d.line("   " + title, "section", [title])
            d.blank()
            d.blank()
            for ld in range(rng.choice([1, 1, 1, 2])):
                ldn += 1
                n = ldn
                sz = rng.choice(["447.10 GB", "558.88 GB", "1.09 TB", "1.64 TB", "3.64 TB", "7.28 TB", "279.37 GB"])
                raid = rng.choice(["RAID 1", "RAID 5", "RAID 6", "RAID 1+0", "RAID 0", "RAID 50"])
                st = rng.choice(["OK", "OK", "OK", "Interim Recovery Mode", "Recovering, 37% complete"])
                d.line(f"      logicaldrive {n} ({sz}, {raid}, {st})", "row",
                       ["logicaldrive", str(n), sz, raid, st])
            d.blank()
            dsize = rng.choice(kind[2])
            for _ in range(rng.randint(2, 6)):
                p = rng.choice(ports)
                box = "1"
                pd = f"{p}:{box}:{bay}"
                st = rng.choice(["OK"] * 8 + ["Predictive Failure", "Failed", "Rebuilding"])
                extra = rng.random() < .15
                loc = f"port {p}:box {box}:bay {bay}"
                cells = ["physicaldrive", pd, loc, kind[1], dsize, st]
                text = f"      physicaldrive {pd} ({loc}, {kind[1]}, {dsize}, {st}"
                if extra:
                    text += ", spare"
                    cells.append("spare")
                d.line(text + ")", "row", cells)
                bay += 1
            d.blank()
            d.blank()
        if rng.random() < .5:
            d.line("   unassigned", "section", ["unassigned"])
            d.blank()
            for _ in range(rng.randint(1, 3)):
                p = rng.choice(ports)
                pd = f"{p}:1:{bay}"
                loc = f"port {p}:box 1:bay {bay}"
                kind = rng.choice(["SAS HDD", "SATA SSD", "SATA HDD"])
                sz = rng.choice(["600 GB", "1.2 TB", "480 GB", "4 TB"])
                d.line(f"      physicaldrive {pd} ({loc}, {kind}, {sz}, OK)", "row",
                       ["physicaldrive", pd, loc, kind, sz, "OK"])
                bay += 1
            d.blank()
        if rng.random() < .7:
            wwid = "5" + fake.hexid(rng, 15).upper()
            vid = rng.choice(["PMCSIERA", "HPE", "HP"])
            model = rng.choice(["SRCv8x6G", "SRCv24x6G", "Gen10 ServerBl"])
            num = str(rng.choice([379, 380, 381]))
            port = rng.choice(["Unknown", "1I"])
            d.line(f"   SEP (Vendor ID {vid}, Model {model}) {num}  (WWID: {wwid}, Port: {port})", "row",
                   ["SEP", f"Vendor ID {vid}", f"Model {model}", num, "WWID", wwid, "Port", port])
            d.blank()
        if rng.random() < .4:
            num, wwid = str(rng.randint(370, 380)), "5" + fake.hexid(rng, 15).upper()
            d.line(f"   Expander {num}  (WWID: {wwid}, Port: {ports[0]}, Box: 1)", "row",
                   ["Expander", num, "WWID", wwid, "Port", ports[0], "Box", "1"])
            d.blank()
    return d
