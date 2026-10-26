"""`ddcutil detect`: one block per display, nested key: value fields with
an EDID synopsis sub-block, odd per-level padding and occasional prose."""
from lib import Doc

TOOL = "ddcutil-detect"

MONITORS = [("DEL", "Dell Inc.", ["DELL U2719D", "DELL P2419H", "DELL U2723QE", "DELL S2721DGF", "AW3423DW"]),
            ("GSM", "Goldstar Company Ltd (LG)", ["LG HDR 4K", "LG ULTRAGEAR", "27GL850", "LG HDR WQHD"]),
            ("SAM", "Samsung Electric Company", ["LS27A600U", "Odyssey G7", "C27F390", "U28E590"]),
            ("BNQ", "BenQ Corporation", ["BenQ PD2700U", "BenQ GW2480", "BenQ EX2780Q"]),
            ("ACI", "Ancor Communications Inc (ASUS)", ["VG27AQ", "PA278QV", "ROG PG279Q"]),
            ("HWP", "Hewlett Packard", ["HP Z27", "HP E24 G4", "HP 27f"]),
            ("AOC", "AOC International", ["Q27G2G4", "24G2W1G4"]),
            ("PHL", "Philips Consumer Electronics Company", ["PHL 276E8V", "PHL 243V7"])]
PANELS = [("BOE", "BOE Technology Group Co., Ltd"), ("AUO", "AU Optronics"), ("LGD", "LG Display"),
          ("SHP", "Sharp Corporation"), ("CMN", "Chimei Innolux Corporation")]


def serial(rng):
    return "".join(rng.choice("ABCDEFGHJKLMNPRSTVWXY0123456789") for _ in range(rng.choice([7, 8, 12, 13])))


def edid(d, rng, mfg, mname, model):
    d.section("   EDID synopsis:")
    pairs = [("Mfg id", f"{mfg} - {mname}" if rng.random() < 0.7 else mfg), ("Model", model)]
    code = rng.randint(1, 65535)
    pairs.append(("Product code", f"{code}  (0x{code:04x})"))
    pairs.append(("Serial number", serial(rng) if model else ""))
    if rng.random() < 0.6:
        b = rng.randint(0, 2 ** 32 - 1)
        pairs.append(("Binary serial number", f"{b} (0x{b:08x})"))
    for k, v in pairs:
        if v:
            d.line("      " + (k + ":").ljust(22) + v, "kv", [k, v])
        else:
            d.line("      " + (k + ":").ljust(22), "kv", [k])
    y, wk = str(rng.randint(2014, 2025)), str(rng.randint(1, 52))
    if rng.random() < 0.6:
        d.line("      " + "Manufacture year:".ljust(22) + f"{y},  Week: {wk}", "row", ["Manufacture year", y, "Week", wk])
    else:
        d.line("      " + "Manufacture year:".ljust(22) + y, "kv", ["Manufacture year", y])
    if rng.random() < 0.5:
        v = rng.choice(["1.3", "1.4"])
        d.line("      " + "EDID version:".ljust(22) + v, "kv", ["EDID version", v])


def generate(rng):
    d = Doc()
    n = rng.randint(1, 4)
    num = 0
    laptop = rng.random() < 0.4
    new_style = rng.random() < 0.5
    for i in range(n + (1 if laptop else 0)):
        if i:
            d.blank()
        is_panel = laptop and i == n
        bus = str(rng.randint(2, 20))
        invalid = is_panel or rng.random() < 0.1
        if invalid:
            d.section("Invalid display")
        else:
            num += 1
            d.section(f"Display {num}")
        d.line(f"   I2C bus:  /dev/i2c-{bus}", "kv", ["I2C bus", f"/dev/i2c-{bus}"])
        if new_style:
            conn = f"card{rng.choice([0, 1])}-{'eDP' if is_panel else rng.choice(['DP', 'HDMI-A', 'DVI-D'])}-{rng.randint(1, 3)}"
            d.line("   " + "DRM connector:".ljust(25) + conn, "kv", ["DRM connector", conn])
        if is_panel:
            mfg, mname = rng.choice(PANELS)
            edid(d, rng, mfg, mname, rng.choice(["", "", "NE135FBM-N41"]))
            d.skip("   DDC communication failed")
            if rng.random() < 0.7:
                d.skip("   This is an eDP laptop display. Laptop displays do not support DDC/CI.")
            continue
        mfg, mname, models = rng.choice(MONITORS)
        model = rng.choice(models)
        edid(d, rng, mfg, mname, model)
        if invalid:
            d.skip("   DDC communication failed")
            continue
        if new_style and rng.random() < 0.5:
            mon = f"{mfg}:{model}:{serial(rng)}"
            d.line("   " + "Monitor:".ljust(21) + mon, "kv", ["Monitor", mon])
        vcp = rng.choice(["2.1", "2.2", "2.0", "Detection failed"])
        d.line("   " + "VCP version:".ljust(21) + vcp, "kv", ["VCP version", vcp])
    if rng.random() < 0.3:
        d.blank()
    return d
