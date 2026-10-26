"""hostapd `hostapd_cli all_sta`: per associated station, the MAC address alone
on a line, then `key=value` lines."""
from lib import Doc, fake

TOOL = "hostapd_cli-all_sta"


def generate(rng):
    d = Doc()
    iface = rng.choice(["wlan0", "wlan1", "wlp2s0", "ath0", "phy0-ap0", "wlan0-1"])
    if rng.random() < .8:
        d.line(f"Selected interface '{iface}'", "kv", ["Selected interface", iface])
    for _ in range(rng.randint(1, 4)):
        mac = fake.mac(rng)
        d.section(mac, mac)
        flags = "".join(f"[{f}]" for f in ["AUTH", "ASSOC", "AUTHORIZED"] +
                        rng.sample(["SHORT_PREAMBLE", "WMM", "MFP", "HT", "VHT", "HE", "WPS"], rng.randint(1, 4)))
        rx_b, tx_b = rng.randint(1000, 10 ** 10), rng.randint(1000, 10 ** 10)
        rate_r = rng.choice(["6000", "65000", "144400", "300000", "866700", "1200900"])
        pairs = [
            ("flags", flags),
            ("aid", str(rng.randint(1, 30))),
            ("capability", f"0x{rng.randint(1, 0xffff):x}"),
            ("listen_interval", rng.choice(["1", "5", "10", "20"])),
            ("supported_rates", " ".join(rng.sample("82 84 8b 96 0c 12 18 24 30 48 60 6c".split(), rng.randint(4, 12)))),
            ("timeout_next", rng.choice(["NULLFUNC POLL", "DEAUTH", "REMOVE"])),
        ]
        if rng.random() < .8:
            pairs += [
                ("dot11RSNAStatsSTAAddress", mac),
                ("dot11RSNAStatsVersion", "1"),
                ("dot11RSNAStatsSelectedPairwiseCipher", rng.choice(["00-0f-ac-4", "00-0f-ac-2", "00-0f-ac-8"])),
                ("dot11RSNAStatsTKIPLocalMICFailures", "0"),
                ("dot11RSNAStatsTKIPRemoteMICFailures", "0"),
                ("wpa", "2"),
                ("AKMSuiteSelector", rng.choice(["00-0f-ac-2", "00-0f-ac-8", "00-0f-ac-1"])),
                ("hostapdWPAPTKState", "11"),
                ("hostapdWPAPTKGroupState", "0"),
            ]
        pairs += [
            ("rx_packets", str(rng.randint(10, 10 ** 7))),
            ("tx_packets", str(rng.randint(10, 10 ** 7))),
            ("rx_bytes", str(rx_b)),
            ("tx_bytes", str(tx_b)),
            ("inactive_msec", str(rng.randint(0, 120000))),
            ("signal", str(rng.randint(-90, -25))),
            ("rx_rate_info", rate_r + rng.choice(["", f" vhtmcs {rng.randint(0, 9)} vhtnss {rng.randint(1, 4)}",
                                                  f" mcs {rng.randint(0, 15)}", f" shortGI"])),
            ("tx_rate_info", rng.choice(["6000", "72200", "433300", "866700"]) + rng.choice(["", " mcs 7 shortGI", f" vhtmcs {rng.randint(0, 9)} vhtnss 2 shortGI"])),
            ("connected_time", str(rng.randint(1, 10 ** 6))),
        ]
        if rng.random() < .5:
            pairs.append(("ht_mcs_bitmap", "ffff0000000000000000"))
        if rng.random() < .4:
            pairs.append(("ht_caps_info", f"0x{rng.randint(1, 0xffff):04x}"))
        if rng.random() < .3:
            pairs.append(("vht_caps_info", f"0x{rng.randint(1, 0xffffffff):08x}"))
        if rng.random() < .3:
            pairs.append(("keyid", rng.choice(["guest", "iot", fake.word(rng)])))
        for k, v in pairs:
            d.line(f"{k}={v}", "kv", [k, v])
    return d
