"""LSI `sas2ircu <ctl> DISPLAY`: a copyright banner, rule-delimited sections
of padded `key : value` lines, `Device is a ...` subsections and a two-line
completion footer."""
from lib import Doc, fake

TOOL = "sas2ircu-display"

RULE = "-" * 72


def _box(d, title):
    d.skip(RULE)
    d.section(title)
    d.skip(RULE)


def _kv(d, k, v, w):
    d.kv(k, v, sep=": ", key_width=w, indent="  ")


def generate(rng):
    d = Doc()
    w = 38
    sas3 = rng.random() < .35
    util = "SAS3IRCU" if sas3 else "SAS2IRCU"
    vendor = rng.choice(["Avago Technologies", "LSI Corporation", "Broadcom Inc."])
    d.skip(f"{vendor} SAS{3 if sas3 else 2} IR Configuration Utility.")
    ver = rng.choice(["20.00.00.00 (2014.09.18)", "16.00.00.00 (2013.03.01)", "17.00.00.00 (2018.04.02)"])
    d.line(f"Version {ver} ", "kv", ["Version", ver])
    d.skip(f"Copyright (c) 2008-{rng.choice([2013, 2014, 2018])} {vendor}. All rights reserved. ")
    d.blank()
    ctl = rng.choice([0, 0, 1])
    d.skip(f"Read configuration has been initiated for controller {ctl}")
    _box(d, "Controller information")
    raid = rng.random() < .6
    for k, v in [("Controller type", rng.choice(["SAS3008", "SAS3108"] if sas3 else ["SAS2008", "SAS2308_2", "SAS2116_1"])),
                 ("BIOS version", rng.choice(["7.39.00.00", "8.37.00.00", "7.29.00.00"])),
                 ("Firmware version", rng.choice(["20.00.07.00", "16.00.10.00", "19.00.00.00"])),
                 ("Channel description", "1 Serial Attached SCSI"),
                 ("Initiator ID", "0"),
                 ("Maximum physical devices", rng.choice(["255", "1023"])),
                 ("Concurrent commands supported", rng.choice(["3432", "9584", "10240"])),
                 ("Slot", str(rng.randint(0, 6))),
                 ("Segment", "0"),
                 ("Bus", str(rng.randint(1, 130))),
                 ("Device", "0"),
                 ("Function", "0"),
                 ("RAID Support", "Yes" if raid else "No")]:
        _kv(d, k, v, w)
    _box(d, "IR Volume information")
    slots = list(range(rng.randint(2, 8)))
    encl = str(rng.choice([1, 1, 2]))
    if raid and rng.random() < .8:
        for vol in range(rng.choice([1, 1, 2])):
            d.line(f"IR volume {vol + 1}", "section", [f"IR volume {vol + 1}"])
            members = slots[vol * 2: vol * 2 + 2] or slots[:2]
            for k, v in [("Volume ID", str(rng.choice([286, 323, 79]) + vol)),
                         ("Status of volume", rng.choice(["Okay (OKY)", "Okay (OKY)", "Degraded (DGD)", "Inactive, Okay (OKY)"])),
                         ("Hot Spare Pool", "0"),
                         ("Volume wwid", fake.hexid(rng, 16)),
                         ("RAID level", rng.choice(["RAID1", "RAID1", "RAID0", "RAID10", "RAID1E"])),
                         ("Size (in MB)", str(rng.choice([952720, 476416, 1906394, 285568]))),
                         ("Boot", rng.choice(["Primary", "Not set"]))]:
                _kv(d, k, v, w)
            d.line("  Physical hard disks".ljust(w + 2) + ":", "section", ["Physical hard disks"])
            for i, s in enumerate(members):
                _kv(d, f"PHY[{i}] Enclosure#/Slot#", f"{encl}:{s}", w)
    _box(d, "Physical device information")
    d.line("Initiator at ID #0", "section", ["Initiator at ID #0"])
    d.blank()
    models = [("ATA", "WDC WD1003FBYX-0", "1V02", "SATA_HDD"), ("ATA", "ST4000NM0033-9ZM", "SN04", "SATA_HDD"),
              ("SEAGATE", "ST600MM0006", "0003", "SAS_HDD"), ("ATA", "Samsung SSD 850", "1B6Q", "SATA_SSD"),
              ("HGST", "HUS726060AL5210", "A907", "SAS_HDD"), ("ATA", "INTEL SSDSC2BB24", "0370", "SATA_SSD")]
    for s in slots:
        vendor, model, fw, dtype = rng.choice(models)
        d.line("Device is a Hard disk", "section", ["Device is a Hard disk"])
        mb = rng.choice([953869, 3815447, 572325, 238475, 5723166])
        state = rng.choice(["Optimal (OPT)", "Optimal (OPT)", "Ready (RDY)", "Hot Spare (HSP)", "Failed (FLD)", "Missing (MIS)"])
        pairs = [("Enclosure #", encl), ("Slot #", str(s)),
                 ("SAS Address", f"4433221-{rng.randint(0, 7)}-{s:04x}-0000"),
                 ("State", state),
                 ("Size (in MB)/(in sectors)", f"{mb}/{mb * 2048 + rng.randint(0, 2047)}"),
                 ("Manufacturer", vendor), ("Model Number", model), ("Firmware Revision", fw),
                 ("Serial No", rng.choice(["WD", "Z1Z", "S2R", "BTWL", ""]) + "".join(rng.choice("0123456789ABCDEFGHJKLMNPRSTVWXYZ") for _ in range(rng.randint(8, 12)))),
                 ("GUID", rng.choice(["N/A", fake.hexid(rng, 16)])),
                 ("Protocol", "SAS" if dtype.startswith("SAS") else "SATA"),
                 ("Drive Type", dtype)]
        for k, v in pairs:
            _kv(d, k, v, w)
        d.blank()
    if rng.random() < .6:
        d.line("Device is a Enclosure services device", "section", ["Device is a Enclosure services device"])
        for k, v in [("Enclosure #", encl), ("Slot #", str(rng.choice([8, 12, 24]))),
                     ("SAS Address", f"500605b-0-{fake.hexid(rng, 4)}-{fake.hexid(rng, 4)}"),
                     ("State", "Standby (SBY)"), ("Manufacturer", rng.choice(["LSI", "Intel", "Supermicro"])),
                     ("Model Number", rng.choice(["SAS2X28", "RES2SV240", "SC826P"])),
                     ("Firmware Revision", rng.choice(["0e12", "0d00", "1.04"])),
                     ("Serial No", "x" + fake.hexid(rng, 8)), ("GUID", "N/A"), ("Protocol", "SAS"),
                     ("Device Type", "Enclosure services device")]:
            _kv(d, k, v, w)
    _box(d, "Enclosure information")
    for k, v in [("Enclosure#", encl), ("Logical ID", f"500605b0:{fake.hexid(rng, 8)}"),
                 ("Numslots", str(rng.choice([8, 12, 24, 36]))), ("StartSlot", "0")]:
        _kv(d, k, v, w)
    d.skip(RULE)
    d.skip(f"{util}: Command DISPLAY Completed Successfully.")
    d.skip(f"{util}: Utility Completed Successfully.")
    return d
