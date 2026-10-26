"""batman-adv `batctl o` (originators): a bracketed banner, then a table of
originators with last-seen, link quality (#/255 for BATMAN_IV, throughput
for BATMAN_V), next hop and outgoing interface; `*` marks the best route."""
from lib import Doc, fake

TOOL = "batctl-o"


def generate(rng):
    d = Doc()
    algo = rng.choice(["BATMAN_IV", "BATMAN_IV", "BATMAN_V"])
    ver = rng.choice(["2019.2", "2021.0", "2022.0", "2023.1", "2024.2"])
    mif = rng.choice(["eth0", "wlan0", "mesh0", "wlan0-mesh", "enp1s0"])
    prefix = rng.choice(["02:ba:7a:df", fake.mac(rng)[:11], "ae:54:87:ff"])
    mmac = f"{prefix}:{rng.randint(0, 255):02x}:00"
    bmac = fake.mac(rng)
    main, mesh, verstr = f"{mif}/{mmac}", f"bat0/{bmac}", f"B.A.T.M.A.N. adv {ver}"
    d.line(f"[{verstr}, MainIF/MAC: {main} ({mesh} {algo})]", "row",
           [verstr, "MainIF/MAC", main, mesh, algo])
    tq_col = "(#/255)" if algo == "BATMAN_IV" else "( throughput)"
    header = [None, "Originator", "last-seen", tq_col, "Nexthop", "[outgoingIF]"]
    d.line(f"   Originator        last-seen {tq_col}{' ' if algo == 'BATMAN_IV' else '  '}Nexthop           [outgoingIF]",
           "header", header)
    ifaces = [mif] + rng.sample(["wlan1", "eth1", "mesh1", "tun0", "wlan0-1"], rng.randint(0, 2))
    nodes = [f"{prefix}:{rng.randint(0, 255):02x}:00" for _ in range(rng.randint(1, 10))]
    nodes = list(dict.fromkeys(nodes))
    for node in nodes:
        routes = rng.choice([1, 1, 2, 3])
        hops = [node] + [rng.choice(nodes) for _ in range(routes - 1)]
        for k, nh in enumerate(hops):
            best = k == 0
            seen = f"{rng.uniform(0, 12):.3f}s"
            if algo == "BATMAN_IV":
                q = rng.randint(30, 255) if best else rng.randint(1, 230)
                tq = f"({q:3d})"
                qcell = f"({q})" if q >= 100 else tq
            else:
                tp = rng.choice([rng.uniform(1, 999), rng.uniform(100, 3000)])
                tq = f"({tp:10.1f})"
                qcell = tq
            ifc = rng.choice(ifaces)
            mark = " * " if best else "   "
            text = f"{mark}{node} {seen:>8}   {tq} {nh} [{ifc:>10}]"
            d.line(text, "row", ["*" if best else None, node, seen, qcell, nh, ifc])
    return d
