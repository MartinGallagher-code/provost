"""FreeBSD/macOS `ipfw show` (or `ipfw -a list`): headerless rule lines of
rule number, packet and byte counters (zero-padded rule number), optional
timestamp with -t, then the rule body."""
from lib import Doc, fake

TOOL = "ipfw-show"


def _body(rng):
    a, b = fake.ip(rng), fake.ip(rng)
    ifc = rng.choice(["em0", "lo0", "vtnet0", "igb1", "tun0", "bridge0"])
    return rng.choice([
        "allow ip from any to any via lo0",
        "deny ip from any to 127.0.0.0/8",
        "deny ip from 127.0.0.0/8 to any",
        f"allow tcp from any to me {fake.port(rng)} setup keep-state :default",
        f"allow tcp from {a}/24 to me dst-port 22 in via {ifc}",
        f"deny log logamount 100 ip from any to {b}",
        "check-state :default",
        "allow tcp from any to any established",
        f"allow udp from me to any dst-port 53 keep-state :default",
        f"nat 1 ip from any to any via {ifc}",
        f"pipe {rng.randint(1, 9)} ip from {a} to any out",
        f"queue {rng.randint(1, 9)} tcp from any {fake.port(rng)} to any",
        f"fwd {b},{fake.port(rng)} tcp from {a} to any 80",
        "allow icmp from any to any icmptypes 0,3,8,11",
        f"reject tcp from table(bruteforce) to any",
        f"skipto {rng.randint(1, 9) * 1000} ip from any to any in recv {ifc}",
        "deny ip from any to any",
        "allow ip6 from any to any proto ipv6-icmp",
        f"count ip from any to any MAC {fake.mac(rng)} any",
    ])


def generate(rng):
    d = Doc()
    stamped = rng.random() < .3
    epoch = rng.random() < .3
    pk_w, by_w = rng.choice([(9, 10), (8, 9), (11, 13), (5, 6)])
    n = rng.randint(3, 22)
    nums = sorted(rng.sample(range(1, 650), n - 1))
    rules = [f"{x * 100:05d}" for x in nums] + ["65535"]
    data = []
    for num in rules:
        pk = rng.choice([0, 0, rng.randint(0, 10 ** 4), rng.randint(0, 10 ** pk_w - 1)])
        by = pk * rng.randint(40, 1500)
        body = "deny ip from any to any" if num == "65535" and rng.random() < .7 else \
            ("allow ip from any to any" if num == "65535" else _body(rng))
        data.append((num, pk, by, body))
    # ipfw sizes the counter columns to the widest value
    pk_w = max(len(str(x[1])) for x in data) + rng.choice([0, 1, 2])
    by_w = max(len(str(x[2])) for x in data) + rng.choice([0, 1, 2])
    for num, pk, by, body in data:
        cells = [num, str(pk), str(by)]
        text = f"{num} {str(pk).rjust(pk_w)} {str(by).rjust(by_w)} "
        if stamped:
            if pk:
                ts = str(rng.randint(1500000000, 1790000000)) if epoch else \
                    fake.date(rng, "rfc")[:3] + " " + fake.date(rng, "syslog") + f" {rng.randint(2019, 2026)}"
                text += ts + " "
                cells.append(ts)
        text += body
        cells.append(body)
        d.line(text, "row", cells)
    return d
