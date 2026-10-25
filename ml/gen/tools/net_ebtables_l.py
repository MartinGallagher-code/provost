"""Linux `ebtables -L` (optionally --Ln / --Lc): a `Bridge table:` line, then
per chain a header line of `key: value` pairs and one line per rule; with
--Lc each rule ends in `, pcnt = N -- bcnt = N` counters."""
from lib import Doc, fake

TOOL = "ebtables-L"

CHAINS = {"filter": ["INPUT", "FORWARD", "OUTPUT"], "nat": ["PREROUTING", "OUTPUT", "POSTROUTING"],
          "broute": ["BROUTING"]}


def _rule(rng):
    ifc = rng.choice(["eth0", "eth1", "veth+", "tap0", "vnet3", "wlan0", "bond0"])
    return rng.choice([
        "-p ARP -j ACCEPT",
        f"-p IPv4 -i {ifc} -j ACCEPT",
        f"-s {fake.mac(rng)} -j DROP",
        f"-d Broadcast -i {ifc} -j DROP",
        f"-p ARP --arp-ip-src {fake.ip(rng)} -j ACCEPT",
        f"-p IPv4 --ip-src {fake.ip(rng)}/24 --ip-proto udp --ip-dport 67 -j DROP",
        f"-p 802_1Q --vlan-id {rng.randint(2, 4094)} -j ACCEPT",
        f"-i {ifc} --log-level notice --log-prefix \"EBT {fake.word(rng)}\" --log-ip -j CONTINUE",
        f"-p IPv6 -o {ifc} -j DROP",
        f"-s ! {fake.mac(rng)} -i {ifc} -j DROP",
        f"-j {fake.word(rng).upper()}-{rng.randint(1, 9)}",
        f"-p ARP -j arpreply --arpreply-mac {fake.mac(rng)} --arpreply-target ACCEPT",
        f"-i {ifc} -j mark --mark-set 0x{rng.randint(1, 255):x} --mark-target CONTINUE",
        f"-d {fake.mac(rng)} -j dnat --to-dst {fake.mac(rng)} --dnat-target ACCEPT",
    ])


def generate(rng):
    d = Doc()
    table = rng.choice(["filter", "filter", "filter", "nat", "broute"])
    numbered = rng.random() < .35
    counters = rng.random() < .45
    d.line(f"Bridge table: {table}", "kv", ["Bridge table", table])
    chains = list(CHAINS[table])
    if rng.random() < .35:
        chains += [f"{fake.word(rng).upper()}-{rng.randint(1, 9)}" for _ in range(rng.randint(1, 2))]
    for ch in chains:
        d.blank()
        n = rng.choice([0, 1, 2, 3, 5, 8])
        policy = rng.choice(["ACCEPT", "ACCEPT", "DROP"]) if ch in CHAINS[table] else \
            rng.choice(["RETURN", "ACCEPT", "DROP"])
        d.line(f"Bridge chain: {ch}, entries: {n}, policy: {policy}", "row",
               ["Bridge chain", ch, "entries", str(n), "policy", policy])
        for i in range(1, n + 1):
            r = _rule(rng)
            cells, text = [], ""
            if numbered:
                text += f"{i}. "
                cells.append(f"{i}.")
            text += r
            cells.append(r)
            if counters:
                pc = rng.choice([0, rng.randint(0, 999), rng.randint(0, 10 ** 7)])
                bc = pc * rng.randint(42, 1500)
                text += f" , pcnt = {pc} -- bcnt = {bc}"
                cells += ["pcnt", str(pc), "bcnt", str(bc)]
            d.line(text, "row", cells)
    return d
