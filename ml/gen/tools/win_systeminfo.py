"""cmd `systeminfo`: aligned `Key:   value` lines (some keys contain a colon
themselves), with `[01]: value` lists and the indented per-NIC details nested
under Processor(s), Hotfix(s) and Network Card(s)."""
from lib import Doc, fake

TOOL = "systeminfo"

W = 27  # values start here


def _date(rng, y0=2019, y1=2026):
    h = rng.randint(1, 12)
    return (f"{rng.randint(1, 12)}/{rng.randint(1, 28)}/{rng.randint(y0, y1)}, "
            f"{h}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {rng.choice(['AM', 'PM'])}")


def generate(rng):
    d = Doc()
    host = rng.choice(["DESKTOP-", "LAPTOP-", "SRV-", "WS-"]) + fake.token(rng, 7).upper()
    server = host.startswith("SRV")
    osname = rng.choice(["Microsoft Windows Server 2022 Standard", "Microsoft Windows Server 2019 Datacenter",
                         "Microsoft Windows Server 2025 Standard"] if server else
                        ["Microsoft Windows 11 Pro", "Microsoft Windows 11 Enterprise", "Microsoft Windows 10 Pro",
                         "Microsoft Windows 11 Home", "Microsoft Windows 10 Enterprise LTSC"])
    build = rng.choice(["17763", "19045", "20348", "22631", "26100"])
    domain = rng.choice(["WORKGROUP", "corp.example.com", "AD.LOCAL"])
    mf, model = rng.choice([("Dell Inc.", "XPS 15 9520"), ("LENOVO", "20XW0026US"), ("HP", "HP EliteBook 840 G8 Notebook PC"),
                            ("Microsoft Corporation", "Virtual Machine"), ("VMware, Inc.", "VMware7,1"),
                            ("System manufacturer", "System Product Name"), ("ASUS", "ROG Strix G15 G513QM_G513QM")])
    tot = rng.randint(4, 128) * 1024 - rng.randint(0, 900)
    avail = rng.randint(500, tot)
    vmax = tot + rng.randint(1000, 9000)
    vav = rng.randint(200, vmax)
    pairs = [
        ("Host Name", host), ("OS Name", osname),
        ("OS Version", f"10.0.{build} N/A Build {build}"),
        ("OS Manufacturer", "Microsoft Corporation"),
        ("OS Configuration", rng.choice(["Standalone Workstation", "Member Workstation", "Member Server", "Primary Domain Controller"])),
        ("OS Build Type", "Multiprocessor Free"),
        ("Registered Owner", rng.choice([fake.user(rng), "Windows User", f"{fake.user(rng)}@example.com"])),
        ("Registered Organization", rng.choice(["N/A", "", "Example Corp"])),
        ("Product ID", f"00{rng.randint(300, 399)}-{rng.randint(10000, 99999)}-{rng.randint(10000, 99999)}-AA{rng.randint(100, 999)}"),
        ("Original Install Date", _date(rng)), ("System Boot Time", _date(rng, 2026, 2026)),
        ("System Manufacturer", mf), ("System Model", model),
        ("System Type", rng.choice(["x64-based PC", "x64-based PC", "ARM64-based PC"])),
        ("Processor(s)", None),
        ("BIOS Version", f"{mf} {rng.randint(1, 3)}.{rng.randint(0, 30)}.{rng.randint(0, 9)}, {rng.randint(1, 12)}/{rng.randint(1, 28)}/{rng.randint(2019, 2026)}"),
        ("Windows Directory", "C:\\WINDOWS" if not server else "C:\\Windows"),
        ("System Directory", "C:\\WINDOWS\\system32" if not server else "C:\\Windows\\system32"),
        ("Boot Device", f"\\Device\\HarddiskVolume{rng.randint(1, 4)}"),
        ("System Locale", rng.choice(["en-us;English (United States)", "en-gb;English (United Kingdom)", "de;German (Germany)"])),
        ("Input Locale", rng.choice(["en-us;English (United States)", "en-gb;English (United Kingdom)"])),
        ("Time Zone", rng.choice(["(UTC-08:00) Pacific Time (US & Canada)", "(UTC+00:00) Dublin, Edinburgh, Lisbon, London",
                                  "(UTC-05:00) Eastern Time (US & Canada)", "(UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna"])),
        ("Total Physical Memory", f"{tot:,} MB"), ("Available Physical Memory", f"{avail:,} MB"),
        ("Virtual Memory: Max Size", f"{vmax:,} MB"), ("Virtual Memory: Available", f"{vav:,} MB"),
        ("Virtual Memory: In Use", f"{vmax - vav:,} MB"),
        ("Page File Location(s)", "C:\\pagefile.sys"), ("Domain", domain),
        ("Logon Server", "\\\\" + (host if domain == "WORKGROUP" else rng.choice(["DC01", "DC02", "ADDC-EAST"]))),
        ("Hotfix(s)", None), ("Network Card(s)", None), ("Hyper-V Requirements", None),
    ]
    d.blank()
    for k, v in pairs:
        if k == "Processor(s)":
            n = rng.choice([1, 1, 1, 2])
            d.kv(k, f"{n} Processor(s) Installed.", key_width=None, sep=":".ljust(W - len(k)))
            for i in range(n):
                cpu = rng.choice([f"Intel64 Family 6 Model {rng.choice([140, 154, 183, 186])} Stepping {rng.randint(1, 9)} GenuineIntel ~{rng.choice([1800, 2300, 2496, 3600])} Mhz",
                                  f"AMD64 Family 25 Model {rng.choice([33, 80, 97])} Stepping {rng.randint(0, 2)} AuthenticAMD ~{rng.choice([3401, 3801, 4501])} Mhz"])
                d.line(" " * W + f"[{i + 1:02d}]: {cpu}", "kv", [f"[{i + 1:02d}]", cpu])
        elif k == "Hotfix(s)":
            n = rng.choice([0, 1, 2, 3, 4, 6, 9])
            d.kv(k, f"{n} Hotfix(s) Installed.", sep=":".ljust(W - len(k)))
            for i in range(n):
                kb = f"KB{rng.randint(4500000, 5049999)}"
                d.line(" " * W + f"[{i + 1:02d}]: {kb}", "kv", [f"[{i + 1:02d}]", kb])
        elif k == "Network Card(s)":
            nics = rng.sample(["Intel(R) Wi-Fi 6E AX211 160MHz", "Intel(R) Ethernet Connection (7) I219-V",
                               "Realtek PCIe GbE Family Controller", "Hyper-V Virtual Ethernet Adapter",
                               "Bluetooth Device (Personal Area Network)", "Microsoft Hyper-V Network Adapter",
                               "vmxnet3 Ethernet Adapter", "TAP-Windows Adapter V9"], rng.randint(1, 3))
            d.kv(k, f"{len(nics)} NIC(s) Installed.", sep=":".ljust(W - len(k)))
            for i, nic in enumerate(nics):
                d.line(" " * W + f"[{i + 1:02d}]: {nic}", "kv", [f"[{i + 1:02d}]", nic])
                ind = " " * (W + 6)
                conn = rng.choice(["Wi-Fi", "Ethernet", "Ethernet 2", "vEthernet (Default Switch)", "Bluetooth Network Connection"])
                d.line(f"{ind}Connection Name: {conn}", "kv", ["Connection Name", conn])
                state = rng.random()
                if state < .25:
                    d.line(f"{ind}Status:          Media disconnected", "kv", ["Status", "Media disconnected"])
                    continue
                dhcp = state < .7
                d.line(f"{ind}DHCP Enabled:    {'Yes' if dhcp else 'No'}", "kv", ["DHCP Enabled", "Yes" if dhcp else "No"])
                ip = fake.ip(rng)
                if dhcp:
                    srv = ip.rsplit(".", 1)[0] + ".1"
                    d.line(f"{ind}DHCP Server:     {srv}", "kv", ["DHCP Server", srv])
                d.line(f"{ind}IP address(es)", "section", ["IP address(es)"])
                addrs = [ip, "fe80::" + ":".join(f"{rng.randint(0, 65535):x}" for _ in range(4))]
                if rng.random() < .3:
                    addrs.append(fake.ip(rng, v6=True))
                for j, a in enumerate(addrs):
                    d.line(f"{ind}[{j + 1:02d}]: {a}", "kv", [f"[{j + 1:02d}]", a])
        elif k == "Hyper-V Requirements":
            if rng.random() < .6:
                v = "A hypervisor has been detected. Features required for Hyper-V will not be displayed."
                d.kv(k, v, sep=":".ljust(W - len(k)))
            else:
                d.line(k + ":".ljust(W - len(k)) + "VM Monitor Mode Extensions: Yes", "kv",
                       [k, "VM Monitor Mode Extensions", "Yes"])
                for kk in ["Virtualization Enabled In Firmware", "Second Level Address Translation", "Data Execution Prevention Available"]:
                    vv = rng.choice(["Yes", "Yes", "No"])
                    d.line(" " * W + f"{kk}: {vv}", "kv", [kk, vv])
        elif v == "":
            d.line(k + ":", "kv", [k])
        else:
            d.kv(k, v, sep=":".ljust(W - len(k)))
    return d
