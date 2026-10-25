"""TDengine `taos` shell: the welcome banner, `taos> query;` prompts, then a
result whose header is centered in type-sized columns, an `=====` rule,
`| `-terminated rows (numbers right-aligned) and `Query OK, N row(s) in set`."""
from lib import Doc, fake

TOOL = "taos"

CITIES = ["California.SanFrancisco", "California.LosAngeles", "California.SanDiego", "California.SanJose",
          "California.PaloAlto", "California.Campbell", "California.MountainView", "California.Sunnyvale"]


def _ts(rng, base, i, step):
    s = base + i * step
    return f"2026-10-{1 + s // 86400 % 28:02d} {s // 3600 % 24:02d}:{s // 60 % 60:02d}:{s % 60:02d}.{rng.choice([0, 0, rng.randint(0, 999)]):03d}"


def _result(d, cols, rows):
    """cols: (name, width, right); a None value prints NULL, "" prints blank."""
    def cell(v, w, right):
        v = v if v is not None else "NULL"
        return " " + (v.rjust(w) if right else v.ljust(w)) + " |"

    d.line("".join(" " + n.center(w) + " |" for n, w, _ in cols), "header", [n for n, _, _ in cols])
    d.skip("=" * sum(w + 3 for _, w, _ in cols))
    for r in rows:
        d.line("".join(cell(v, w, rt) for v, (_, w, rt) in zip(r, cols)), "row",
               [None if v == "" else v if v is not None else "NULL" for v in r])


def generate(rng):
    d = Doc()
    ver = rng.choice(["3.0.4.1", "3.2.1.0", "3.3.2.0", "2.6.0.34"])
    if rng.random() < .5:
        d.skip(f"Welcome to the TDengine Command Line Interface, Client Version:{ver}")
        d.skip("Copyright (c) 2023 by TDengine, all rights reserved.")
        d.blank()
    for k in range(rng.choice([1, 1, 2])):
        q = rng.choice(["meters", "databases", "dnodes", "avg"])
        n = rng.randint(1, 10)
        if q == "meters":
            lim = n
            d.skip(f"taos> select * from {rng.choice(['test.meters', 'meters', 'power.d1001'])} limit {lim};")
            base, step = rng.randint(0, 2000000), rng.choice([1, 10, 60, 900])
            rows = [[_ts(rng, base, i, step), f"{rng.uniform(5, 15):.5f}", str(rng.randint(205, 235)),
                     f"{rng.uniform(.2, .4):.5f}" if rng.random() > .05 else None,
                     rng.choice(CITIES), str(rng.randint(1, 10))] for i in range(n)]
            cols = [("ts", 23, False), ("current", 20, True), ("voltage", 11, True), ("phase", 20, True),
                    ("location", rng.choice([24, 30, 64]), False), ("groupid", 11, True)]
        elif q == "databases":
            d.skip("taos> show databases;")
            names = ["information_schema", "performance_schema"] + rng.sample(["test", "power", "iot", "metrics", "fleet_telemetry", "log"], rng.randint(0, 4))
            if rng.random() < .5:
                cols = [("name", 32, False)]
                rows = [[x] for x in names]
            else:
                cols = [("name", 32, False), ("create_time", 23, False), ("vgroups", 7, True), ("ntables", 20, True),
                        ("replica", 7, True), ("strict", 6, False), ("duration", 10, False), ("keep", 32, False)]
                rows = []
                for x in names:
                    sysdb = x.endswith("_schema")
                    rows.append([x, None if sysdb else fake.date(rng, "datetime") + ".000", None if sysdb else str(rng.choice([2, 4, 8])),
                                 str(rng.randint(0, 100000)), None if sysdb else rng.choice(["1", "3"]),
                                 None if sysdb else rng.choice(["on", "off"]), None if sysdb else rng.choice(["10d", "14400m", "1d"]),
                                 None if sysdb else rng.choice(["3650d,3650d,3650d", "5256000m,5256000m,5256000m", "365d,365d,365d"])])
        elif q == "dnodes":
            d.skip("taos> show dnodes;")
            nd = rng.randint(1, 5)
            cols = [("id", 6, True), ("endpoint", rng.choice([24, 32]), False), ("vnodes", 6, True), ("support_vnodes", 14, True),
                    ("status", 10, False), ("create_time", 23, False), ("reboot_time", 23, False), ("note", 20, False)]
            rows = []
            for i in range(nd):
                st = rng.choice(["ready"] * 6 + ["offline"])
                rows.append([str(i + 1), f"{rng.choice(['td', 'tdengine-', 'h'])}{i + 1}{rng.choice(['', '.internal'])}:6030",
                             str(rng.randint(0, 40)), str(rng.choice([16, 32, 64])), st, fake.date(rng, "datetime") + ".000",
                             fake.date(rng, "datetime") + ".000", "" if st == "ready" else rng.choice(["status msg timeout", "dnode not online"])])
            n = nd
        else:
            interval = rng.choice(["10s", "1m", "15m", "1h"])
            d.skip(f"taos> select _wstart, avg(voltage), max(current) from meters where groupid = {rng.randint(1, 10)} interval({interval});")
            base, step = rng.randint(0, 2000000), {"10s": 10, "1m": 60, "15m": 900, "1h": 3600}[interval]
            rows = [[_ts(rng, base - base % step, i, step)[:-4] + ".000", f"{rng.uniform(205, 235):.9f}", f"{rng.uniform(5, 15):.5f}"]
                    for i in range(n)]
            cols = [("_wstart", 23, False), ("avg(voltage)", 21, True), ("max(current)", 20, True)]
        cols = [(nme, max(w, len(nme)), rt) for nme, w, rt in cols]
        _result(d, cols, rows)
        took = f"{rng.uniform(.0005, .9):.6f}s"
        d.skip(f"Query OK, {len(rows)} row(s) in set ({took})")
        d.blank()
    return d
