"""macOS `networksetup -listallhardwareports`: blank-separated key/value
blocks, then a `VLAN Configurations` heading with an `=` rule."""
from lib import Doc, fake

TOOL = "networksetup-listallhardwareports"

PORTS = ["Ethernet", "Wi-Fi", "Thunderbolt Bridge", "Thunderbolt 1", "Thunderbolt 2", "Bluetooth PAN",
         "USB 10/100/1000 LAN", "Belkin USB-C LAN", "iPhone USB", "Thunderbolt Ethernet Slot 0",
         "AX88179A", "Display Ethernet"]


def generate(rng):
    d = Doc()
    d.blank()
    names = rng.sample(PORTS, rng.randint(2, 8))
    en = 0
    for p in names:
        if p == "Thunderbolt Bridge":
            dev, addr = "bridge0", rng.choice(["N/A", fake.mac(rng)])
        elif p.startswith("Thunderbolt ") and p[-1].isdigit():
            dev, addr = f"en{en}", fake.mac(rng); en += 1
        else:
            dev, addr = f"en{en}", fake.mac(rng); en += 1
        d.line(f"Hardware Port: {p}", "kv", ["Hardware Port", p])
        d.line(f"Device: {dev}", "kv", ["Device", dev])
        d.line(f"Ethernet Address: {addr}", "kv", ["Ethernet Address", addr])
        d.blank()
    d.section("VLAN Configurations")
    d.skip("===================")
    for i in range(rng.choice([0, 0, 1, 2])):
        name = rng.choice(["office", "iot", "lab-net", "guest vlan", "storage"])
        d.kv("VLAN User Defined Name", name)
        d.kv("Parent Device", f"en{rng.randint(0, max(en - 1, 0))}")
        d.kv("Device (VLAN) Name", f"vlan{i}")
        d.kv("Tag", str(rng.randint(2, 4094)))
        d.blank()
    return d
