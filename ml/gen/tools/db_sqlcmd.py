"""SQL Server `sqlcmd -Q ...`: fixed-width result sets (column width from the
declared type, numbers right-aligned), a dash rule per column, then
`(N rows affected)`."""
from lib import Doc, fake

TOOL = "sqlcmd"

DBS = "master tempdb model msdb SalesDB Inventory HR_Prod ReportServer ReportServerTempDB AdventureWorks2019 WideWorldImporters Staging".split()


def _render(d, header, widths, right, rows):
    def fmt(vals):
        out = []
        for c, v in enumerate(vals):
            v = v if v is not None else ""
            out.append(v.rjust(widths[c]) if c in right else v.ljust(widths[c]))
        return " ".join(out).rstrip()
    d.line(fmt(header), "header", header)
    d.skip(" ".join("-" * w for w in widths))
    for r in rows:
        d.line(fmt(r), "row", [v if v not in ("", None) else None for v in r])


def _databases(rng):
    n = rng.randint(4, 11)
    names = (DBS[:4] + rng.sample(DBS[4:], min(n - 4, len(DBS) - 4)))[:n]
    header = ["name", "database_id", "create_date", "state_desc", "recovery_model_desc", "compatibility_level"]
    keep = [0, 1] + sorted(rng.sample([2, 3, 4, 5], rng.randint(1, 4)))
    rows = []
    for i, nm in enumerate(names):
        full = [nm, str(i + 1), fake.date(rng, "datetime") + f".{rng.randint(0, 999):03d}",
                rng.choice(["ONLINE"] * 6 + ["OFFLINE", "RESTORING", "RECOVERY_PENDING"]),
                rng.choice(["SIMPLE", "FULL", "BULK_LOGGED"]), rng.choice(["100", "130", "140", "150", "160"])]
        rows.append([full[k] for k in keep])
    widths_full = [rng.choice([128, 30, 40, 64]), 11, 23, rng.choice([60, 30]), rng.choice([60, 30]), 19]
    return [header[k] for k in keep], [widths_full[k] for k in keep], {keep.index(k) for k in (1, 5) if k in keep}, rows


def _who(rng):
    header = ["spid", "ecid", "status", "loginame", "hostname", "blk", "dbname", "cmd", "request_id"]
    rows = []
    for _ in range(rng.randint(3, 14)):
        sys_ = rng.random() < .4
        rows.append([str(rng.randint(1, 50) if sys_ else rng.randint(51, 400)), "0",
                     rng.choice(["background", "sleeping"]) if sys_ else rng.choice(["sleeping", "runnable", "suspended", "sleeping"]),
                     "sa" if sys_ else rng.choice(["sa", "app_user", "CORP\\svc_sql", "reporting", "NT AUTHORITY\\SYSTEM"]),
                     "" if sys_ else rng.choice(["WEB-01", "APP-SRV-02", "localhost", "BI-NODE3"]),
                     "0" if rng.random() < .9 else str(rng.randint(51, 99)),
                     rng.choice(DBS) if not sys_ or rng.random() < .3 else "NULL",
                     rng.choice(["AWAITING COMMAND", "SELECT", "INSERT", "LOG WRITER", "CHECKPOINT", "TASK MANAGER", "LAZY WRITER"]),
                     "0"])
    widths = [5, 5, 30, 128 if rng.random() < .3 else 30, 128 if rng.random() < .3 else 20, 5, 128 if rng.random() < .3 else 20, 16, 10]
    return header, widths, {0, 1, 5, 8}, rows


def _sizes(rng):
    header = ["DatabaseName", "FileName", "type_desc", "SizeMB", "UsedMB", "FreePct"]
    rows = []
    for _ in range(rng.randint(2, 10)):
        db = rng.choice(DBS)
        kind = rng.choice(["ROWS", "LOG"])
        size = rng.uniform(8, 250000)
        used = size * rng.uniform(.05, .99)
        rows.append([db, db + ("_log" if kind == "LOG" else rng.choice(["", "_data", "_2"])), kind,
                     f"{size:.2f}", f"{used:.2f}", f"{100 * (1 - used / size):.1f}"])
    return header, [rng.choice([128, 40]), rng.choice([128, 60]), 60, 20, 20, 20], {3, 4, 5}, rows


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        d.skip(f"Changed database context to '{rng.choice(DBS)}'.")
    for k in range(rng.choice([1, 1, 1, 2])):
        if k:
            d.blank()
        header, widths, right, rows = rng.choice([_databases, _who, _sizes])(rng)
        widths = [max(w, len(h), *(len(r[c] or "") for r in rows)) for c, (w, h) in enumerate(zip(widths, header))]
        if rng.random() < .5:   # narrow declared types: columns only as wide as their values
            widths = [max(len(h), *(len(r[c] or "") for r in rows)) for c, h in enumerate(header)]
        _render(d, header, widths, right, rows)
        d.blank()
        d.skip(f"({len(rows)} rows affected)")
    return d
