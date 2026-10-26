"""`bartib list`: activities grouped under a date heading, each group an
aligned table with a dashed rule under the header (or one ungrouped table
with full timestamps under --no_grouping); a running activity has no Stopped."""
from lib import Doc

TOOL = "bartib-list"

DESC = ["Daily standup", "Write documentation", "Invoice review", "Client call: Globex",
        "Expense reports", "Payroll run", "Prepare quarterly VAT return", "Emails",
        "Code review", "Budget meeting", "Fix import of bank CSV", "Lunch",
        "Draft offer for Initech (phase 2)", "Bookkeeping", "1:1", "Planning"]
PROJ = ["Work", "bartib", "Acme Corp", "Internal", "Admin", "Globex", "Finance", "Sales", "Initech"]


def dur(m):
    return f"{m // 60}h {m % 60}m" if m >= 60 and m % 60 else (f"{m // 60}h" if m >= 60 else f"{m}m")


def hm(m):
    return f"{m // 60:02d}:{m % 60:02d}"


def generate(rng):
    d = Doc()
    group = rng.random() < 0.7
    y, mo, dd = rng.randint(2021, 2026), rng.randint(1, 12), rng.randint(1, 20)
    days = []
    for k in range(rng.randint(1, 4)):
        date = f"{y}-{mo:02d}-{dd + k * rng.randint(1, 2):02d}"
        t = rng.randint(6 * 60, 10 * 60)
        acts = []
        for _ in range(rng.randint(1, 7)):
            ln = rng.randint(5, 200)
            if t + ln >= 24 * 60:
                break
            acts.append([t, t + ln, rng.choice(DESC), rng.choice(PROJ), ln])
            t += ln + rng.choice([0, 0, 5, 15, 30])
        days.append((date, acts))
    if days[-1][1] and rng.random() < 0.3:
        days[-1][1][-1][1] = None  # still running
    hdr = ["Started", "Stopped", "Description", "Project", "Duration"]

    def rows_of(date, acts):
        out = []
        for st, en, desc, proj, ln in acts:
            s = hm(st) if group else f"{date} {hm(st)}"
            e = (hm(en) if group else f"{date} {hm(en)}") if en is not None else None
            out.append([s, e, desc, proj, dur(ln)])
        return out

    if group:
        for i, (date, acts) in enumerate(days):
            if i:
                d.blank()
            d.section(date)
            d.table(hdr, rows_of(date, acts), rule="-")
    else:
        rows = [r for date, acts in days for r in rows_of(date, acts)]
        d.table(hdr, rows, rule="-")
    return d
