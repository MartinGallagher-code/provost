"""macOS `airport -s` Wi-Fi scan: SSIDs right-aligned in a 32-column field,
then BSSID, RSSI, CHANNEL, HT, CC and a free-form SECURITY column (several
space-separated suites are one value). BSSID is blank without location access."""
from lib import Doc, fake

TOOL = "airport-s"


def _ssid(rng):
    w = fake.word(rng)
    return rng.choice([
        f"{w.title()}Net", f"{w}-5G", f"NETGEAR{rng.randint(10, 99)}", f"TP-Link_{fake.hexid(rng, 4).upper()}",
        "xfinitywifi", f"Linksys {rng.randint(10000, 99999)}", f"DIRECT-{fake.hexid(rng, 2).upper()}-HP OfficeJet Pro",
        f"{fake.user(rng).title()}'s iPhone", f"FRITZ!Box 7590 {fake.hexid(rng, 2).upper()}", "eduroam",
        f"{w}_guest", f"Vodafone-{rng.randint(100000, 999999)}", "Starbucks WiFi", f"SKY{rng.randint(10000, 99999)}",
        f"HUAWEI-{fake.hexid(rng, 4).upper()}_5G", "Free Public WiFi", f"BT-{fake.hexid(rng, 6).upper()}",
    ])


SEC = ["WPA2(PSK/AES/AES)", "WPA2(PSK/AES/AES)", "WPA2(PSK/AES/AES)", "NONE",
       "WPA(PSK/AES,TKIP/TKIP) WPA2(PSK/AES,TKIP/TKIP)", "WPA2(802.1x/AES/AES)",
       "RSN(PSK,SAE/AES/AES)", "WPA3(SAE/AES/AES)", "WPA2(PSK,FT-PSK/AES/AES)",
       "WPA(PSK/TKIP/TKIP)", "WEP", "WPA2(PSK/AES,TKIP/TKIP)"]


def generate(rng):
    d = Doc()
    hidden_bssid = rng.random() < .3
    cc_default = rng.choice(["US", "GB", "DE", "FR", "CA", "AU", "NL"])
    header = ["SSID", "BSSID", "RSSI", "CHANNEL", "HT", "CC", "SECURITY (auth/unicast/group)"]
    bw = 0 if hidden_bssid else 17
    hdr = "SSID".rjust(32) + " " + "BSSID".ljust(bw) + " " + "RSSI CHANNEL HT CC SECURITY (auth/unicast/group)"
    d.line(hdr, "header", header)
    for _ in range(rng.randint(1, 18)):
        ssid = _ssid(rng)
        if len(ssid) > 32:
            ssid = ssid[:32]
        bssid = None if hidden_bssid else fake.mac(rng)
        rssi = str(rng.randint(-92, -30))
        band = rng.random()
        if band < .45:
            ch = str(rng.choice([1, 6, 11, 2, 3, 4, 8, 9]))
            if rng.random() < .3:
                ch += rng.choice([",+1", ",-1"])
        elif band < .9:
            ch = str(rng.choice([36, 40, 44, 48, 52, 100, 112, 132, 149, 153, 157, 161]))
            ch += rng.choice(["", ",+1", ",-1", ",80"])
        else:
            ch = f"{rng.choice([1, 5, 21, 37, 53])},6GHz"
        ht = rng.choice(["Y", "Y", "Y", "N"])
        cc = rng.choice([cc_default, cc_default, cc_default, "--", "X0"])
        sec = rng.choice(SEC)
        text = ssid.rjust(32) + " " + (bssid or "").ljust(bw) + " " + rssi.ljust(4) + " " + ch.ljust(7) + " " + \
            ht.ljust(2) + " " + cc.ljust(2) + " " + sec + (" " if rng.random() < .7 else "")
        d.line(text, "row", [ssid.strip(), bssid, rssi, ch, ht, cc, sec])
    return d
