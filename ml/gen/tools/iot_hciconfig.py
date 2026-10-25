"""BlueZ `hciconfig [-a]`: one block per adapter; tab-indented lines holding
one or several `Key: value` pairs, flag words, and byte counters."""
from lib import Doc, fake

TOOL = "hciconfig"

CHIPS = [("Broadcom Corporation (15)", "4.1 (0x7)", "0x168", "0x2209"),
         ("Cypress Semiconductor (305)", "5.0 (0x9)", "0x13a", "0x6119"),
         ("Intel Corp. (2)", "5.2 (0xb)", "0x100", "0x2a2b"),
         ("Cambridge Silicon Radio (10)", "4.0 (0x6)", "0x22bb", "0x22bb"),
         ("Realtek Semiconductor Corporation (93)", "5.1 (0xa)", "0xb", "0x8b6"),
         ("Qualcomm (29)", "5.0 (0x9)", "0x1", "0x25a")]


def pairs_row(d, text, cells):
    d.line(text, "row", cells)


def adapter(d, rng, i, full):
    mac = fake.mac(rng).upper()
    bus = rng.choice(["USB", "UART", "UART", "SDIO", "PCI"])
    acl = rng.choice(["1021:8", "310:10", "1021:4", "678:8", "820:8"])
    sco = rng.choice(["64:1", "64:8", "96:6", "255:12", "0:0"])
    up = rng.random() < .8
    d.line(f"hci{i}:\tType: Primary  Bus: {bus}", "row", [f"hci{i}", "Type", "Primary", "Bus", bus])
    d.line(f"\tBD Address: {mac}  ACL MTU: {acl}  SCO MTU: {sco}", "row",
           ["BD Address", mac, "ACL MTU", acl, "SCO MTU", sco])
    flags = "UP RUNNING" + rng.choice([" PSCAN", " PSCAN ISCAN", "", " ISCAN", " PSCAN AUTH ENCRYPT"]) if up else "DOWN"
    d.line(f"\t{flags} ", "row", [flags])
    rx = [str(rng.randint(0, 10 ** rng.randint(3, 8))), str(rng.randint(0, 999)), "0",
          str(rng.randint(10, 9999)), str(rng.randint(0, 3))]
    tx = [str(rng.randint(0, 10 ** rng.randint(3, 7))), str(rng.randint(0, 999)), "0",
          str(rng.randint(10, 9999)), str(rng.randint(0, 3))]
    d.line(f"\tRX bytes:{rx[0]} acl:{rx[1]} sco:{rx[2]} events:{rx[3]} errors:{rx[4]}", "row",
           ["RX bytes", rx[0], "acl", rx[1], "sco", rx[2], "events", rx[3], "errors", rx[4]])
    d.line(f"\tTX bytes:{tx[0]} acl:{tx[1]} sco:{tx[2]} commands:{tx[3]} errors:{tx[4]}", "row",
           ["TX bytes", tx[0], "acl", tx[1], "sco", tx[2], "commands", tx[3], "errors", tx[4]])
    if not (full and up):
        return
    man, hv, rev, sub = rng.choice(CHIPS)
    feats = " ".join(f"0x{rng.randint(0, 255):02x}" for _ in range(8))
    d.line(f"\tFeatures: {feats}", "kv", ["Features", feats])
    pt = rng.choice(["DM1 DM3 DM5 DH1 DH3 DH5 HV1 HV2 HV3", "DM1 DM3 DM5 DH1 DH3 DH5", "DM1 DH1 HV1"])
    d.line(f"\tPacket type: {pt} ", "kv", ["Packet type", pt])
    lp = rng.choice(["RSWITCH SNIFF", "RSWITCH HOLD SNIFF PARK", "RSWITCH HOLD SNIFF", "SNIFF"])
    d.line(f"\tLink policy: {lp} ", "kv", ["Link policy", lp])
    lm = rng.choice(["SLAVE ACCEPT", "MASTER", "PERIPHERAL ACCEPT", "CENTRAL"])
    d.line(f"\tLink mode: {lm} ", "kv", ["Link mode", lm])
    name = rng.choice(["raspberrypi", "BlueZ 5.55", fake.host(rng).split(".")[0], "ubuntu-0", "rpi-gateway #1"])
    d.line(f"\tName: '{name}'", "kv", ["Name", name])
    cls = rng.choice(["0x000000", "0x0c0000", "0x6c0100", "0x480000", "0x7c010c"])
    d.line(f"\tClass: {cls}", "kv", ["Class", cls])
    sc = rng.choice(["Unspecified", "Rendering, Capturing", "Networking, Rendering, Capturing, Audio, Telephony",
                     "Capturing, Telephony"])
    d.line(f"\tService Classes: {sc}", "kv", ["Service Classes", sc])
    dc = rng.choice(["Miscellaneous, ", "Computer, Desktop workstation", "Computer, Laptop", "Uncategorized, "])
    d.line(f"\tDevice Class: {dc}", "kv", ["Device Class", dc.rstrip(", ") if dc.endswith(", ") else dc])
    d.line(f"\tHCI Version: {hv}  Revision: {rev}", "row", ["HCI Version", hv, "Revision", rev])
    d.line(f"\tLMP Version: {hv}  Subversion: {sub}", "row", ["LMP Version", hv, "Subversion", sub])
    d.line(f"\tManufacturer: {man}", "kv", ["Manufacturer", man])


def generate(rng):
    d = Doc()
    full = rng.random() < .65
    n = rng.choice([1, 1, 1, 2, 2, 3])
    for i in range(n):
        adapter(d, rng, i, full)
        d.blank()
    return d
