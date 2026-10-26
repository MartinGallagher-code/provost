"""ModemManager `mmcli -m 0`: boxed report, a section column, right-aligned
keys, `key: value` pairs, and wrapped continuation values."""
from lib import Doc, fake

TOOL = "mmcli-m"

VENDORS = [("Quectel", ["EC25", "EG25-G", "RM500Q-GL", "EM05-G"], "quectel"),
           ("Sierra Wireless, Incorporated", ["EM7455", "MC7304", "EM7565"], "sierra"),
           ("QUALCOMM INCORPORATED", ["QUECTEL Mobile Broadband Module", "0"], "generic"),
           ("Huawei Technologies Co., Ltd.", ["ME909s-120", "E3372"], "huawei"),
           ("Telit", ["LN940", "LE910C4-NF"], "telit")]
OPERATORS = [("23410", "O2 - UK"), ("23415", "Vodafone UK"), ("310260", "T-Mobile"),
             ("26201", "Telekom.de"), ("20801", "Orange F"), ("310410", "AT&T"), ("", "")]


def generate(rng):
    d = Doc()
    n = rng.randint(0, 3)
    base = "/org/freedesktop/ModemManager1"
    man, models, plugin = rng.choice(VENDORS)
    model = rng.choice(models)
    imei = "86" + "".join(rng.choice("0123456789") for _ in range(13))
    state = rng.choice(["connected", "registered", "enabled", "disabled", "searching", "locked", "failed"])
    tech = rng.choice(["lte", "umts", "hsdpa, hsupa", "5gnr", "lte, 5gnr", "unknown"])
    opid, opname = rng.choice(OPERATORS)
    ports = [("cdc-wdm0", "qmi"), ("ttyUSB0", "ignored"), ("ttyUSB1", "gps"), ("ttyUSB2", "at"),
             ("ttyUSB3", "at"), ("wwan0", "net")]
    if plugin == "huawei":
        ports = [("cdc-wdm0", "mbim"), ("ttyUSB0", "at"), ("ttyUSB2", "at"), ("wwan0", "net")]
    port_items = [f"{p} ({t})" for p, t in ports[:rng.randint(2, len(ports))]]

    def wrap(items, per):
        chunks = [items[i:i + per] for i in range(0, len(items), per)]
        out = [", ".join(c) for c in chunks]
        return [s + ("," if i < len(out) - 1 else "") for i, s in enumerate(out)]

    sections = []
    sections.append(("General", [("path", [f"{base}/Modem/{n}"]),
                                 ("device id", [fake.hexid(rng, 40)])]))
    hw = [("manufacturer", [man]), ("model", [model]),
          ("firmware revision", [rng.choice(["EC25EFAR06A06M4G", "SWI9X30C_02.33.03.00", "11.617.06.00.00",
                                             "RM500QGLABR11A06M4G", "M0F.660014"])])]
    if rng.random() < .6:
        hw.append(("carrier config", [rng.choice(["default", "ROW_Generic_3GPP", "Commercial-TMO", "VoLTE-ATT"])]))
    if rng.random() < .5:
        hw.append(("h/w revision", [rng.choice(["10000", "EM7455", "1.0", "20000"])]))
    hw += [("supported", [rng.choice(["gsm-umts, lte", "gsm-umts, lte, 5gnr", "lte"])]),
           ("current", [rng.choice(["gsm-umts, lte", "lte", "gsm-umts, lte, 5gnr"])]),
           ("equipment id", [imei])]
    sections.append(("Hardware", hw))
    sysp = [("device", [f"/sys/devices/platform/{rng.choice(['soc', 'scb/fd500000.pcie', 'pci0000:00'])}"
                        f"/usb{rng.randint(1, 3)}/{rng.randint(1, 3)}-{rng.randint(1, 4)}"]),
            ("drivers", [rng.choice(["option, qmi_wwan", "cdc_mbim, option", "qcserial, qmi_wwan", "cdc_acm"])]),
            ("plugin", [plugin]), ("primary port", [ports[0][0]])]
    sysp.append(("ports", wrap(port_items, rng.randint(2, 4))))
    sections.append(("System", sysp))
    st = []
    if rng.random() < .6:
        st.append(("lock", [rng.choice(["sim-pin2", "none", "sim-pin"])]))
        st.append(("unlock retries", [rng.choice(["sim-pin (3), sim-puk (10), sim-pin2 (3), sim-puk2 (10)",
                                                   "sim-pin (3), sim-puk (10)"])]))
    st += [("state", [state]), ("power state", [rng.choice(["on", "low", "off"])])]
    if state in ("connected", "registered", "enabled"):
        st.append(("access tech", [tech]))
        st.append(("signal quality", [f"{rng.randint(0, 100)}% ({rng.choice(['recent', 'cached'])})"]))
    if state == "failed":
        st.append(("failed reason", [rng.choice(["sim-missing", "unknown-capabilities"])]))
    sections.append(("Status", st))
    modes = rng.sample(["allowed: 3g; preferred: none", "allowed: 4g; preferred: none",
                        "allowed: 3g, 4g; preferred: 4g", "allowed: 3g, 4g; preferred: 3g",
                        "allowed: 5g; preferred: none", "allowed: 4g, 5g; preferred: 5g"], rng.randint(1, 4))
    sections.append(("Modes", [("supported", modes),
                               ("current", [rng.choice(modes)])]))
    if rng.random() < .6:
        sections.append(("Bands", [("supported", wrap([f"eutran-{b}" for b in sorted(rng.sample(range(1, 72), rng.randint(3, 14)))], 6)),
                                   ("current", wrap([f"eutran-{b}" for b in sorted(rng.sample(range(1, 72), rng.randint(2, 8)))], 6))]))
    sections.append(("IP", [("supported", ["ipv4, ipv6, ipv4v6"])]))
    g = [("imei", [imei])]
    if rng.random() < .5:
        g.append(("enabled locks", [rng.choice(["fixed-dialing", "sim, fixed-dialing", "none"])]))
    if opid:
        g += [("operator id", [opid]), ("operator name", [opname])]
    g.append(("registration", [rng.choice(["home", "roaming", "searching", "idle", "denied"])]))
    if rng.random() < .6:
        g.append(("packet service state", [rng.choice(["attached", "detached"])]))
    sections.append(("3GPP", g))
    if rng.random() < .6:
        sections.append(("3GPP EPS", [("ue mode of operation", [rng.choice(["csps-1", "csps-2", "ps-2"])]),
                                      ("initial bearer path", [f"{base}/Bearer/{rng.randint(0, 9)}"]),
                                      ("initial bearer apn", [rng.choice(["ims", "internet", "three.co.uk", "fast.t-mobile.com"])]),
                                      ("initial bearer ip type", [rng.choice(["ipv4", "ipv4v6"])])]))
    sim = [("primary sim path", [f"{base}/SIM/{rng.randint(0, 3)}"])]
    if rng.random() < .4:
        sim.append(("sim slot paths", [f"slot 1: {base}/SIM/0 (active)", "slot 2: none"]))
    sections.append(("SIM", sim))
    if rng.random() < .7:
        sections.append(("Bearer", [("paths", [f"{base}/Bearer/{rng.randint(0, 9)}"])]))

    kw = max(len(k) for _, kvs in sections for k, _ in kvs) + rng.choice([0, 0, 2])
    sw = max(len(s) for s, _ in sections)
    rule = "  " + "-" * (sw + kw + 8)
    for s, kvs in sections:
        d.skip(rule)
        for i, (k, vals) in enumerate(kvs):
            lead = "  " + (s if i == 0 else "").ljust(sw) + " | "
            text = lead + k.rjust(kw) + ": " + vals[0]
            d.line(text, "kv", ([s] if i == 0 else []) + [k, vals[0]])
            for v in vals[1:]:
                d.line("  " + "".ljust(sw) + " | " + " " * (kw + 2) + v, "cont", [v])
    return d
