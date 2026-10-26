"""cmd `netsh wlan show interfaces` and `netsh wlan show networks mode=bssid`:
prose count lines, then indented `Key   : value` blocks; the networks form
nests `BSSID n` blocks under `SSID n : name` lines."""
from lib import Doc, fake

TOOL = "netsh-wlan"

SSIDS = ["HomeNet", "HomeNet-5G", "CorpWiFi", "CorpGuest", "xfinitywifi", "NETGEAR42", "TP-Link_5F3A",
         "Linksys00213", "DIRECT-7B-HP M283 LaserJet", "eduroam", "Pixel_8821", "BTWi-fi", "SKY4F2A1",
         "The LAN Before Time", "FBI Surveillance Van 3", "Cafe Free WiFi", ""]


def _mac(rng):
    return ":".join(f"{rng.randint(0, 255):02x}" for _ in range(6))


def _interfaces(d, rng):
    n = rng.choice([1, 1, 1, 2])
    d.blank()
    d.skip(f"There {'is' if n == 1 else 'are'} {n} interface{'s' if n > 1 else ''} on the system:")
    for i in range(n):
        d.blank()
        connected = rng.random() < .75
        ssid = rng.choice([s for s in SSIDS if s])
        band = rng.choice(["2.4 GHz", "5 GHz", "5 GHz", "6 GHz"])
        ch = {"2.4 GHz": rng.choice([1, 6, 11]), "5 GHz": rng.choice([36, 44, 100, 149, 157]),
              "6 GHz": rng.choice([5, 37, 69])}[band]
        rate = rng.choice(["72.2", "144.4", "300", "433.3", "866.7", "1201", "2402"])
        pairs = [("Name", rng.choice(["Wi-Fi", "Wi-Fi 2", "WLAN"])),
                 ("Description", rng.choice(["Intel(R) Wi-Fi 6E AX211 160MHz", "Realtek RTL8852BE WiFi 6 802.11ax PCIe Adapter",
                                             "Qualcomm Atheros QCA9377 Wireless Network Adapter", "MediaTek Wi-Fi 6 MT7921 Wireless LAN Card"])),
                 ("GUID", fake.uuid(rng)), ("Physical address", _mac(rng))]
        if rng.random() < .6:
            pairs.append(("Interface type", "Primary"))
        pairs.append(("State", "connected" if connected else rng.choice(["disconnected", "disconnecting", "authenticating"])))
        if connected:
            pairs += [("SSID", ssid), ("AP BSSID", _mac(rng))]
            if rng.random() < .6:
                pairs.append(("Band", band))
            pairs += [("Channel", str(ch)), ("Network type", "Infrastructure"),
                      ("Radio type", rng.choice(["802.11n", "802.11ac", "802.11ax", "802.11be"])),
                      ("Authentication", rng.choice(["WPA2-Personal", "WPA3-Personal", "WPA2-Enterprise", "Open"])),
                      ("Cipher", rng.choice(["CCMP", "GCMP-256", "None"])),
                      ("Connection mode", rng.choice(["Auto Connect", "Profile"])),
                      ("Receive rate (Mbps)", rate), ("Transmit rate (Mbps)", rng.choice([rate, "866.7", "573.5"])),
                      ("Signal", f"{rng.randint(20, 100)}%"), ("Profile", ssid)]
        else:
            pairs.append(("Radio status", "Hardware On\n" + " " * 29 + "Software On"))
        w = 23
        for k, v in pairs:
            if "\n" in v:
                a, b = v.split("\n")
                d.line("    " + k.ljust(w) + ": " + a, "kv", [k, a])
                d.line(b, "cont", [b.strip()])
            else:
                d.line("    " + k.ljust(w) + ": " + v, "kv", [k, v])
        if connected and rng.random() < .5:
            d.blank()
            for k in ["QoS MSCS Configured", "QoS Map Configured", "QoS Map Allowed by Policy"]:
                v = rng.choice(["0", "0", "1"])
                d.line("    " + k.ljust(28) + ": " + v, "kv", [k, v])
    d.blank()
    if rng.random() < .5:
        d.kv("Hosted network status", "Not available", sep="  : ", indent="    ")
        d.blank()


def _networks(d, rng):
    nets = rng.sample(SSIDS, rng.randint(1, 6))
    d.blank()
    d.kv("Interface name", rng.choice(["Wi-Fi", "Wi-Fi 2"]), sep=" : ")
    d.skip(f"There are {len(nets)} networks currently visible.")
    d.blank()
    for i, s in enumerate(nets, 1):
        text = f"SSID {i} : {s}"
        d.line(text if s else text + "", "kv", [f"SSID {i}", s] if s else [f"SSID {i}"])
        auth = rng.choice(["WPA2-Personal", "WPA3-Personal", "WPA2-Enterprise", "Open"])
        pairs = [("Network type", "Infrastructure"), ("Authentication", auth),
                 ("Encryption", "None" if auth == "Open" else "CCMP")]
        for k, v in pairs:
            d.line("    " + k.ljust(24) + ": " + v, "kv", [k, v])
        if rng.random() < .7:
            for b in range(1, rng.randint(2, 3)):
                d.line("    " + f"BSSID {b}".ljust(24) + ": " + (m := _mac(rng)), "kv", [f"BSSID {b}", m])
                bp = [("Signal", f"{rng.randint(10, 99)}%  "),
                      ("Radio type", rng.choice(["802.11n", "802.11ac", "802.11ax"])),
                      ("Band", rng.choice(["2.4 GHz", "5 GHz"])), ("Channel", str(rng.choice([1, 6, 11, 36, 149])))]
                if rng.random() < .5:
                    bp.append(("Bss Load:", None))
                for k, v in bp:
                    if v is None:
                        d.line("         Bss Load:", "section", ["Bss Load"])
                        cu, cn = str(rng.randint(1, 30)), str(rng.randint(0, 250))
                        d.line("             Connected Stations:        " + cu, "kv", ["Connected Stations", cu])
                        d.line("             Channel Utilization:        " + cn + f" ({int(cn) * 100 // 255} %)", "kv",
                               ["Channel Utilization", cn + f" ({int(cn) * 100 // 255} %)"])
                        continue
                    d.line("         " + k.ljust(19) + ": " + v, "kv", [k, v.strip()])
                rates = rng.choice(["1 2 5.5 11", "6 9 12 18 24 36 48 54", "6 12 24"])
                d.line("         " + "Basic rates (Mbps)".ljust(19) + ": " + rates, "kv", ["Basic rates (Mbps)", rates])
                if rng.random() < .6:
                    o = rng.choice(["6 9 12 18 24 36 48 54", "9 18 36 48 54"])
                    d.line("         " + "Other rates (Mbps)".ljust(19) + ": " + o, "kv", ["Other rates (Mbps)", o])
        d.blank()


def generate(rng):
    d = Doc()
    if rng.random() < .55:
        _interfaces(d, rng)
    else:
        _networks(d, rng)
    return d
