"""Dell iDRAC `racadm getsysinfo`: titled blocks of `Key = value` settings."""
from lib import Doc, fake

TOOL = "racadm-getsysinfo"

MODELS = ["PowerEdge R640", "PowerEdge R740xd", "PowerEdge R650", "PowerEdge R750", "PowerEdge R440",
          "PowerEdge T640", "PowerEdge R7525", "PowerEdge C6420", "PowerEdge FC640", "PowerEdge M640"]


def tag(rng):
    return "".join(rng.choice("BCDFGHJKLMNPQRSTVWXYZ0123456789") for _ in range(7))


def mac(rng, oui):
    return oui + ":" + ":".join(f"{rng.randint(0, 255):02X}" for _ in range(3))


def dt(rng):
    return fake.date(rng, "us") + " " + fake.date(rng, "time")


def generate(rng):
    d = Doc()
    w = rng.choice([23, 24])
    oui = rng.choice(["50:9A:4C", "D0:94:66", "B0:83:FE", "E4:43:4B", "F4:02:70"])
    st = tag(rng)

    def block(title, pairs):
        d.section(title + ":")
        for k, v in pairs:
            if v == "":
                d.line(k.ljust(w) + "= ", "kv", [k])
            else:
                d.line(k.ljust(w) + "= " + v, "kv", [k, v])
        d.blank()

    if rng.random() < 0.3:
        d.skip("Security Alert: Certificate is invalid - unable to get local issuer certificate")
        d.skip("Continuing execution. Use -S option for racadm to stop execution on certificate-related errors.")
    days = "Mon Tue Wed Thu Fri Sat Sun".split()
    mons = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    block("RAC Information", [
        ("RAC Date/Time", f"{rng.choice(days)} {rng.choice(mons)} {rng.randint(1, 28)} {rng.randint(2021, 2026)} "
                          f"{fake.date(rng, 'time')}"),
        ("Firmware Version", rng.choice(["2.75.75.75", "4.40.00.00", "5.10.50.00", "6.10.30.00", "3.36.36.36"])),
        ("Firmware Build", f"{rng.randint(1, 60):02d}"),
        ("Last Firmware Update", dt(rng)),
        ("Hardware Version", "0.01"),
        ("MAC Address", mac(rng, oui)),
    ])
    block("Common settings", [
        ("Register DNS RAC Name", rng.choice(["0", "1"])),
        ("DNS RAC Name", "idrac-" + st),
        ("Current DNS Domain", rng.choice(["", "example.com", "mgmt.internal", "oob.lan"])),
        ("Domain Name from DHCP", rng.choice(["Disabled", "Enabled"])),
    ])
    gw = fake.ip(rng)
    block("IPv4 settings", [
        ("Enabled", "1"),
        ("Current IP Address", fake.ip(rng)),
        ("Current IP Gateway", gw),
        ("Current IP Netmask", rng.choice(["255.255.255.0", "255.255.254.0", "255.255.0.0"])),
        ("DHCP Enabled", rng.choice(["0", "1"])),
        ("Current DNS Server 1", fake.ip(rng)),
        ("Current DNS Server 2", rng.choice(["0.0.0.0", fake.ip(rng)])),
        ("DNS Servers from DHCP", rng.choice(["Disabled", "Enabled"])),
    ])
    if rng.random() < 0.5:
        block("IPv6 settings", [
            ("Enabled", rng.choice(["0", "1"])),
            ("Current IP Address 1", rng.choice(["::", fake.ip(rng, v6=True)])),
            ("Current IP Gateway", "::"),
            ("Autoconfig", rng.choice(["1", "0"])),
            ("Link Local IP Address", "fe80::" + ":".join(fake.hexid(rng, 4) for _ in range(3))),
            ("Current IP Address 2", "::"),
            ("DNS Servers from DHCPv6", rng.choice(["Disabled", "Enabled"])),
        ])
    block("System Information", [
        ("System Model", rng.choice(MODELS)),
        ("System Revision", rng.choice(["I", "II"])),
        ("System BIOS Version", f"{rng.randint(1, 2)}.{rng.randint(0, 22)}.{rng.randint(0, 9)}"),
        ("Service Tag", st),
        ("Express Svc Code", str(rng.randint(10 ** 10, 10 ** 11 - 1))),
        ("Host Name", rng.choice(["", fake.host(rng)])),
        ("OS Name", rng.choice(["", "Ubuntu", "VMware ESXi", "Red Hat Enterprise Linux", "Microsoft Windows Server 2022"])),
        ("OS Version", rng.choice(["", "22.04.4 LTS", "8.0.2 build-21203435", "9.4 (Plow)", "Version 21H2"])),
        ("Power Status", rng.choice(["ON", "ON", "OFF"])),
        ("Fresh Air Capable", rng.choice(["No", "Yes"])),
    ])
    init = rng.choice([480, 300, 600])
    block("Watchdog Information", [
        ("Recovery Action", rng.choice(["None", "Reboot", "Power Off", "Power Cycle"])),
        ("Present countdown value", f"{rng.randint(1, init)} seconds"),
        ("Initial countdown value", f"{init} seconds"),
    ])
    d.section("Embedded NIC MAC Addresses:")
    kind = rng.choice(["Integrated", "Embedded"])
    for i in range(1, rng.choice([2, 2, 4]) + 1):
        nic = f"NIC.{kind}.1-{i}-1"
        m = mac(rng, oui)
        d.line(nic.ljust(w) + "Ethernet".ljust(w) + "= " + m, "kv", [nic, "Ethernet", m])
    if rng.random() < 0.3:
        d.blank()
        d.section("FC MAC Addresses:")
        for i in range(1, 3):
            fc = f"FC.Slot.{rng.randint(1, 6)}-{i}"
            wwn = ":".join(f"{rng.randint(0, 255):02X}" for _ in range(8))
            d.line(fc.ljust(w) + "WWN".ljust(w) + "= " + wwn, "kv", [fc, "WWN", wwn])
    return d
