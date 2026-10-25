"""FreeBSD `pciconf -lv`: per device a selector line of key=value pairs, then
indented `key = 'value'` lines."""
from lib import Doc, fake

TOOL = "pciconf-lv"

DEVICES = [
    ("hostb", "0x060000", "0x8086", "Intel Corporation", "Xeon E3-1200 v6/7th Gen Core Processor Host Bridge/DRAM Registers", "bridge", "HOST-PCI"),
    ("pcib", "0x060400", "0x8086", "Intel Corporation", "6th-10th Gen Core Processor PCIe Controller (x16)", "bridge", "PCI-PCI"),
    ("vgapci", "0x030000", "0x8086", "Intel Corporation", "UHD Graphics 630 (Desktop)", "display", "VGA"),
    ("vgapci", "0x030000", "0x10de", "NVIDIA Corporation", "GP107 [GeForce GTX 1050 Ti]", "display", "VGA"),
    ("xhci", "0x0c0330", "0x8086", "Intel Corporation", "200 Series/Z370 Chipset Family USB 3.0 xHCI Controller", "serial bus", "USB"),
    ("ahci", "0x010601", "0x8086", "Intel Corporation", "200 Series PCH SATA controller [AHCI mode]", "mass storage", "SATA"),
    ("nvme", "0x010802", "0x144d", "Samsung Electronics Co Ltd", "NVMe SSD Controller SM981/PM981/PM983", "mass storage", "NVM"),
    ("em", "0x020000", "0x8086", "Intel Corporation", "Ethernet Connection (2) I219-V", "network", "ethernet"),
    ("igb", "0x020000", "0x8086", "Intel Corporation", "I350 Gigabit Network Connection", "network", "ethernet"),
    ("re", "0x020000", "0x10ec", "Realtek Semiconductor Co., Ltd.", "RTL8111/8168/8411 PCI Express Gigabit Ethernet Controller", "network", "ethernet"),
    ("iwm", "0x028000", "0x8086", "Intel Corporation", "Wireless 8265 / 8275", "network", None),
    ("hdac", "0x040300", "0x8086", "Intel Corporation", "200 Series PCH HD Audio", "multimedia", "HDA"),
    ("virtio_pci", "0x020000", "0x1af4", "Red Hat, Inc.", "Virtio network device", "network", "ethernet"),
    ("isab", "0x060100", "0x8086", "Intel Corporation", "Z370 Chipset LPC/eSPI Controller", "bridge", "PCI-ISA"),
    ("ichsmb", "0x0c0500", "0x8086", "Intel Corporation", "200 Series/Z370 Chipset Family SMBus Controller", "serial bus", "SMBus"),
    ("none", "0x118000", "0x8086", "Intel Corporation", "200 Series PCH Thermal Subsystem", "dasp", None),
]


def generate(rng):
    d = Doc()
    counts = {}
    picks = rng.sample(DEVICES, rng.randint(2, 9))
    bus = 0
    for drv, cls, vend, vname, dname, klass, sub in picks:
        n = counts.get(drv, 0)
        counts[drv] = n + 1
        bus += rng.randint(0, 2)
        sel = f"{drv}{n}@pci0:{bus}:{rng.randint(0, 31)}:{rng.randint(0, 7)}"
        pairs = [("class", cls), ("rev", f"0x{rng.randint(0, 0x20):02x}"), ("hdr", "0x01" if drv == "pcib" else "0x00"),
                 ("vendor", vend), ("device", f"0x{rng.randint(0, 0xffff):04x}")]
        if rng.random() < .8:
            pairs += [("subvendor", f"0x{rng.randint(0, 0xffff):04x}"), ("subdevice", f"0x{rng.randint(0, 0xffff):04x}")]
        text = f"{sel}:" + rng.choice(["\t", " "]) + " ".join(f"{k}={v}" for k, v in pairs)
        d.line(text, "row", [sel] + [x for p in pairs for x in p])
        if rng.random() < .1:
            continue    # -l only for this one: no description lines
        kv = [("vendor", f"'{vname}'"), ("device", f"'{dname}'"), ("class", klass)]
        if sub:
            kv.append(("subclass", sub))
        for k, v in kv:
            d.line(f"    {k:<10} = {v}", "kv", [k, v])
    return d
