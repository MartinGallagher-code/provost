"""Aerospike `asadm -e "info network|namespace usage|set"`: the shell
preamble (Seed / Config_file / Online), a `~~~Title (timestamp)~~~` banner,
a `|`-separated table (two header lines when columns are grouped) and a
`Number of rows: N` footer."""
from lib import Doc, fake

TOOL = "asadm-info"


def _num(rng, unit=True):
    v = rng.uniform(0, 999)
    return f"{v:.3f}" + (rng.choice([" K", " M", ""]) if unit else "")


def _pct(rng):
    return f"{rng.uniform(0, 90):.2f} %"


def _sz(rng):
    return f"{rng.uniform(1, 999):.3f} {rng.choice(['KB', 'MB', 'GB', 'TB'])}"


def _render(d, groups, header, rows, right):
    """groups: None, or list of (title, span) over the header columns."""
    w = [max(len(header[c]), *(len(r[c] or "") for r in rows)) for c in range(len(header))]
    if groups:
        # widen grouped spans so the group title fits
        c = 0
        for title, span in groups:
            have = sum(w[c:c + span]) + span - 1
            if span == 1:
                w[c] = max(w[c], len(title))
            elif len(title) + 4 > have:
                w[c + span - 1] += len(title) + 4 - have
            c += span

    def fmt(vals, align_right):
        return "|".join((v or "").rjust(w[c]) if align_right(c) else (v or "").ljust(w[c]) for c, v in enumerate(vals))

    if groups:
        parts, cells, c = [], [], 0
        for title, span in groups:
            width = sum(w[c:c + span]) + span - 1
            if span == 1:
                parts.append(title.rjust(width))
            else:
                parts.append(title.center(width, "~"))
            cells.append(title)
            c += span
        d.line("|".join(parts), "header", cells)
        tops = [t for t, s in groups for _ in range(s)]
        sub = [h if h != tops[c] else None for c, h in enumerate(header)]
        d.line(fmt([h or "" for h in sub], lambda c: True).rstrip(), "header", sub)
    else:
        d.line(fmt(header, lambda c: True), "header", header)
    for r in rows:
        d.line(fmt(r, lambda c: c in right).rstrip(), "row", [v if v else None for v in r])
    return len(rows)


def generate(rng):
    d = Doc()
    n = rng.randint(1, 7)
    ips = [fake.ip(rng) for _ in range(n)]
    nodes = [f"{rng.choice(['aero', 'as', 'aerospike-'])}{i + 1}.{rng.choice(['internal', 'prod.local'])}:3000"
             if rng.random() < .7 else f"{ip}:3000" for i, ip in enumerate(ips)]
    ver = rng.choice(["2.14.0", "2.18.0", "2.21.0", "3.1.0"])
    if rng.random() < .6:
        d.kv("Seed", f"[('{ips[0]}', 3000, None)]", sep=":        ")
        d.kv("Config_file", "/root/.aerospike/astools.conf, /etc/aerospike/astools.conf", sep=": ")
        d.skip(f"Aerospike Interactive Shell, version {ver}")
        d.blank()
        d.skip(f"Found {n} nodes")
        d.kv("Online", ", ".join(f"{ip}:3000" for ip in ips), sep=":  ")
        d.blank()
    what = rng.choice(["network", "network", "namespace usage", "set"])
    stamp = f"{fake.date(rng, 'datetime')} UTC"
    title = {"network": "Network Information", "namespace usage": "Namespace Usage Information", "set": "Set Information"}[what]
    if rng.random() < .5:
        d.skip(f"Admin> info {what}")
    tw = rng.choice([110, 130, 150])
    banner = f"{title} ({stamp})"
    left = (tw - len(banner)) // 2
    d.section("~" * left + banner + "~" * (tw - left - len(banner)), banner)
    ns = rng.sample(["test", "bar", "users", "sessions", "cache", "profiles", "events"], rng.randint(1, 3))
    if what == "network":
        header = ["Node", "Node ID", "IP", "Build", "Migrations", "Size", "Key", "Integrity", "Principal", "Conns", "Uptime"]
        groups = [("Node", 1), ("Node ID", 1), ("IP", 1), ("Build", 1), ("Migrations", 1), ("Cluster", 4), ("Client", 1), ("Uptime", 1)]
        key = fake.hexid(rng, 12).upper()
        ids = [fake.hexid(rng, 15).upper() for _ in nodes]
        princ = max(ids)
        build = f"E-{rng.choice(['6.3.0.5', '6.4.0.2', '7.0.0.3', '5.7.0.17'])}"
        rows = [[nd, ("*" if i == princ else "") + i, f"{ip}:3000", build, _num(rng, False) if rng.random() < .2 else "0.000",
                 str(n), key, "True", princ, str(rng.randint(2, 900)),
                 f"{rng.randint(0, 900):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"]
                for nd, i, ip in zip(nodes, ids, ips)]
        count = _render(d, groups, header, rows, right={4, 5, 9, 10})
    elif what == "namespace usage":
        header = ["Namespace", "Node", "Total Records", "Expirations", "Evictions", "Stop Writes", "Used", "Used%", "HWM%", "Avail%"]
        groups = [("Namespace", 1), ("Node", 1), ("Total Records", 1), ("Expirations", 1), ("Evictions", 1),
                  ("Stop Writes", 1), ("Device", 4)]
        rows = []
        for s in ns:
            for nd in nodes:
                rows.append([s, nd, _num(rng), _num(rng), _num(rng) if rng.random() < .3 else "0.000",
                             rng.choice(["False"] * 9 + ["True"]), _sz(rng), _pct(rng), "50 %", f"{rng.randint(5, 99)} %"])
            if rng.random() < .7:
                rows.append([s, "", _num(rng), _num(rng), "0.000", "", _sz(rng), "", "", ""])
        count = _render(d, groups, header, rows, right={2, 3, 4, 6, 7, 8, 9})
    else:
        header = ["Namespace", "Set", "Node", "Set ID", "Objects", "Stop Writes Count", "Disable Eviction", "Set Delete", "Memory Used"]
        rows = []
        for s in ns:
            for st in rng.sample(["demo", "users", "orders", "tokens", "session_v2", "audit"], rng.randint(1, 2)):
                sid = str(rng.randint(1, 12))
                for nd in nodes:
                    rows.append([s, st, nd, sid, _num(rng), "0", rng.choice(["false", "false", "true"]), "false", _sz(rng)])
        count = _render(d, None, header, rows, right={3, 4, 5, 8})
    d.skip(f"Number of rows: {count}")
    return d
