"""FD.io VPP `vppctl show interface`: a centered header, then per interface
one row of Name/Idx/State/MTU plus its first counter, and its remaining
counters on lines that leave the first four columns empty."""
from lib import Doc, fake

TOOL = "vppctl-show-interface"

W = (32, 5, 10, 21, 16, 16)


def generate(rng):
    d = Doc()
    header = ["Name", "Idx", "State", "MTU (L3/IP4/IP6/MPLS)", "Counter", "Count"]
    text = "".join(h.center(w) for h, w in zip(header, W))
    d.line(text.rstrip() if rng.random() < .5 else text, "header", header)
    names = ["local0"]
    pool = [f"GigabitEthernet0/{rng.randint(3, 9)}/0", f"TenGigabitEthernet{rng.randint(1, 9)}/0/{rng.randint(0, 1)}",
            f"VirtualFunctionEthernet0/{rng.randint(4, 9)}/{rng.randint(0, 7)}", f"host-{fake.word(rng)}{rng.randint(0, 9)}",
            "loop0", "loop1", "tap0", f"memif{rng.randint(0, 3)}/0", "ipip0", "vxlan_tunnel0",
            f"FortyGigabitEthernet{rng.randint(1, 9)}/0/0", f"af-packet-{fake.word(rng)}", "wg0", "bond0"]
    names += rng.sample(pool, rng.randint(1, 6))
    subs = []
    for n in names:
        subs.append(n)
        if "Ethernet" in n and rng.random() < .3:
            subs.append(f"{n}.{rng.randint(2, 4000)}")
    for idx, n in enumerate(subs):
        up = n != "local0" and rng.random() < .8
        state = "up" if up else "down"
        if n == "local0":
            mtu = "0/0/0/0"
        else:
            l3 = rng.choice(["9000", "1500", "9000", "1460", "2026"])
            mtu = rng.choice([f"{l3}/0/0/0", f"{l3}/{l3}/{l3}/0", f"{l3}/0/0/0"])
        counters = []
        if up:
            rxp, txp = rng.randint(0, 10 ** 9), rng.randint(0, 10 ** 9)
            counters += [("rx packets", rxp), ("rx bytes", rxp * rng.randint(60, 1500)),
                         ("tx packets", txp), ("tx bytes", txp * rng.randint(60, 1500))]
            for c in rng.sample(["drops", "punt", "ip4", "ip6", "rx-miss", "rx-no-buf", "tx-error", "rx-error"],
                                rng.randint(0, 4)):
                counters.append((c, rng.randint(1, 10 ** 6)))
            if rng.random() < .15:
                counters = counters[:2]
        first = n.ljust(W[0]) + str(idx).center(W[1]) + state.center(W[2]) + mtu.center(W[3])
        if counters:
            c, v = counters[0]
            d.line(first + c.ljust(W[4]) + str(v).rjust(W[5]), "row", [n, str(idx), state, mtu, c, str(v)])
            for c, v in counters[1:]:
                d.line(" " * sum(W[:4]) + c.ljust(W[4]) + str(v).rjust(W[5]), "row",
                       [None, None, None, None, c, str(v)])
        else:
            tail = " " * rng.choice([0, 6])
            d.line(first.rstrip() + tail, "row", [n, str(idx), state, mtu, None, None])
    return d
