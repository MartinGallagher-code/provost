"""macOS `sudo wdutil info`: em-dash ruled section titles, `Key : value`
lines with the key padded to 21, and `: value` continuation lines for keys
with several values."""
from lib import Doc, fake

TOOL = "wdutil-info"

RULE = "—" * 68
KW = 21


def kv(d, k, v):
    if v in ("", None):
        d.line(f"    {k:<{KW}}:", "kv", [k, None])
    else:
        d.line(f"    {k:<{KW}}: {v}", "kv", [k, v])


def more(d, v):
    d.line(f"    {'':<{KW}}: {v}", "cont", [v])


def section(d, title):
    d.skip(RULE)
    d.section(title)
    d.skip(RULE)


def generate(rng):
    d = Doc()
    svc = fake.uuid(rng).upper()
    ip = fake.ip(rng)
    gw = ".".join(ip.split(".")[:3] + ["1"])
    on = rng.random() < .85
    for sec in ["NETWORK", "WIFI", "BLUETOOTH", "AWDL", "POWER"]:
        if sec in ("AWDL", "POWER", "BLUETOOTH") and rng.random() < .3:
            continue
        section(d, sec)
        if sec == "NETWORK":
            kv(d, "Primary IPv4", f"en0 (Wi-Fi / {svc})" if on else "None")
            if on:
                more(d, ip)
            kv(d, "Primary IPv6", rng.choice(["None", f"en0 (Wi-Fi / {svc})"]))
            dns = [gw] + [fake.ip(rng) for _ in range(rng.randint(0, 2))]
            kv(d, "DNS Addresses", dns[0])
            for x in dns[1:]:
                more(d, x)
            kv(d, "Apple", rng.choice(["Reachable", "Reachable", "Not Reachable"]))
        elif sec == "WIFI":
            m = fake.mac(rng)
            kv(d, "MAC Address", f"{m} (hw={m})")
            kv(d, "Interface Name", "en0")
            kv(d, "Power", f"On [On]" if on else "Off [Off]")
            kv(d, "Op Mode", "STA" if on else "")
            if on:
                ssid = rng.choice(["HomeNet", "Office-5G", "eduroam", "Pretty Fly for a WiFi", "NETGEAR42", "<redacted>"])
                band = rng.choice(["2g", "5g", "5g", "6g"])
                ch = {"2g": rng.choice([1, 6, 11]), "5g": rng.choice([36, 44, 149, 157]), "6g": rng.choice([37, 69])}[band]
                width = 20 if band == "2g" else rng.choice([40, 80, 160])
                pairs = [("SSID", ssid), ("BSSID", fake.mac(rng)), ("RSSI", f"{rng.randint(-85, -35)} dBm"),
                         ("CCA", f"{rng.randint(0, 60)} %"), ("Noise", f"{rng.randint(-98, -88)} dBm"),
                         ("Tx Rate", f"{rng.choice([86.0, 144.0, 286.0, 573.0, 866.0, 1200.0, 1441.0])} Mbps"),
                         ("Security", rng.choice(["WPA2 Personal", "WPA3 Personal", "WPA2 Enterprise", "None"])),
                         ("PHY Mode", rng.choice(["11ax", "11ac", "11n"])), ("MCS Index", str(rng.randint(0, 11))),
                         ("NSS", str(rng.choice([1, 2]))), ("Channel", f"{band}{ch}/{width}"),
                         ("Country Code", rng.choice(["US", "GB", "DE", "JP", "IE"])),
                         ("Scan Cache Count", str(rng.randint(0, 60))), ("NetworkServiceID", svc),
                         ("IPv4 Config Method", rng.choice(["DHCP", "Manual"])), ("IPv4 Address", ip),
                         ("IPv4 Router", gw), ("IPv6 Config Method", "Automatic"), ("IPv6 Address", "None"),
                         ("IPv6 Router", "None"), ("DNS", gw), ("BTC Mode", rng.choice(["Off", "On"])),
                         ("Desense", ""), ("Chain Ack", "[]"), ("BTC Profile 2.4GHz", "Disabled"),
                         ("BTC Profile 5GHz", "Disabled"), ("Sniffing", "No"), ("Supports 6e", rng.choice(["Yes", "No"])),
                         ("Supported Channels", "2g1/20,2g2/20,2g3/20,2g4/20,2g5/20,2g6/20,2g7/20,2g8/20,2g9/20,2g10/20,2g11/20,5g36/20,5g40/20,5g44/20,5g48/20,5g149/80")]
                for k, v in pairs:
                    if k in ("Scan Cache Count", "Chain Ack", "Sniffing", "Supports 6e", "Supported Channels") and rng.random() < .3:
                        continue
                    kv(d, k, v)
        elif sec == "BLUETOOTH":
            bt = rng.random() < .8
            kv(d, "Power", "On" if bt else "Off")
            kv(d, "Address", fake.mac(rng).replace(":", "-"))
            kv(d, "Discoverable", "No")
            kv(d, "Connectable", "Yes" if bt else "No")
            kv(d, "Scanning", "No")
            devs = rng.sample(["AirPods Pro", "Magic Keyboard", "Magic Mouse", "MX Master 3", "WH-1000XM4", "Bob’s AirPods"], rng.randint(0, 3)) if bt else []
            kv(d, "Devices", str(len(devs)))
            for x in devs:
                more(d, f"{x} ({rng.choice(['Connected', 'Not Connected'])})")
        elif sec == "AWDL":
            kv(d, "Power", rng.choice(["Off", "On"]))
            kv(d, "Op Mode", rng.choice(["AWDL", ""]))
            kv(d, "Channel", rng.choice(["", "6", "149"]))
        else:
            ac = rng.random() < .5
            kv(d, "Power Source", "AC Power" if ac else "Battery Power")
            kv(d, "Battery Charge", f"{rng.randint(5, 100)}%")
            kv(d, "Low Power Mode", rng.choice(["Disabled", "Enabled"]))
    d.skip(RULE)
    return d
