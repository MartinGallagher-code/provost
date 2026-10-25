"""`klog report`: one line per day; year and month are printed only when they
change, totals right-aligned, optional Should/Diff columns (--diff), then a
`====` rule and the grand total."""
from lib import Doc

TOOL = "klog-report"

MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
WD = "Mon Tue Wed Thu Fri Sat Sun".split()


def hm(mins, sign=False):
    s = "-" if mins < 0 else ("+" if sign else "")
    mins = abs(mins)
    h, m = mins // 60, mins % 60
    if h and m:
        body = f"{h}h{m}m"
    elif h:
        body = f"{h}h"
    else:
        body = f"{m}m"
    return s + body


def generate(rng):
    d = Doc()
    diff = rng.random() < 0.4
    year, month = rng.randint(2019, 2026), rng.randint(1, 12)
    day, wd = rng.randint(1, 5), rng.randint(0, 6)
    rows = []
    last_y = last_m = None
    tot = should_tot = 0
    for _ in range(rng.randint(3, 16)):
        mins = rng.choice([rng.randint(0, 11) * 60, rng.randint(1, 600), rng.randint(6, 9) * 60 + rng.choice([0, 15, 30, 45])])
        if rng.random() < 0.05:
            mins = -rng.randint(1, 3) * 60
        should = 0 if wd >= 5 else rng.choice([8 * 60, 8 * 60, 7 * 60 + 30, 6 * 60])
        tot += mins
        should_tot += should
        y = str(year) if year != last_y else None
        m = MON[month - 1] if (month, year) != last_m else None
        last_y, last_m = year, (month, year)
        r = [y, m, f"{WD[wd]} {day:02d}.", hm(mins)]
        if diff:
            r += [hm(should), hm(mins - should, sign=True)]
        rows.append(r)
        step = rng.choice([1, 1, 1, 2, 3])
        day += step
        wd = (wd + step) % 7
        if day > 28:
            day -= 28
            month += 1
            if month > 12:
                month, year = 1, year + 1
    ncol = len(rows[0])
    w = [4, 3, 7] + [max([len(r[c]) for r in rows] + [len(hm(tot, False)), 5 if c == 3 else 6] +
                         ([len(hm(should_tot))] if c == 4 else []) +
                         ([len(hm(tot - should_tot, True))] if c == 5 else [])) for c in range(3, ncol)]

    def render(r):
        out = (r[0] or "").ljust(4) + " " + (r[1] or "").ljust(3) + "    " + (r[2] or "").ljust(7)
        for c in range(3, ncol):
            out += "  " + (r[c] or "").rjust(w[c])
        return out.rstrip()

    hdr = [None, None, None, "Total"] + (["Should", "Diff"] if diff else [])
    d.line(render(hdr), "header", hdr)
    for r in rows:
        d.line(render(r), "row", r)
    left = 4 + 1 + 3 + 4 + 7
    d.skip(" " * (left + 1) + "=" * (sum(w[3:]) + 2 * (ncol - 3) - 1))
    total = [None, None, None, hm(tot)] + ([hm(should_tot), hm(tot - should_tot, True)] if diff else [])
    d.line(render(total), "row", total)
    return d
