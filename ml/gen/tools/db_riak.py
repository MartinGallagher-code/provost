"""`riak-admin member-status`: a `=== Membership ===` banner, a fixed-width
table framed by dash rules, and a `Valid:3 / Leaving:0 / ...` tally."""
from lib import Doc, fake

TOOL = "riak-admin-member-status"


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        d.skip("Attempting to restart script through sudo -H -u riak")
    n = rng.randint(1, 12)
    nodes = []
    style = rng.choice(["ip", "host", "dev"])
    for i in range(n):
        if style == "ip":
            nodes.append(f"'riak@{fake.ip(rng)}'")
        elif style == "host":
            nodes.append(f"'riak@riak{i + 1:02d}.{rng.choice(['prod.example.com', 'internal', 'dc1.lan'])}'")
        else:
            nodes.append(f"'dev{i + 1}@127.0.0.1'")
    status = [rng.choice(["valid"] * 10 + ["leaving", "joining", "exiting", "down"]) for _ in nodes]
    share = [rng.uniform(.5, 1.5) if s in ("valid", "leaving", "down") else 0 for s in status]
    tot = sum(share) or 1
    ring = [100 * x / tot for x in share]
    changing = rng.random() < .3
    w = 79 if rng.random() < .8 else rng.choice([72, 80])
    title = " Membership "
    left = (w - len(title)) // 2
    d.section("=" * left + title + "=" * (w - left - len(title)), "Membership")
    d.line("Status     Ring    Pending    Node", "header", ["Status", "Ring", "Pending", "Node"])
    d.skip("-" * w)
    for s, r, nd in zip(status, ring, nodes):
        pend = "--" if not changing else f"{rng.uniform(0, 40):.1f}%" if s != "leaving" else "  0.0%"
        text = f"{s:<10}{r:5.1f}%{pend:>8}      {nd}"
        d.line(text, "row", [s, f"{r:.1f}%", pend.strip(), nd])
    d.skip("-" * w)
    counts = [(k.capitalize(), status.count(k)) for k in ("valid", "leaving", "exiting", "joining", "down")]
    d.skip(" / ".join(f"{k}:{v}" for k, v in counts))
    return d
