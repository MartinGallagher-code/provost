"""cmd `ipconfig` and `ipconfig /all`: a `Windows IP Configuration` heading,
`adapter <name>:` sections, and dot-leader `Key . . . . : value` lines with
extra DNS servers / gateways continued on indented lines."""
from lib import Doc, fake

TOOL = "ipconfig"

ADAPTERS = [("Ethernet adapter", "Ethernet", "Intel(R) Ethernet Connection (7) I219-V"),
            ("Ethernet adapter", "Ethernet 2", "Realtek PCIe GbE Family Controller"),
            ("Wireless LAN adapter", "Wi-Fi", "Intel(R) Wi-Fi 6E AX211 160MHz"),
            ("Wireless LAN adapter", "Local Area Connection* 1", "Microsoft Wi-Fi Direct Virtual Adapter"),
            ("Wireless LAN adapter", "Local Area Connection* 10", "Microsoft Wi-Fi Direct Virtual Adapter #2"),
            ("Ethernet adapter", "vEthernet (Default Switch)", "Hyper-V Virtual Ethernet Adapter"),
            ("Ethernet adapter", "vEthernet (WSL (Hyper-V firewall))", "Hyper-V Virtual Ethernet Adapter #2"),
            ("Ethernet adapter", "Bluetooth Network Connection", "Bluetooth Device (Personal Area Network)"),
            ("Unknown adapter", "OpenVPN Data Channel Offload", "OpenVPN Data Channel Offload"),
            ("Tunnel adapter", "Teredo Tunneling Pseudo-Interface", "Microsoft Teredo Tunneling Adapter")]

DAYS = "Monday Tuesday Wednesday Thursday Friday Saturday Sunday".split()
MONTHS = "January February March April May June July August September October November December".split()


def _lease(rng):
    h = rng.randint(1, 12)
    return (f"{rng.choice(DAYS)}, {rng.choice(MONTHS)} {rng.randint(1, 28)}, 2026 "
            f"{h}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {rng.choice(['AM', 'PM'])}")


def _kv(d, key, vals):
    text = "   " + key
    if key in ("Connection-specific DNS Suffix", "Primary Dns Suffix"):
        text += "  ."
    for i in range(len(text), 37):
        text += "." if i % 2 else " "
    text += (" " if len(text) > 37 else "") + ": "
    if not vals:
        d.line(text, "kv", [key])
        return
    d.line(text + vals[0], "kv", [key, vals[0]])
    for v in vals[1:]:
        d.line(" " * 39 + v, "cont", [v])


def _mac(rng):
    return "-".join(f"{rng.randint(0, 255):02X}" for _ in range(6))


def generate(rng):
    d = Doc()
    full = rng.random() < .6
    host = rng.choice(["DESKTOP-", "LAPTOP-", "WS"]) + fake.token(rng, 7).upper()
    suffix = rng.choice(["lan", "home", "corp.example.com", "localdomain", ""])
    d.blank()
    d.section("Windows IP Configuration")
    d.blank()
    if full:
        _kv(d, "Host Name", [host])
        _kv(d, "Primary Dns Suffix", [suffix] if "corp" in suffix else [])
        _kv(d, "Node Type", [rng.choice(["Hybrid", "Hybrid", "Broadcast", "Peer-Peer"])])
        _kv(d, "IP Routing Enabled", ["No"])
        _kv(d, "WINS Proxy Enabled", ["No"])
        if suffix:
            _kv(d, "DNS Suffix Search List", [suffix] + (["example.com"] if rng.random() < .3 else []))
        d.blank()
    for kind, name, desc in rng.sample(ADAPTERS, rng.randint(1, 5)):
        d.section(f"{kind} {name}:")
        d.blank()
        idx = rng.randint(2, 40)
        up = rng.random() < .65 and kind != "Tunnel adapter"
        if not up:
            _kv(d, "Media State", ["Media disconnected"])
            _kv(d, "Connection-specific DNS Suffix", [suffix] if suffix and rng.random() < .3 else [])
            if full:
                _kv(d, "Description", [desc])
                _kv(d, "Physical Address", [_mac(rng)] if kind != "Tunnel adapter" else [])
                _kv(d, "DHCP Enabled", [rng.choice(["Yes", "No"])])
                _kv(d, "Autoconfiguration Enabled", ["Yes"])
            d.blank()
            continue
        dhcp = rng.random() < .7 and not name.startswith("vEthernet")
        ip = fake.ip(rng)
        gw = ip.rsplit(".", 1)[0] + "." + rng.choice(["1", "254"])
        ll = "fe80::" + ":".join(f"{rng.randint(0, 65535):x}" for _ in range(4)) + f"%{idx}"
        _kv(d, "Connection-specific DNS Suffix", [suffix] if suffix and dhcp else [])
        if full:
            _kv(d, "Description", [desc])
            _kv(d, "Physical Address", [_mac(rng)])
            _kv(d, "DHCP Enabled", ["Yes" if dhcp else "No"])
            _kv(d, "Autoconfiguration Enabled", ["Yes"])
        if rng.random() < .25:
            v6 = fake.ip(rng, v6=True)
            _kv(d, "IPv6 Address", [v6 + ("(Preferred)" if full else "")])
            if rng.random() < .5:
                _kv(d, "Temporary IPv6 Address", [fake.ip(rng, v6=True) + ("(Preferred)" if full else "")])
        _kv(d, "Link-local IPv6 Address", [ll + ("(Preferred)" if full else "")])
        _kv(d, "IPv4 Address", [ip + ("(Preferred)" if full else "")])
        _kv(d, "Subnet Mask", [rng.choice(["255.255.255.0", "255.255.240.0", "255.255.0.0", "255.255.252.0"])])
        if full and dhcp:
            _kv(d, "Lease Obtained", [_lease(rng)])
            _kv(d, "Lease Expires", [_lease(rng)])
        gws = ([ll.split("%")[0][:10] + "1%" + str(idx)] if rng.random() < .2 else []) + \
            ([gw] if not name.startswith("vEthernet") or rng.random() < .3 else [])
        _kv(d, "Default Gateway", gws)
        if full:
            if dhcp:
                _kv(d, "DHCP Server", [gw])
            _kv(d, "DHCPv6 IAID", [str(rng.randint(10 ** 7, 10 ** 9))])
            _kv(d, "DHCPv6 Client DUID", ["00-01-00-01-" + "-".join(f"{rng.randint(0, 255):02X}" for _ in range(10))])
            dns = rng.choice([[gw], [gw, "8.8.8.8"], ["1.1.1.1", "1.0.0.1"], ["fec0:0:0:ffff::1%1", "fec0:0:0:ffff::2%1", "fec0:0:0:ffff::3%1"]])
            _kv(d, "DNS Servers", dns)
            if rng.random() < .2:
                _kv(d, "Primary WINS Server", [fake.ip(rng)])
            _kv(d, "NetBIOS over Tcpip", [rng.choice(["Enabled", "Enabled", "Disabled"])])
            if rng.random() < .2:
                _kv(d, "Connection-specific DNS Suffix Search List", [suffix or "lan"])
        d.blank()
    return d
