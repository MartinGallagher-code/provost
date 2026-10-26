"""Oracle `sqlplus`: the login banner (unless -s), then a query result with
column widths from the declared types, NUMBER columns right-aligned (header
too), the header repeated every PAGESIZE rows, and `N rows selected.`"""
from lib import Doc, fake

TOOL = "sqlplus"

MON = "JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split()


def _odate(rng):
    return f"{rng.randint(1, 28):02d}-{rng.choice(MON)}-{rng.randint(15, 26):02d}"


def _tablespaces(rng):
    names = ["SYSTEM", "SYSAUX", "UNDOTBS1", "TEMP", "USERS"] + rng.sample(
        ["APP_DATA", "APP_INDEX", "LOB_DATA", "AUDIT_TBS", "HIST_2023", "STAGING", "UNDOTBS2", "TEMP_BIG"], rng.randint(0, 6))
    rows = []
    for n in names:
        tot = rng.randint(100, 900000)
        used = int(tot * rng.uniform(.01, .99))
        rows.append([n, rng.choice(["ONLINE"] * 8 + ["OFFLINE", "READ ONLY"]),
                     "TEMPORARY" if n.startswith("TEMP") else "UNDO" if n.startswith("UNDO") else "PERMANENT",
                     str(tot), str(used), f"{100 * used / tot:.2f}"])
    return (["TABLESPACE_NAME", "STATUS", "CONTENTS", "TOTAL_MB", "USED_MB", "PCT_USED"],
            [30, 9, 21, 10, 10, 10], {3, 4, 5}, rows)


def _sessions(rng):
    rows = []
    for _ in range(rng.randint(3, 22)):
        bg = rng.random() < .35
        rows.append([str(rng.randint(1, 1500)), str(rng.randint(1, 65000)),
                     "" if bg else rng.choice(["SYS", "SYSTEM", "APP_OWNER", "HR", "SCOTT", "BATCH_USER", "DBSNMP"]),
                     rng.choice(["ACTIVE", "INACTIVE"]) if not bg else "ACTIVE",
                     rng.choice(["dbhost01", "app-srv-02.example.com", "WORKGROUP\\PC-1123", "batch01"]),
                     (rng.choice(["oracle@dbhost01 (PMON)", "oracle@dbhost01 (DBW0)", "oracle@dbhost01 (LGWR)", "oracle@dbhost01 (CKPT)"])
                      if bg else rng.choice(["sqlplus@app-srv-02 (TNS V1-V3)", "JDBC Thin Client", "SQL Developer", "python3.11@batch01 (TNS V1-V3)", ""]))])
    return (["SID", "SERIAL#", "USERNAME", "STATUS", "MACHINE", "PROGRAM"],
            [10, 10, 30, 8, rng.choice([64, 30]), rng.choice([48, 30])], {0, 1}, rows)


def _users(rng):
    rows = []
    for u in rng.sample(["SYS", "SYSTEM", "OUTLN", "DBSNMP", "APP_OWNER", "APP_RO", "HR", "SCOTT", "BATCH_USER",
                         "AUDSYS", "GSMADMIN_INTERNAL", "XDB", "ANONYMOUS", "REPORTING"], rng.randint(3, 14)):
        rows.append([u, rng.choice(["OPEN", "OPEN", "LOCKED", "EXPIRED & LOCKED", "EXPIRED(GRACE)"]),
                     rng.choice(["SYSTEM", "SYSAUX", "USERS", "APP_DATA"]), _odate(rng),
                     rng.choice(["", "", _odate(rng)])])
    return (["USERNAME", "ACCOUNT_STATUS", "DEFAULT_TABLESPACE", "CREATED", "EXPIRY_DA"],
            [30, 32, 30, 9, 9], set(), rows)


def generate(rng):
    d = Doc()
    silent = rng.random() < .4
    rel = rng.choice(["19.0.0.0.0", "21.0.0.0.0", "23.0.0.0.0"])
    if not silent:
        d.blank()
        d.skip(f"SQL*Plus: Release {rel} - Production on {fake.date(rng, 'rfc')[:3]} Oct {rng.randint(1, 28)} "
               f"{fake.date(rng, 'time')} 2026")
        d.skip(f"Version {rel[:3]}{rng.randint(3, 22)}.0.0.0")
        d.blank()
        d.skip("Copyright (c) 1982, 2023, Oracle.  All rights reserved.")
        d.blank()
        if rng.random() < .5:
            d.skip(f"Last Successful login time: Wed Oct 22 2026 {fake.date(rng, 'time')} +00:00")
            d.blank()
        d.skip("Connected to:")
        d.skip(f"Oracle Database {rel[:2]}c Enterprise Edition Release {rel} - Production")
        d.skip(f"Version {rel[:3]}{rng.randint(3, 22)}.0.0.0")
        d.blank()
    header, widths, right, rows = rng.choice([_tablespaces, _sessions, _users])(rng)
    widths = [max(w, len(h)) for w, h in zip(widths, header)]
    widths = [max(w, *(len(r[c]) for r in rows)) for c, w in enumerate(widths)]
    shown = [h[:w] for h, w in zip(header, widths)]

    def fmt(vals):
        return " ".join((v or "").rjust(widths[c]) if c in right else (v or "").ljust(widths[c])
                        for c, v in enumerate(vals)).rstrip()

    pagesize = rng.choice([14, 14, 50, 100])
    for i, r in enumerate(rows):
        if i % (pagesize - 3) == 0:
            if i:
                d.blank()
            d.line(fmt(shown), "header", shown)
            d.skip(" ".join("-" * w for w in widths))
        d.line(fmt(r), "row", [v if v else None for v in r])
    if len(rows) >= 6:
        d.blank()
        d.skip(f"{len(rows)} rows selected.")
    if not silent:
        d.blank()
        d.skip(f"Disconnected from Oracle Database {rel[:2]}c Enterprise Edition Release {rel} - Production")
    return d
