"""timetrap `t display`: a `Timesheet:` line, then a table whose Day column is
printed once per day, Start - End pairs, durations, notes; a per-day subtotal
line, a rule, and the sheet total (optionally several sheets and a Grand
Total)."""
from lib import Doc

TOOL = "timetrap-display"

WD = "Mon Tue Wed Thu Fri Sat Sun".split()
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
SHEETS = "default coding client-acme consulting invoicing billable admin sales freelance".split()
NOTES = ["improved display functionality", "working on list", "work on kill", "gem packaging",
         "enhance edit", "call with client", "invoice #1042", "Q3 expense report", "standup",
         "reconcile bank statement", "review contract draft", "email", "proposal for Initech",
         "fix rounding bug in tax calc", "timesheet cleanup", "onboarding new hire"]


def hms(s):
    return f"{s // 3600}:{s % 3600 // 60:02d}:{s % 60:02d}"


def sheet(d, rng, name, ids, next_id):
    entries = []  # (day, start, end, dur, note, id)
    y, mo, dd, wd = rng.randint(2009, 2026), rng.randint(1, 12), rng.randint(1, 20), rng.randint(0, 6)
    for _ in range(rng.randint(1, 4)):
        day = f"{WD[wd]} {MON[mo - 1]} {dd:02d}, {y}"
        t = rng.randint(0, 12 * 3600)
        for k in range(rng.randint(1, 5)):
            t += rng.randint(60, 3 * 3600)
            ln = rng.randint(3, 3 * 3600)
            if t + ln >= 86400:
                break
            note = rng.choice(NOTES) if rng.random() < 0.75 else None
            entries.append((day if k == 0 else None, hms(t).rjust(8, "0"), hms(t + ln).rjust(8, "0"), ln, note, str(next_id)))
            next_id += rng.randint(1, 3)
            t += ln
        step = rng.randint(1, 3)
        dd, wd = dd + step, (wd + step) % 7
    d.kv("Timesheet", name)
    idw = max([2] + [len(e[5]) for e in entries]) if ids else 0
    pre = "    " + ("Id".ljust(idw) + "  " if ids else "")
    hdr = (["Id"] if ids else []) + ["Day", "Start", "End", "Duration", "Notes"]
    d.line(pre + "Day                Start      End        Duration   Notes", "header", hdr)
    total = 0
    sub = 0
    for i, (day, st, en, ln, note, eid) in enumerate(entries):
        dur = hms(ln)
        text = "    " + ((eid.ljust(idw) + "  ") if ids else "") + (day or "").ljust(19) + st + " - " + en + "   " + dur.ljust(11) + (note or "")
        d.line(text.rstrip(), "row", ([eid] if ids else []) + [day, st, en, dur, note])
        sub += ln
        total += ln
        if i == len(entries) - 1 or entries[i + 1][0]:
            d.line(pre + " " * 41 + hms(sub), "row", ([None] if ids else []) + [None, None, None, hms(sub), None])
            sub = 0
    d.skip(pre + "-" * 59)
    d.line(pre + "Total".ljust(41) + hms(total), "row", ([None] if ids else []) + ["Total", None, None, hms(total), None])
    return total, next_id


def generate(rng):
    d = Doc()
    ids = rng.random() < 0.3
    nid = rng.randint(1, 900)
    names = rng.sample(SHEETS, rng.choice([1, 1, 1, 2, 3]))
    grand = 0
    for i, n in enumerate(names):
        if i:
            d.blank()
        t, nid = sheet(d, rng, n, ids, nid)
        grand += t
    if len(names) > 1:
        d.skip("-" * 63)
        d.line("Grand Total".ljust(45 + (4 if ids else 0)) + hms(grand), "kv", ["Grand Total", hms(grand)])
    return d
