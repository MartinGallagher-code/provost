"""CUPS/BSD `lpc status`: one `queue:` heading per printer, then indented
status statements (device, queuing, printing, entries, daemon)."""
from lib import Doc, fake

TOOL = "lpc"

MODELS = ["HP_LaserJet_4250", "Brother_HL-L2350DW", "Canon_iR-ADV_C5535", "EPSON_WF-3720", "lp", "lp0",
          "Xerox_WorkCentre_6515", "office", "label-printer", "Zebra_ZD420", "PDF", "Kyocera_ECOSYS_M2540dn",
          "Ricoh_MP_C3004", "reception", "plotter"]
DEVICES = ["ipp", "ipps", "socket", "usb", "lpd", "dnssd", "parallel", "cups-pdf", "smb", "implicitclass",
           "/dev/null", "hp"]


def generate(rng):
    d = Doc()
    bsd = rng.random() < 0.25
    for q in rng.sample(MODELS, rng.randint(1, 6)):
        d.section(q + ":")
        if not bsd:
            dev = f"'{rng.choice(DEVICES)}'"
            text = f"\tprinter is on device {dev} speed -1"
            d.line(text, "kv", ["printer is on device", dev, "speed -1"])
        for what in ("queuing", "printing"):
            st = "is " + rng.choice(["enabled", "enabled", "enabled", "disabled"])
            d.line(f"\t{what} {st}", "kv", [what, st])
        n = rng.choice([0, 0, 0, 1, rng.randint(2, 40)])
        if bsd:
            ent = "no entries" if n == 0 else f"{n} entr{'y' if n == 1 else 'ies'} in spool area"
            d.line("\t" + ent, "row", [ent])
            st = rng.choice(["printer idle", f"{q} is ready and printing", "no daemon present",
                             "waiting for printer to become ready (offline ?)",
                             f"{q} is ready and printing via network"])
            d.line("\t" + st, "row", [st])
        else:
            ent = "no entries" if n == 0 else f"{n} entr{'y' if n == 1 else 'ies'}"
            d.line("\t" + ent, "row", [ent])
            d.line("\tdaemon present", "kv", ["daemon", "present"])
    return d
