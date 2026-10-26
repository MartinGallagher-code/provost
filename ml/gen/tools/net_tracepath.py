"""iputils `tracepath`: one fixed-layout line per probe (hop, host, RTT, then
an optional asymm/reached/pmtu note), `no reply` hops, and a Resume summary."""
from lib import Doc, fake

TOOL = "tracepath"


def _hostname(rng):
    return rng.choice([
        f"ae{rng.randint(0, 9)}.cr{rng.randint(1, 9)}.{rng.choice(['fra', 'lon', 'ams', 'nyc', 'sjc'])}{rng.randint(1, 3)}.example.net",
        f"{fake.ip(rng)}",
        f"be{rng.randint(10, 99)}.{rng.choice(['ccr', 'agr', 'rcr'])}{rng.randint(10, 99)}.{rng.choice(['par01', 'dca01', 'iad02'])}.atlas.cogentco.com",
        f"{rng.randint(1, 254)}-{rng.randint(1, 254)}-{rng.randint(1, 254)}.static.isp{rng.randint(1, 9)}.net",
        f"xe-{rng.randint(0, 7)}-0-{rng.randint(0, 3)}.edge{rng.randint(1, 6)}.example.org",
    ])


def generate(rng):
    d = Doc()
    six = rng.random() < .2
    pmtu = rng.choice([1500, 1500, 1500, 1492, 1480, 1450, 9000])
    hw = rng.choice([52, 52, 49, 46])
    both = rng.random() < .3
    target_name = rng.choice(["example.com", "one.one.one.one", "dns.google", fake.host(rng)])
    target_ip = fake.ip(rng, v6=six)
    d.line(f" 1?: [LOCALHOST]".ljust(36) + f"pmtu {pmtu}", "row", ["1?", "[LOCALHOST]", f"pmtu {pmtu}"])
    hops = rng.randint(3, 16)
    rtt = rng.uniform(0.2, 2)
    for h in range(1, hops + 1):
        reps = 2 if h == 1 and rng.random() < .7 else 1
        last = h == hops
        for _ in range(reps):
            hop = f"{h:2d}:  "
            if not last and h > 1 and rng.random() < .12:
                d.line(hop + "no reply", "row", [str(h), "no reply"])
                continue
            if h == 1:
                name, ip = rng.choice(["_gateway", "gateway", "router.lan", "fritz.box"]), fake.ip(rng)
            elif last:
                name, ip = target_name, target_ip
            else:
                name, ip = _hostname(rng), fake.ip(rng, v6=six)
            host = f"{name} ({ip})" if both else (ip if rng.random() < .25 else name)
            rtt += rng.uniform(-0.5, 6)
            r = f"{max(rtt, 0.05):.3f}ms"
            cells = [str(h), host, r]
            text = hop + host.ljust(hw) + r.rjust(8) + " "
            if last:
                text += "reached"
                cells.append("reached")
            elif h > 2 and rng.random() < .25:
                note = f"asymm {rng.randint(h - 3, h + 4):2d}"
                text += note + " "
                cells.append(note)
            elif h > 1 and rng.random() < .06:
                pmtu = rng.choice([1480, 1460, 1400])
                text += f"pmtu {pmtu}"
                cells.append(f"pmtu {pmtu}")
            d.line(text, "row", cells)
    back = hops + rng.choice([0, 0, 0, 1, -1, 2])
    d.line(f"     Resume: pmtu {pmtu} hops {hops} back {back} ", "row",
           ["Resume", "pmtu", str(pmtu), "hops", str(hops), "back", str(back)])
    return d
