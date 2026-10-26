"""`utt report` (Ultimate Time Tracker): a centred date banner, Working/Break
time key-values, then Projects / Activities / Details sections, each a
centred rule-heading followed by `(1h30) project: activity` lines."""
from lib import Doc

TOOL = "utt-report"

WD = "Monday Tuesday Wednesday Thursday Friday Saturday Sunday".split()
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
PROJ = {"acme": ["invoicing", "support call", "deploy"], "internal": ["standup", "1:1", "hiring"],
        "billing": ["dunning emails", "refunds", "stripe reconciliation"],
        "finance": ["budget 2025", "expense review", "VAT return"], "sales": ["demo", "proposal", "CRM cleanup"],
        "asd": ["A", "B", "C"], "qwer": ["foo", "bar"]}
BREAKS = ["lunch**", "coffee**", "break**", "gym**", "commute***"]


def hm(m):
    return f"{m // 60}h{m % 60:02d}"


def banner(text, fill="-", width=80):
    t = f" {text} "
    left = (width - len(t)) // 2
    return fill * left + t + fill * (width - len(t) - left)


def generate(rng):
    d = Doc()
    wd, mo, dd, y = rng.randint(0, 6), rng.randint(1, 12), rng.randint(1, 28), rng.randint(2014, 2026)
    week = (mo - 1) * 4 + dd // 7 + 1
    title = f"{WD[wd]}, {MON[mo - 1]} {dd:02d}, {y} (week {week})"
    acts = []  # (start, end, project or None, name)
    t = rng.randint(7 * 60, 10 * 60)
    for _ in range(rng.randint(2, 9)):
        ln = rng.choice([15, 30, 45, 60, 60, 90, 120, rng.randint(5, 180)])
        if rng.random() < 0.2:
            acts.append((t, t + ln, None, rng.choice(BREAKS)))
        else:
            p = rng.choice(list(PROJ))
            acts.append((t, t + ln, p, rng.choice(PROJ[p])))
        t += ln
    work = sum(e - s for s, e, p, _ in acts if p)
    brk = sum(e - s for s, e, p, _ in acts if not p)
    d.section(banner(title), title)
    d.blank()
    wt = f"{hm(work)} ({hm(work + brk)} - {hm(brk)})"
    d.kv("Working Time", wt)
    d.line(f"Break   Time: {hm(brk)}", "kv", ["Break   Time", hm(brk)])
    d.blank()
    # Projects
    d.section(banner("Projects"), "Projects")
    d.blank()
    byp = {}
    for s, e, p, n in acts:
        if p:
            byp.setdefault(p, [0, []])
            byp[p][0] += e - s
            if n not in byp[p][1]:
                byp[p][1].append(n)
    for p in sorted(byp):
        dur, names = byp[p]
        d.line(f"({hm(dur)}) {p}: {', '.join(names)}", "row", [f"({hm(dur)})", p, ", ".join(names)])
    d.blank()
    d.section(banner("Activities"), "Activities")
    d.blank()
    bya = {}
    for s, e, p, n in acts:
        bya[(p, n)] = bya.get((p, n), 0) + e - s
    for (p, n), dur in sorted(((k, v) for k, v in bya.items() if k[0]), key=lambda kv: kv[0]):
        d.line(f"({hm(dur)}) {p}: {n}", "row", [f"({hm(dur)})", p, n])
    brks = [(k, v) for k, v in bya.items() if not k[0]]
    if brks:
        d.blank()
        for (p, n), dur in brks:
            d.line(f"({hm(dur)}) {n}", "row", [f"({hm(dur)})", n])
    if rng.random() < 0.7:
        d.blank()
        d.section(banner("Details"), "Details")
        d.blank()
        for s, e, p, n in acts:
            span = f"{s // 60:02d}:{s % 60:02d}-{e // 60 % 24:02d}:{e % 60:02d}"
            if p:
                d.line(f"({hm(e - s)}) {span} {p}: {n}", "row", [f"({hm(e - s)})", span, p, n])
            else:
                d.line(f"({hm(e - s)}) {span} {n}", "row", [f"({hm(e - s)})", span, n])
    return d
