"""Asterisk `asterisk -rx 'sip show peers'`: chan_sip's fixed-width table
(single-space gutters, padded and truncated columns, many empty cells) and
its `N sip peers [Monitored: ...]` footer."""
from lib import Doc, fake

TOOL = "asterisk-rx-sip-show-peers"

TRUNKS = ["voipms", "twilio-trunk", "flowroute", "sipgate", "telnyx_out", "provider-main",
          "bandwidth-e911-backup-trunk-primary", "andrews_arnold"]
DESC = ["", "", "", "Reception", "Sales desk", "Warehouse DECT base", "Fax ATA", "Conference room phone",
        "Main office trunk to upstream carrier (redundant)"]


def fmt(vals):
    w = [25, 39, 3, 10, 10, 3, 8, 11, 32]
    out = ""
    for i, v in enumerate(vals[:9]):
        out += (v if i == 7 else v[:w[i]]).ljust(w[i]) + " "
    return out + (vals[9] if len(vals) > 9 else "")


def generate(rng):
    d = Doc()
    rt = rng.random() < .25
    hdr = ["Name/username", "Host", "Dyn", "Forcerport", "Comedia", "ACL", "Port", "Status", "Description",
           "Realtime" if rt else ""]
    d.line(fmt(hdr), "header", hdr if rt else hdr[:9])
    peers = []
    ext0 = rng.choice([100, 200, 1000, 2000, 6000])
    exts = sorted(rng.sample(range(ext0, ext0 + 60), rng.randint(1, 12)))
    for e in exts:
        peers.append(str(e))
    peers += rng.sample(TRUNKS, rng.randint(0, 3))
    peers.sort()
    on = off = unmon_on = unmon_off = 0
    for p in peers:
        trunk = not p.isdigit()
        dyn = "D" if not trunk or rng.random() < .2 else ""
        if rng.random() < .3:
            name = p
        else:
            name = f"{p}/{p}" if not trunk else f"{p}/{rng.choice(['1234567', 'acct' + fake.num(rng, 100, 99999), p])}"
        reachable = rng.random() < .65
        monitored = rng.random() < .85
        if trunk:
            host = rng.choice(["sip.example-carrier.net", "atlanta.voip.ms", fake.ip(rng),
                               "us-east.sip.telnyx.example.com"])
        elif reachable:
            host = rng.choice([fake.ip(rng), fake.ip(rng), fake.ip(rng, v6=True)])
        else:
            host = "(Unspecified)"
        nat = rng.choice(["Auto (No)", "Auto (Yes)", "Yes", "No"])
        com = rng.choice(["No", "Yes", "Auto (No)", "Auto (Yes)"])
        acl = "A" if rng.random() < .2 else ""
        port = rng.choice(["5060", "5060", "5061", str(rng.randint(1024, 65535))]) if host != "(Unspecified)" else "0"
        if not monitored:
            status = "Unmonitored"
            if host == "(Unspecified)":
                unmon_off += 1
            else:
                unmon_on += 1
        elif host == "(Unspecified)":
            status = rng.choice(["UNKNOWN", "UNREACHABLE"])
            off += 1
        else:
            status = rng.choice([f"OK ({rng.randint(1, 450)} ms)", f"OK ({rng.randint(1, 40)} ms)", "LAGGED (2104 ms)"])
            on += 1
        desc = rng.choice(DESC)
        rtv = rng.choice(["Cached RT", ""]) if rt else ""
        vals = [name, host, dyn, nat, com, acl, port, status, desc, rtv]
        cells = [v[:w] if v else None for v, w in zip(vals, [25, 39, 3, 10, 10, 3, 8, 99, 32, 99])]
        d.line(fmt(vals), "row", cells if rt else cells[:9])
    n = len(peers)
    d.skip(f"{n} sip peers [Monitored: {on} online, {off} offline Unmonitored: {unmon_on} online, {unmon_off} offline]")
    return d
