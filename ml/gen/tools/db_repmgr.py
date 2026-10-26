"""`repmgr cluster show` (and `--compact`): a borderless pipe table of the
replication cluster, optionally followed by WARNING/HINT prose."""
from lib import Doc, fake

TOOL = "repmgr-cluster-show"


def generate(rng):
    d = Doc()
    compact = rng.random() < .3
    n = rng.randint(2, 7)
    stem = rng.choice(["node", "pg", "db", "pgsql-", "postgres-prod-"])
    names = [f"{stem}{i + 1}" for i in range(n)]
    loc = rng.choice([["default"], ["dc1", "dc2"], ["eu-west-1a", "eu-west-1b", "eu-west-1c"]])
    primary = 0 if rng.random() < .8 else rng.randrange(n)
    tl = str(rng.randint(1, 14))
    issues = []
    rows = []
    for i, nm in enumerate(names):
        if i == primary:
            role, status, up = "primary", "* running", ""
        elif rng.random() < .15:
            role, status, up = "witness", "* running", names[primary]
        else:
            role, up = "standby", names[primary] if rng.random() < .85 else rng.choice([x for x in names if x != nm])
            status = rng.choice(["running"] * 8 + ["- failed", "? unreachable", "! running as primary"])
            if status != "running":
                issues.append((i, status))
        prio = rng.choice(["100", "100", "50", "0", "10"])
        host = nm if rng.random() < .6 else fake.ip(rng)
        conn = f"host={host} dbname=repmgr user=repmgr" + (" connect_timeout=2" if rng.random() < .6 else "") + (
            f" port={rng.choice([5432, 5433, 6432])}" if rng.random() < .3 else "")
        line_tl = tl if status != "- failed" else rng.choice(["?", str(max(1, int(tl) - 1))])
        rows.append([str(i + 1), nm, role, status, up, rng.choice(loc), prio, line_tl if role != "witness" else "n/a", conn])
    header = ["ID", "Name", "Role", "Status", "Upstream", "Location", "Priority", "Timeline", "Connection string"]
    if compact:
        header = ["ID", "Name", "Role", "Status", "Upstream", "Location", "Prio.", "TLI"]
        rows = [r[:8] for r in rows]
    w = [max(len(header[c]), *(len(r[c]) + 2 * (c == 3 and r[c] == "running") for r in rows)) for c in range(len(header))]

    def fmt(vals):
        return "|".join(" " + v.ljust(w[c]) + " " for c, v in enumerate(vals)).rstrip()

    d.line(fmt(header), "header", header)
    d.skip("+".join("-" * (x + 2) for x in w))
    for r in rows:
        shown = list(r)
        if r[3] == "running":
            shown[3] = "  running"   # the status flag column stays aligned
        d.line(fmt(shown), "row", [v if v else None for v in r])
    if issues:
        d.blank()
        d.skip("WARNING: following issues were detected")
        for i, st in issues:
            if st == "- failed":
                d.skip(f'  - unable to connect to node "{names[i]}" (ID: {i + 1})')
            elif st == "? unreachable":
                d.skip(f'  - node "{names[i]}" (ID: {i + 1}) is registered as standby but unreachable')
            else:
                d.skip(f'  - node "{names[i]}" (ID: {i + 1}) is registered as standby but running as primary')
        d.blank()
        d.skip("HINT: execute with --verbose option to see connection error messages")
    return d
