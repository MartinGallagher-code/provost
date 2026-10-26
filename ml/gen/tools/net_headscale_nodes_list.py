"""headscale `headscale nodes list`: a pterm table with ` | ` column
separators and no outer border or rule; IP addresses are one comma-joined
value, keys are bracketed short prefixes."""
from lib import Doc, fake

TOOL = "headscale-nodes-list"


def _ts(rng):
    return fake.date(rng, "datetime")


def generate(rng):
    d = Doc()
    tags = rng.random() < .4
    header = ["ID", "Hostname", "Name", "MachineKey", "NodeKey", "User", "IP addresses", "Ephemeral",
              "Last seen", "Expiration", "Connected", "Expired"]
    if tags:
        header += ["ForcedTags", "InvalidTags", "ValidTags"]
    rows = []
    for i in range(1, rng.randint(1, 14) + 1):
        host = rng.choice([fake.host(rng).split(".")[0], f"{fake.user(rng)}-laptop", f"{fake.user(rng)}s-MacBook-Pro",
                           "localhost", f"pixel-{rng.randint(5, 9)}", f"k8s-node-{rng.randint(1, 9)}", "raspberrypi"])
        name = host.lower() if rng.random() < .8 else f"{host.lower()}-{fake.token(rng, 5)}"
        v4 = f"100.64.0.{rng.randint(1, 254)}"
        v6 = f"fd7a:115c:a1e0::{rng.randint(1, 255):x}"
        ips = rng.choice([f"{v4}, {v6}", f"{v4}, {v6}", v4])
        online = rng.random() < .55
        exp = rng.choice(["0001-01-01 00:00:00", "N/A", _ts(rng)])
        row = [str(i), host, name, f"[{fake.token(rng, 5)}]", f"[{fake.token(rng, 5)}]",
               rng.choice(["alice", "bob", "default", "ops", "carol", "homelab"]), ips,
               rng.choice(["false", "false", "false", "true"]), _ts(rng) if rng.random() < .95 else "",
               exp, "online" if online else "offline", rng.choice(["no", "no", "no", "yes"])]
        if tags:
            ft = rng.choice(["", "", "tag:server", "tag:prod,tag:web"])
            row += [ft, "", rng.choice(["", "", "tag:ci"])]
        rows.append(row)
    ncol = len(header)
    width = [max(len(str(x)) for x in [header[c]] + [r[c] for r in rows]) for c in range(ncol)]

    def render(cells):
        return " | ".join(cells[c].ljust(width[c]) for c in range(ncol)).rstrip()

    d.line(render(header), "header", header)
    for r in rows:
        d.line(render(r), "row", [v if v else None for v in r])
    return d
