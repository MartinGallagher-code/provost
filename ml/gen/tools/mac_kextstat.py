"""macOS `kextstat`: an aligned table of loaded kernel extensions; the last
header names `Name (Version) UUID <Linked Against>` split into their cells.
Newer releases prefix two lines about running kmutil."""
from lib import Doc, fake

TOOL = "kextstat"

KEXTS = ["com.apple.kpi.bsd", "com.apple.kpi.dsep", "com.apple.kpi.iokit", "com.apple.kpi.kasan",
         "com.apple.kpi.libkern", "com.apple.kpi.mach", "com.apple.kpi.private", "com.apple.kpi.unsupported",
         "com.apple.kec.corecrypto", "com.apple.kec.Libm", "com.apple.kec.pthread",
         "com.apple.iokit.IOACPIFamily", "com.apple.driver.AppleACPIPlatform", "com.apple.iokit.IOPCIFamily",
         "com.apple.driver.AppleSMC", "com.apple.iokit.IOStorageFamily", "com.apple.filesystems.apfs",
         "com.apple.driver.AppleUSBHostMergeProperties", "com.apple.iokit.IOUSBHostFamily",
         "com.apple.iokit.IONetworkingFamily", "com.apple.driver.AppleBCMWLANCore",
         "com.apple.filesystems.smbfs", "com.apple.driver.AppleHDA", "com.apple.nke.l2tp",
         "com.apple.security.sandbox", "com.apple.AppleFSCompression.AppleFSCompressionTypeZlib",
         "com.vmware.kext.vmhgfs", "com.parallels.kext.hypervisor", "org.virtualbox.kext.VBoxDrv",
         "com.Logitech.Control Center.HID Driver", "com.paragon-software.filesystems.ntfs",
         "com.objective-see.lulu"]


def generate(rng):
    d = Doc()
    if rng.random() < .6:
        d.skip("Executing: /usr/bin/kmutil showloaded")
        d.skip("No variant specified, falling back to release")
    d.line("Index Refs Address            Size       Wired      Name (Version) UUID <Linked Against>", "header",
           ["Index", "Refs", "Address", "Size", "Wired", "Name", "(Version)", "UUID", "<Linked Against>"])
    darwin = f"{rng.randint(19, 24)}.{rng.randint(0, 6)}.0"
    names = list(KEXTS[:8]) + rng.sample(KEXTS[8:], rng.randint(3, 16))
    idx = 0
    for i, name in enumerate(names):
        idx += 1 if i < 8 or rng.random() < .7 else rng.randint(2, 6)
        if i < 8:
            addr, size, wired, ver = "0", "0", "0", darwin
            linked = ""
        else:
            addr = f"0xffffff{rng.randint(0x7f80000000, 0x7fffffffff):010x}"
            size = f"0x{rng.randint(1, 4000) * 0x1000:x}"
            wired = size
            ver = rng.choice([darwin, f"{rng.randint(1, 900)}.{rng.randint(0, 99)}",
                              f"{rng.randint(1, 3)}.{rng.randint(0, 9)}.{rng.randint(0, 9)}", "1"])
            linked = " ".join(str(x) for x in sorted(rng.sample(range(1, max(idx, 3)), rng.randint(1, min(8, max(idx - 1, 1)))), reverse=True))
        refs = str(rng.choice([0, 0, 1, 2, 3, rng.randint(4, 180)]))
        uuid = fake.uuid(rng).upper()
        text = f"{idx:>5} {refs:>4} {addr:<18} {size:<10} {wired:<10} {name} ({ver}) {uuid} <{linked}>"
        d.line(text, "row", [str(idx), refs, addr, size, wired, name, f"({ver})", uuid, f"<{linked}>"])
    return d
