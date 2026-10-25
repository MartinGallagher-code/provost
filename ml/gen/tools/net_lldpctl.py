"""lldpd `lldpctl`: rule-delimited neighbor blocks; an Interface line with
several `key: value` pairs, then indented Chassis/Port/VLAN key/value groups."""
from lib import Doc, fake

TOOL = "lldpctl"

RULE = "-" * 79


def _kv(d, indent, key, val, w=14):
    d.line(" " * indent + (key + ":").ljust(w) + val, "kv", [key, val])


def generate(rng):
    d = Doc()
    d.skip(RULE)
    d.section("LLDP neighbors:")
    d.skip(RULE)
    for i in range(rng.randint(1, 4)):
        ifname = rng.choice(["eth0", "eth1", "eno1", "eno2", "enp3s0", "ens192", "swp" + str(rng.randint(1, 48))])
        via = rng.choice(["LLDP", "LLDP", "LLDP", "CDPv2", "EDP"])
        rid = str(i + rng.randint(1, 3))
        nd = rng.choice([0, 0, rng.randint(1, 400)])
        t = f"{nd} day{'s' if nd != 1 else ''}, {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
        head = "Interface:    "
        text = f"{head}{ifname}, via: {via}, RID: {rid}, Time: {t}"
        d.line(text, "row", ["Interface", ifname, "via", via, "RID", rid, "Time", t])
        d.line("  Chassis:     ", "section", ["Chassis"])
        cid = rng.choice([f"mac {fake.mac(rng)}", f"local {fake.hexid(rng, 8).upper()}"])
        _kv(d, 4, "ChassisID", cid)
        sysname = rng.choice([fake.host(rng), f"sw-{fake.word(rng)}-{rng.randint(1, 9)}", f"core{rng.randint(1, 4)}.dc{rng.randint(1, 3)}.example.net"])
        _kv(d, 4, "SysName", sysname)
        descr = rng.choice([
            f"Cisco IOS Software, C2960X Software (C2960X-UNIVERSALK9-M), Version 15.2({rng.randint(1, 7)})E{rng.randint(1, 9)}, RELEASE SOFTWARE (fc1)",
            f"Juniper Networks, Inc. ex2300-24p Ethernet Switch, kernel JUNOS {rng.randint(18, 23)}.{rng.randint(1, 4)}R{rng.randint(1, 3)}",
            f"Debian GNU/Linux 12 (bookworm) Linux 6.1.0-{rng.randint(10, 30)}-amd64 #1 SMP PREEMPT_DYNAMIC x86_64",
            f"Arista Networks EOS version 4.{rng.randint(20, 31)}.{rng.randint(0, 9)}F running on an Arista Networks DCS-7050SX-64",
            "MikroTik RouterOS 7.12.1 (stable) CRS326-24G-2S+",
        ])
        _kv(d, 4, "SysDescr", descr)
        for _ in range(rng.randint(0, 2)):
            _kv(d, 4, "MgmtIP", fake.ip(rng, v6=rng.random() < .25))
        if rng.random() < .4:
            _kv(d, 4, "MgmtIface", str(rng.randint(1, 60)))
        for cap in rng.sample(["Bridge", "Router", "Wlan", "Station", "Repeater", "Tel"], rng.randint(1, 3)):
            on = rng.choice(["on", "off"])
            d.line("    " + "Capability:".ljust(14) + f"{cap}, {on}", "kv", ["Capability", cap, on])
        d.line("  Port:        ", "section", ["Port"])
        pnum = f"{rng.randint(1, 2)}/0/{rng.randint(1, 48)}"
        pid = rng.choice([f"ifname Gi{pnum}", f"ifname ge-0/0/{rng.randint(0, 47)}", f"mac {fake.mac(rng)}",
                          f"local {rng.randint(1, 600)}", f"ifname Ethernet{rng.randint(1, 54)}"])
        _kv(d, 4, "PortID", pid)
        _kv(d, 4, "PortDescr", rng.choice([f"GigabitEthernet{pnum}", f"uplink to {fake.word(rng)}", ifname,
                                            f"ge-0/0/{rng.randint(0, 47)}.0", "Not received"]))
        _kv(d, 4, "TTL", rng.choice(["120", "120", "180", "3600", "20"]))
        if rng.random() < .5:
            _kv(d, 4, "MFS", str(rng.choice([1514, 1522, 9216])))
        if rng.random() < .4:
            d.line("    PMD autoneg:  supported: yes, enabled: yes", "row",
                   ["PMD autoneg", "supported", "yes", "enabled", "yes"])
            mau = rng.choice(["1000BaseTFD - Four-pair Category 5 UTP, full duplex mode",
                              "10GigBaseSR - R PCS/PMA, 850 nm serial",
                              "100BaseTXFD - 2 pair category 5 UTP, full duplex mode"])
            _kv(d, 6, "MAU oper type", mau, 16)
        for _ in range(rng.choice([0, 1, 1, 2])):
            vid = str(rng.randint(1, 4094))
            pvid = rng.choice(["yes", "no"])
            if rng.random() < .5:
                vname = f"VLAN{vid.zfill(4)}" if rng.random() < .5 else \
                    rng.choice(["mgmt", "servers", "voice", "guest", "storage", f"v{vid}-{fake.word(rng)}"])
                d.line(f"  VLAN:         {vid}, pvid: {pvid} {vname}", "row", ["VLAN", vid, "pvid", pvid, vname])
            else:
                d.line(f"  VLAN:         {vid}, pvid: {pvid}", "row", ["VLAN", vid, "pvid", pvid])
        if rng.random() < .3:
            d.line("  LLDP-MED:    ", "section", ["LLDP-MED"])
            _kv(d, 4, "Device Type", rng.choice(["Network Connectivity Device", "Generic Endpoint (Class I)"]))
        d.skip(RULE)
    return d
