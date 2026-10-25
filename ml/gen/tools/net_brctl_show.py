"""Linux bridge-utils `brctl show`: tab-separated table; a bridge with more
than one port prints each extra port alone on its own line (a continuation)."""
from lib import Doc, fake

TOOL = "brctl-show"


def _tabs(s, stops):
    """Pad s with tabs to reach tab stop `stops` (in 8-column units)."""
    n = max(1, stops - len(s) // 8)
    return s + "\t" * n


def _ports(rng, br):
    kinds = [lambda: f"eth{rng.randint(0, 3)}", lambda: f"enp{rng.randint(0, 9)}s{rng.randint(0, 31)}",
             lambda: f"veth{fake.hexid(rng, 7)}", lambda: f"vnet{rng.randint(0, 40)}",
             lambda: f"tap{rng.randint(0, 9)}", lambda: f"{br}-nic", lambda: f"bond{rng.randint(0, 2)}.{rng.randint(2, 4000)}"]
    n = rng.choice([0, 1, 1, 1, 2, 3, 5])
    return list(dict.fromkeys(rng.choice(kinds)() for _ in range(n)))


def generate(rng):
    d = Doc()
    d.line("bridge name\tbridge id\t\tSTP enabled\tinterfaces", "header",
           ["bridge name", "bridge id", "STP enabled", "interfaces"])
    names = ["br0", "br1", "docker0", "virbr0", "virbr1", "lxcbr0", "br-lan", "vmbr0", "vmbr1",
             f"br-{fake.hexid(rng, 12)}", "brvlan" + str(rng.randint(2, 999)), "cni0", "kube-bridge"]
    for br in rng.sample(names, rng.randint(1, 6)):
        bid = f"{rng.choice(['8000', '8000', '8000', '1000', '7000'])}.{fake.mac(rng).replace(':', '')}"
        stp = rng.choice(["no", "no", "yes"])
        ports = _ports(rng, br)
        text = _tabs(br, 2) + bid + "\t" + stp + "\t\t" + (ports[0] if ports else "")
        d.line(text, "row", [br, bid, stp, ports[0] if ports else None])
        for p in ports[1:]:
            d.line("\t" * 7 + p, "cont", [p])
    return d
