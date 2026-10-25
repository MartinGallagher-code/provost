"""SoapySDR `SoapySDRUtil --find` and `--probe`: the `##` banner, `Found
device N` blocks of `key = value`, and the probe report: `-- Section`
headings between rules, `Key: value` lines, `* Setting - description` items
with `[key=..., default=..., ...]` argument rows."""
from lib import Doc, fake

TOOL = "SoapySDRUtil"

DEVS = {
    "rtlsdr": dict(ident=[("driver", "RTLSDR"), ("hardware", "R820T"), ("index", "0"),
                          ("origin", "https://github.com/pothosware/SoapyRTLSDR")],
                   find=[("driver", "rtlsdr"), ("label", "Generic RTL2832U OEM :: {ser}"), ("manufacturer", "Realtek"),
                         ("product", "RTL2838UHIDIR"), ("serial", "{ser}"), ("tuner", "Rafael Micro R820T")],
                   tx=0, gain=[("TUNER", "[0, 49.6] dB")], full_gain="[0, 49.6] dB",
                   freq=[("RF", "[24, 1766] MHz"), ("CORR", "[-1000, 1000] MHz")], full_freq="[23.999, 1764] MHz",
                   rates="0.25, 1.024, 1.536, 1.792, 1.92, 2.048, 2.16, 2.56, 2.88, 3.2 MSps",
                   formats="CS8, CS16, CF32", native="CS8 [full-scale=128]", ant="RX",
                   log="Found Rafael Micro R820T tuner"),
    "hackrf": dict(ident=[("driver", "HackRF"), ("hardware", "HackRF One"), ("origin", "https://github.com/pothosware/SoapyHackRF"),
                          ("part_id", "a000cb3c00{p}"), ("serial", "{ser}"), ("version", "2023.01.1")],
                   find=[("device", "HackRF One"), ("driver", "hackrf"), ("label", "HackRF One #0 {ser}"),
                         ("part_id", "a000cb3c00{p}"), ("serial", "{ser}"), ("version", "2023.01.1")],
                   tx=1, gain=[("AMP", "[0, 14, 14] dB"), ("LNA", "[0, 40, 8] dB"), ("VGA", "[0, 62, 2] dB")],
                   full_gain="[0, 116] dB", freq=[("RF", "[0, 7250] MHz"), ("BB", "[0, 0] MHz")],
                   full_freq="[0, 7250] MHz", rates="[1, 20] MSps", formats="CS8, CS16, CF32, CF64",
                   native="CS8 [full-scale=128]", ant="TX/RX", log=None),
    "airspy": dict(ident=[("driver", "Airspy"), ("hardware", "Airspy"), ("origin", "https://github.com/pothosware/SoapyAirspy")],
                   find=[("driver", "airspy"), ("label", "AirSpy One [{ser}]"), ("serial", "{ser}")],
                   tx=0, gain=[("LNA", "[0, 15] dB"), ("MIX", "[0, 15] dB"), ("VGA", "[0, 15] dB")],
                   full_gain="[0, 45] dB", freq=[("RF", "[24, 1800] MHz")], full_freq="[24, 1800] MHz",
                   rates="2.5, 10 MSps", formats="CS16, CF32", native="CS16 [full-scale=2048]", ant="RX", log=None),
}
SETTINGS = [("Direct Sampling", "RTL-SDR Direct Sampling Mode", "key=direct_samp, default=0, type=string, options=(0, 1, 2)"),
            ("Offset Tune", "RTL-SDR Offset Tuning Mode", "key=offset_tune, default=false, type=bool"),
            ("I/Q Swap", "RTL-SDR I/Q Swap Mode", "key=iq_swap, default=false, type=bool"),
            ("Digital AGC", "RTL-SDR digital AGC Mode", "key=digital_agc, default=false, type=bool"),
            ("Bias Tee", "Enable the 4.5v Bias-Tee", "key=biastee, default=false, type=bool"),
            ("Buffer Size", "Number of bytes per buffer, multiples of 512 only.",
             "key=bufflen, units=bytes, default=262144, type=int")]


def pairs_cells(s):
    out = []
    i = 0
    while i < len(s):
        eq = s.index("=", i)
        out.append(s[i:eq].strip(" ,"))
        j = eq + 1
        if s[j] == "(":
            k = s.index(")", j) + 1
        else:
            k = s.find(",", j)
            k = len(s) if k < 0 else k
        out.append(s[j:k])
        i = k + 1
    return out


def banner(d):
    d.skip("######################################################")
    d.skip("##     Soapy SDR -- the SDR abstraction library     ##")
    d.skip("######################################################")
    d.blank()


def rule_section(d, title):
    d.skip("-" * 52)
    d.line(f"-- {title}", "section", [title])
    d.skip("-" * 52)


def setting(d, name, desc, args, ind="     "):
    d.line(f"{ind}* {name} - {desc}", "kv", [name, desc])
    d.line(f"{ind}  [{args}]", "row", pairs_cells(args))


def generate(rng):
    d = Doc()
    banner(d)
    kinds = rng.sample(list(DEVS), rng.randint(1, 3))
    ser = lambda: fake.hexid(rng, rng.choice([8, 16, 32]))
    if rng.random() < .45:
        for i, k in enumerate(kinds):
            dv = DEVS[k]
            s, p = ser(), fake.hexid(rng, 6)
            d.line(f"Found device {i}", "section", [f"Found device {i}"])
            for key, v in dv["find"]:
                d.line(f"  {key} = {v.format(ser=s, p=p)}", "kv", [key, v.format(ser=s, p=p)])
            d.blank()
        return d
    k = kinds[0]
    dv = DEVS[k]
    s, p = ser(), fake.hexid(rng, 6)
    d.line(f"Probe device driver={k}", "kv", ["Probe device", "driver", k])
    if rng.random() < .5:
        lab = dict(dv["find"]).get("label", k).format(ser=s, p=p)
        d.line(f"[INFO] Opening {lab}...", "row", ["[INFO]", f"Opening {lab}..."])
    if dv["log"]:
        d.skip(dv["log"])
    d.blank()
    rule_section(d, "Device identification")
    for key, v in dv["ident"]:
        v = v.format(ser=s, p=p)
        d.line(f"  {key}={v}", "kv", [key, v])
    d.blank()
    rule_section(d, "Peripheral summary")
    d.line(f"  Channels: 1 Rx, {dv['tx']} Tx", "kv", ["Channels", f"1 Rx, {dv['tx']} Tx"])
    ts = rng.choice(["NO", "YES"])
    d.line(f"  Timestamps: {ts}", "kv", ["Timestamps", ts])
    if k == "rtlsdr" or rng.random() < .4:
        d.line("  Other Settings:", "section", ["Other Settings"])
        for name, desc, args in rng.sample(SETTINGS[:5], rng.randint(1, 5)):
            setting(d, name, desc, args)
    if rng.random() < .3:
        d.line("  Sensors: lo_locked", "kv", ["Sensors", "lo_locked"])
    d.blank()
    chans = [("RX", 0)] + ([("TX", 0)] if dv["tx"] else [])
    for direction, n in chans:
        rule_section(d, f"{direction} Channel {n}")
        d.line("  Full-duplex: NO", "kv", ["Full-duplex", "NO"])
        agc = "YES" if direction == "RX" and k != "hackrf" else "NO"
        d.line(f"  Supports AGC: {agc}", "kv", ["Supports AGC", agc])
        d.line(f"  Stream formats: {dv['formats']}", "kv", ["Stream formats", dv["formats"]])
        d.line(f"  Native format: {dv['native']}", "kv", ["Native format", dv["native"]])
        if direction == "RX" and k == "rtlsdr":
            d.line("  Stream args:", "section", ["Stream args"])
            setting(d, *SETTINGS[5])
            if rng.random() < .6:
                setting(d, "Ring buffers", "Number of buffers in the ring.", "key=buffers, units=buffers, default=15, type=int")
        d.line(f"  Antennas: {dv['ant']}", "kv", ["Antennas", dv["ant"]])
        if k == "rtlsdr" or rng.random() < .3:
            d.line("  Corrections: PPM, DC offset" if k != "rtlsdr" else "  Corrections: PPM", "kv",
                   ["Corrections", "PPM, DC offset" if k != "rtlsdr" else "PPM"])
        d.line(f"  Full gain range: {dv['full_gain']}", "kv", ["Full gain range", dv["full_gain"]])
        for g, r in dv["gain"]:
            d.line(f"    {g} gain range: {r}", "kv", [f"{g} gain range", r])
        d.line(f"  Full freq range: {dv['full_freq']}", "kv", ["Full freq range", dv["full_freq"]])
        for f, r in dv["freq"]:
            d.line(f"    {f} freq range: {r}", "kv", [f"{f} freq range", r])
        d.line(f"  Sample rates: {dv['rates']}", "kv", ["Sample rates", dv["rates"]])
        if k == "hackrf":
            d.line("  Filter bandwidths: [1.75, 28] MHz", "kv", ["Filter bandwidths", "[1.75, 28] MHz"])
        d.blank()
    return d
