"""`efibootmgr` / `efibootmgr -v`: boot-manager settings as key/value lines,
then one line per Boot#### entry (number+active flag, label, device path)."""
from lib import Doc, fake

TOOL = "efibootmgr"


def guid(rng):
    return fake.uuid(rng)


def hd(rng):
    part = rng.choice([1, 1, 2])
    start = rng.choice(["0x800", "0x1000", "0x28"])
    size = rng.choice(["0x82000", "0x100000", "0x96000", "0x32000"])
    return f"HD({part},GPT,{guid(rng)},{start},{size})"


def entries(rng):
    out = []
    os_entries = [("ubuntu", "\\EFI\\ubuntu\\shimx64.efi"), ("debian", "\\EFI\\debian\\shimx64.efi"),
                  ("Fedora", "\\EFI\\fedora\\shimx64.efi"), ("Linux Boot Manager", "\\EFI\\systemd\\systemd-bootx64.efi"),
                  ("Arch Linux", "\\EFI\\Linux\\arch-linux.efi"), ("rocky", "\\EFI\\rocky\\shimx64.efi"),
                  ("opensuse-secureboot", "\\EFI\\opensuse\\shim.efi"), ("refind", "\\EFI\\refind\\refind_x64.efi")]
    for label, f in rng.sample(os_entries, rng.randint(1, 2)):
        out.append((label, f"{hd(rng)}/File({f})"))
    if rng.random() < 0.5:
        out.append(("Windows Boot Manager",
                    f"{hd(rng)}/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)WINDOWS.........x...B.C.D.O.B.J.E.C.T.=.{{{guid(rng)}}}...."
                    + "".join(rng.choice(".a.b.c.d") for _ in range(rng.randint(5, 30)))))
    nic = f"{rng.randint(0, 2 ** 48 - 1):012x}"
    pci = f"PciRoot(0x0)/Pci(0x{rng.randint(1, 0x1f):x},0x{rng.randint(0, 7):x})/Pci(0x0,0x{rng.randint(0, 1):x})"
    if rng.random() < 0.6:
        name = rng.choice(["Intel(R) Ethernet Connection I219-LM", "Realtek PCIe GBE Family Controller", "Broadcom NetXtreme"])
        out.append((f"UEFI: PXE IPv4 {name}", f"{pci}/MAC({nic},0)/IPv4(0.0.0.0,0,DHCP)..BO"))
        if rng.random() < 0.6:
            out.append((f"UEFI: PXE IPv6 {name}", f"{pci}/MAC({nic},0)/IPv6([::]:<->[::]:,0,0)..BO"))
    if rng.random() < 0.5:
        out.append(("UEFI OS", f"{hd(rng)}/File(\\EFI\\BOOT\\BOOTX64.EFI)..BO"))
    if rng.random() < 0.4:
        out.append((rng.choice(["EFI USB Device", "UEFI: SanDisk Cruzer Blade 1.00", "USB HDD"]),
                    rng.choice(["RC", f"{pci}/USB(1,0)/USB(0,0)..BO"])))
    if rng.random() < 0.3:
        out.append(("EFI Internal Shell", "FvVol(7cb8bdc9-f8eb-4f34-aaea-3ee4af6516a1)/FvFile(7c04a583-9e3e-4f1c-ad65-e05268d0b4d1)"))
    if rng.random() < 0.3:
        out.append(("UEFI Firmware Settings", "FvVol(70040abc-6bd3-4b45-8b16-3c3d6e64e7fa)/FvFile(462caa21-7614-4503-836e-8ab6f4662331)"))
    return out


def generate(rng):
    d = Doc()
    verbose = rng.random() < 0.6
    ents = entries(rng)
    nums = sorted(rng.sample(range(0, 12), len(ents)))
    ids = [f"{n:04X}" for n in nums]
    if rng.random() < 0.2 and len(ids) > 1:
        ids[-1] = "2001"
    order = ids[:]
    rng.shuffle(order)
    if rng.random() < 0.2:
        d.kv("BootNext", rng.choice(ids))
    d.kv("BootCurrent", rng.choice(order[:2]))
    if rng.random() < 0.85:
        d.kv("Timeout", f"{rng.choice([0, 1, 2, 5, 10, 30])} seconds")
    shown = order if rng.random() < 0.8 else order[:-1]
    d.kv("BootOrder", ",".join(shown))
    if verbose and rng.random() < 0.3:
        d.kv("MirroredPercentageAbove4G", rng.choice(["0.00", "5.00"]))
        d.kv("MirrorMemoryBelow4GB", rng.choice(["false", "true"]))
    sep = rng.choice(["\t", "\t", " "])
    for i, (label, path) in zip(ids, ents):
        num = f"Boot{i}" + ("*" if rng.random() < 0.85 else "")
        if verbose:
            d.line(f"{num.ljust(9)} {label}{sep}{path}", "row", [num, label, path])
        else:
            d.line(f"{num.ljust(9)} {label}", "row", [num, label])
    return d
