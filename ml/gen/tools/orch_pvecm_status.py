"""Proxmox `pvecm status`: dashed-underlined sections of fixed-width
`Key:  value` lines, ending in a Membership table with right-aligned
Nodeid/Votes columns (and an optional Qdevice column)."""
from lib import Doc, fake

TOOL = "pvecm-status"


def generate(rng):
    d = Doc()
    kw = 18

    def sec(title):
        d.section(title)
        d.skip("-" * len(title))

    def kv(k, v, trail=""):
        d.line((k + ":").ljust(kw) + v + trail, "kv", [k, v])

    n = rng.randint(2, 7)
    qdev = n % 2 == 0 and rng.random() < 0.6
    online = n - (1 if rng.random() < .2 else 0)
    votes = online + (1 if qdev else 0)
    expected = n + (1 if qdev else 0)
    sec("Cluster information")
    kv("Name", rng.choice(["pve-cluster", "homelab", "prod-" + fake.word(rng), fake.word(rng) + "-pve", "cluster01"]))
    kv("Config Version", str(rng.randint(1, 40)))
    kv("Transport", rng.choice(["knet", "knet", "udpu"]))
    kv("Secure auth", "on")
    d.blank()
    sec("Quorum information")
    mon = rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())
    day = rng.choice("Mon Tue Wed Thu Fri Sat Sun".split())
    kv("Date", f"{day} {mon} {rng.randint(1, 28):2d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:"
               f"{rng.randint(0, 59):02d} {rng.randint(2021, 2026)}")
    kv("Quorum provider", "corosync_votequorum")
    kv("Nodes", str(online))
    local = rng.randint(1, online)
    kv("Node ID", f"0x{local:08x}")
    kv("Ring ID", f"{rng.randint(1, n)}.{rng.randint(1, 4000):x}")
    quorate = votes > expected // 2
    kv("Quorate", "Yes" if quorate else "No")
    d.blank()
    sec("Votequorum information")
    kv("Expected votes", str(expected))
    kv("Highest expected", str(expected))
    kv("Total votes", str(votes))
    if quorate:
        kv("Quorum", str(expected // 2 + 1), "  ")
    else:
        kv("Quorum", f"{expected // 2 + 1} Activity blocked")
    flags = ("Quorate " if quorate else "") + ("Qdevice " if qdev else "")
    if flags.strip():
        kv("Flags", flags.strip(), " ")
    else:
        d.line("Flags:            ", "skip")
    d.blank()
    sec("Membership information")
    names = rng.random() < 0.3
    base = f"{rng.choice(['192.168', '10.0', '172.16'])}.{rng.randint(0, 20)}"
    ip0 = rng.randint(2, 200)
    if qdev:
        d.line("    Nodeid      Votes    Qdevice Name", "header", ["Nodeid", "Votes", "Qdevice", "Name"])
    else:
        d.line("    Nodeid      Votes Name", "header", ["Nodeid", "Votes", "Name"])
    for i in range(1, online + 1):
        nid = f"0x{i:08x}"
        host = f"pve{i}" if names else f"{base}.{ip0 + i}"
        name = host + (" (local)" if i == local else "")
        if qdev:
            q = rng.choice(["A,V,NMW", "A,V,NMW", "A,NV,NMW", "NR"])
            d.line(f"{nid:>10} {'1':>10} {q:>10} {name}", "row", [nid, "1", q, name])
        else:
            d.line(f"{nid:>10} {'1':>10} {name}", "row", [nid, "1", name])
    if qdev:
        d.line(f"{'0x00000000':>10} {'1':>10} {'':>10} Qdevice", "row", ["0x00000000", "1", None, "Qdevice"])
    return d
