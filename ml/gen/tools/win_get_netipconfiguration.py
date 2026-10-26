"""PowerShell `Get-NetIPConfiguration` (Format-List view, optionally
-Detailed): one `Key : value` block per interface, empty values, and extra
values (DNS servers, addresses) continued on indented lines."""
from lib import Doc, fake

TOOL = "Get-NetIPConfiguration"

ADAPTERS = [("Ethernet", "Intel(R) Ethernet Connection (7) I219-V"),
            ("Wi-Fi", "Intel(R) Wi-Fi 6E AX211 160MHz"),
            ("Ethernet 2", "Realtek USB GbE Family Controller"),
            ("vEthernet (Default Switch)", "Hyper-V Virtual Ethernet Adapter"),
            ("vEthernet (WSL)", "Hyper-V Virtual Ethernet Adapter #2"),
            ("Bluetooth Network Connection", "Bluetooth Device (Personal Area Network)"),
            ("Ethernet 3", "TAP-Windows Adapter V9"),
            ("Tailscale", "Tailscale Tunnel"),
            ("Wi-Fi 2", "Killer(R) Wi-Fi 6 AX1650s 160MHz Wireless Network Adapter (201D2W)")]


def _v6ll(rng, idx):
    return "fe80::" + ":".join(f"{rng.randint(0, 65535):x}" for _ in range(4)) + f"%{idx}"


def _mac(rng):
    return "-".join(f"{rng.randint(0, 255):02X}" for _ in range(6))


def generate(rng):
    d = Doc()
    detailed = rng.random() < .35
    computer = "DESKTOP-" + fake.token(rng, 7).upper()
    blocks = []
    for alias, desc in rng.sample(ADAPTERS, rng.randint(1, 4)):
        idx = str(rng.randint(2, 60))
        up = rng.random() < .8
        b = []
        if detailed:
            b.append(("ComputerName", [computer]))
        b += [("InterfaceAlias", [alias]), ("InterfaceIndex", [idx]), ("InterfaceDescription", [desc])]
        if detailed:
            b += [("NetAdapter.LinkLayerAddress", [_mac(rng)]),
                  ("NetAdapter.Status", ["Up" if up else rng.choice(["Disconnected", "Disabled"])])]
        if up:
            prof = rng.choice(["Network", "Network 2", "Network 3", "HomeNet-5G", "corp.example.com",
                               "Unidentified network", "Identifying..."])
            b.append(("NetProfile.Name", [prof]))
            if detailed:
                b += [("NetProfile.NetworkCategory", [rng.choice(["Private", "Public", "DomainAuthenticated"])]),
                      ("NetProfile.IPv6Connectivity", [rng.choice(["NoTraffic", "Internet", "LocalNetwork"])]),
                      ("NetProfile.IPv4Connectivity", [rng.choice(["Internet", "LocalNetwork", "NoTraffic"])])]
        if detailed:
            b.append(("IPv6LinkLocalAddress", [_v6ll(rng, idx)]))
        if up and rng.random() < .3:
            b.append(("IPv6Address", [fake.ip(rng, v6=True) for _ in range(rng.randint(1, 2))]))
        v4 = [fake.ip(rng) for _ in range(1 if rng.random() < .85 else 2)] if up or rng.random() < .3 else \
            ["169.254." + f"{rng.randint(0, 255)}.{rng.randint(1, 254)}"]
        b.append(("IPv4Address", v4))
        if detailed or rng.random() < .5:
            b.append(("IPv6DefaultGateway", [] if rng.random() < .7 else ["fe80::1"]))
        gw = v4[0].rsplit(".", 1)[0] + ".1"
        b.append(("IPv4DefaultGateway", [gw] if up and rng.random() < .85 else []))
        if detailed:
            b += [("NetIPv6Interface.NlMTU", [rng.choice(["1500", "1280", "1400"])]),
                  ("NetIPv4Interface.NlMTU", [rng.choice(["1500", "1472", "1400"])]),
                  ("NetIPv4Interface.DHCP", [rng.choice(["Enabled", "Disabled"])])]
        dns = []
        if up:
            dns = [gw] if rng.random() < .5 else []
            dns += rng.sample(["8.8.8.8", "1.1.1.1", "9.9.9.9", "8.8.4.4", "fec0:0:0:ffff::1%1",
                               "fec0:0:0:ffff::2%1", "2001:4860:4860::8888"], rng.randint(0, 3))
        b.append(("DNSServer", dns))
        blocks.append(b)
    w = max(len(k) for b in blocks for k, _ in b)
    d.blank()
    for b in blocks:
        for k, vals in b:
            if not vals:
                d.line(k.ljust(w) + " : ", "kv", [k])
                continue
            d.line(k.ljust(w) + " : " + vals[0], "kv", [k, vals[0]])
            for v in vals[1:]:
                d.line(" " * (w + 3) + v, "cont", [v])
        d.blank()
    if rng.random() < .6:
        d.blank()
    return d
