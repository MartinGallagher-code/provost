"""macOS `networksetup -listallhardwareports`: blank-separated key/value
blocks (Hardware Port / Device / Ethernet Address), then a ruled
`VLAN Configurations` section with optional VLAN blocks."""
from lib import Doc, fake

TOOL = "networksetup-listallhardwareports"


def generate(rng):
    d = Doc()
    ports = [("Ethernet", "en0"), ("Wi-Fi", "en0"), ("Thunderbolt Bridge", "bridge0"),
             ("Thunderbolt 1", "en1"), ("Thunderbolt 2", "en2"), ("Bluetooth PAN", "en5"),
             ("USB 10/100/1000 LAN", "en7"), ("iPhone USB", "en8"), ("Ethernet Adaptor (en4)", "en4"),
             ("Thunderbolt Ethernet Slot 0", "en6"), ("AX88179A", "en9"), ("Belkin USB-C LAN", "en10")]
    chosen = rng.sample(ports, rng.randint(2, 8))
    used = set()
    d.blank()
    for i, (name, dev) in enumerate(chosen):
        if dev in used and dev.startswith("en"):
            dev = f"en{rng.randint(11, 20)}"
        used.add(dev)
        addr = "N/A" if name in ("iPhone USB",) and rng.random() < .5 else fake.mac(rng)
        d.kv("Hardware Port", name)
        d.kv("Device", dev)
        d.kv("Ethernet Address", addr)
        d.blank()
    d.section("VLAN Configurations")
    d.skip("===================")
    for _ in range(rng.choice([0, 0, 0, 1, 2])):
        tag = str(rng.randint(2, 4094))
        d.kv("VLAN User Defined Name", rng.choice([f"vlan{tag}", fake.word(rng).title() + " VLAN", "Lab"]))
        d.kv("Parent Device", rng.choice(["en0", "en4", "en7"]))
        d.kv("Device (VLAN)", f"vlan{rng.randint(0, 4)}")
        d.kv("Tag", tag)
        d.blank()
    return d
