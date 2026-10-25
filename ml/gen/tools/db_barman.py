"""`barman list-backup <server|all>`: one fixed-layout line per backup,
`server id - date - Size: x - WAL Size: y` plus an optional trailing status,
and short `- FAILED` / `- STARTED` lines."""
from lib import Doc, fake

TOOL = "barman-list-backup"

DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def _size(rng, lo, hi):
    v = rng.uniform(lo, hi)
    for u in ("B", "KiB", "MiB", "GiB", "TiB"):
        if v < 1024:
            return f"{v:.1f} {u}" if u != "B" else f"{int(v)} B"
        v /= 1024
    return f"{v:.1f} PiB"


def generate(rng):
    d = Doc()
    servers = rng.sample(["pg-main", "pg-replica", "main", "billing-db", "pg15", "analytics", "pgsql-prod-01"],
                         rng.choice([1, 1, 2, 3]))
    for srv in servers:
        n = rng.randint(1, 9)
        y, m, day = rng.randint(2022, 2026), rng.randint(1, 12), rng.randint(10, 28)
        base = rng.uniform(1e7, 4e12)
        for i in range(n):
            dd = day - i
            hh, mi, ss = rng.choice([0, 1, 2, 3, 22]), rng.randint(0, 59), rng.randint(0, 59)
            bid = f"{y}{m:02d}{dd:02d}T{hh:02d}{mi:02d}{ss:02d}"
            prefix = f"{srv} {bid}"
            cells = [srv, bid]
            if rng.random() < .25:
                name = rng.choice(["'nightly'", "'pre-upgrade'", "'weekly-full'", "'before-migration-42'"])
                prefix += f" {name}"
                cells.append(name)
            else:
                cells.append(None)
            if i == 0 and rng.random() < .15:
                st = rng.choice(["FAILED", "STARTED", "WAITING_FOR_WALS"])
                if st != "WAITING_FOR_WALS":
                    d.line(f"{prefix} - {st}", "row", cells + [st, None, None, None, None, None])
                    continue
            date = f"{DAYS[(dd + m) % 7]} {MONS[m - 1]} {dd:2d} {(hh + 1) % 24:02d}:{mi:02d}:{ss:02d} {y}"
            size, wal = _size(rng, base * .8, base * 1.2), _size(rng, 0, base / 20) if i or rng.random() < .7 else "0 B"
            text = f"{prefix} - {date} - Size: {size} - WAL Size: {wal}"
            tail = None
            r = rng.random()
            if i == 0 and wal == "0 B":
                tail = "WAITING_FOR_WALS"
            elif r < .12:
                tail = rng.choice(["OBSOLETE", "KEEP:FULL", "KEEP:STANDALONE"])
            elif r < .2:
                tail = f"(tablespaces: {rng.choice(['tbs1', 'fast_ssd', 'archive'])}:/data/{fake.word(rng)}/tbs)"
            if tail:
                text += f" - {tail}" if not tail.startswith("(") else f" {tail}"
            d.line(text, "row", cells + [date, "Size", size, "WAL Size", wal, tail])
    return d
