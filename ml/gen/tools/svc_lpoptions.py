"""CUPS `lpoptions -l`: one `Option/Label: choice *default choice...` line per
PPD option; sometimes preceded by plain `lpoptions` (key=value pairs)."""
from lib import Doc, fake

TOOL = "lpoptions"

OPTIONS = [
    ("PageSize/Media Size", ["Letter", "Legal", "Executive", "A4", "A5", "A6", "B5", "Env10", "EnvDL", "EnvC5",
                             "EnvMonarch", "Statement", "Custom.WIDTHxHEIGHT"]),
    ("PageRegion/PageRegion", ["Letter", "Legal", "A4", "A5", "Executive"]),
    ("InputSlot/Media Source", ["Default", "Auto", "Tray1", "Tray2", "Tray3", "Manual", "MPTray", "Envelope"]),
    ("Duplex/2-Sided Printing", ["None", "DuplexNoTumble", "DuplexTumble"]),
    ("ColorModel/Output Mode", ["RGB", "CMYK", "Gray", "KGray", "Black"]),
    ("Resolution/Resolution", ["300dpi", "600dpi", "1200dpi", "2400x600dpi", "4800x1200dpi"]),
    ("MediaType/Media Type", ["Plain", "Thick", "Thin", "Bond", "Envelope", "Recycled", "Label", "Transparency",
                              "Glossy", "PhotographicGlossy"]),
    ("cupsPrintQuality/Print Quality", ["Draft", "Normal", "High"]),
    ("OutputBin/Output Tray", ["Default", "FaceDown", "FaceUp", "Stacker1"]),
    ("TonerSaveMode/Toner Save", ["Off", "On"]),
    ("HPOption_Tray3/Tray 3", ["False", "True"]),
    ("StapleLocation/Staple", ["None", "UpperLeft", "UpperRight", "DualLeft"]),
    ("Collate/Collate", ["False", "True"]),
    ("BRMonoColor/Color / Mono", ["Auto", "FullColor", "Mono"]),
    ("Halftone/Halftoning", ["Default", "Fine", "Smooth", "Enhanced"]),
    ("print-color-mode/Print Color Mode", ["color", "monochrome"]),
]


def plain(d, rng):
    name = rng.choice(["Office_Printer", "HP_LaserJet", "Brother_HL", "lobby", "PDF"])
    info = rng.choice(["HP LaserJet 4250", "Brother HL-L2350DW series", "Office Printer", "Lobby colour"])
    loc = rng.choice(["Room 101", "2nd floor", "Reception", "lab"])
    pairs = [("copies", "1"),
             ("device-uri", f"{rng.choice(['ipp', 'socket', 'dnssd', 'usb'])}://{fake.ip(rng)}/"
                            f"{rng.choice(['ipp/print', 'printers/' + name, ''])}"),
             ("finishings", "3"), ("job-cancel-after", "10800"), ("job-hold-until", "no-hold"),
             ("job-priority", "50"), ("job-sheets", "none,none"),
             ("marker-change-time", str(rng.randint(0, 1700000000))),
             ("number-up", "1"), ("printer-commands", "none"),
             ("printer-info", f"'{info}'"), ("printer-is-accepting-jobs", "true"),
             ("printer-is-shared", rng.choice(["true", "false"])), ("printer-is-temporary", "false"),
             ("printer-location", f"'{loc}'"), ("printer-make-and-model", f"'{info}'"),
             ("printer-state", str(rng.choice([3, 4, 5]))),
             ("printer-state-change-time", str(rng.randint(1500000000, 1800000000))),
             ("printer-state-reasons", rng.choice(["none", "media-empty-warning", "toner-low-report"])),
             ("printer-type", str(rng.randint(4000, 9000000))),
             ("printer-uri-supported", f"ipp://localhost/printers/{name}")]
    keep = [p for p in pairs if rng.random() < 0.8] or pairs[:3]
    text = " ".join(f"{k}={v}" for k, v in keep)
    cells = [c for kv in keep for c in kv]
    d.line(text, "row", cells)


def generate(rng):
    d = Doc()
    if rng.random() < 0.35:
        plain(d, rng)
        if rng.random() < .5:
            d.blank()
    opts = rng.sample(OPTIONS, rng.randint(2, len(OPTIONS)))
    for key, choices in opts:
        ch = choices[:]
        if len(ch) > 4 and rng.random() < .5:
            ch = rng.sample(ch, rng.randint(3, len(ch)))
        dflt = rng.randrange(len(ch))
        vals = [("*" + c) if i == dflt else c for i, c in enumerate(ch)]
        d.line(f"{key}: " + " ".join(vals), "kv", [key] + vals)
    return d
