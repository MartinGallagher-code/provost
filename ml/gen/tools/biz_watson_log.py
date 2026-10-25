"""`watson log`: one heading per day (date and the day's total), then one
fixed-layout line per frame: id, start/stop, duration, project, tags."""
from lib import Doc, fake

TOOL = "watson-log"

DAYS = "Monday Tuesday Wednesday Thursday Friday Saturday Sunday".split()
MONTHS = ("January February March April May June July August September October "
          "November December").split()
PROJECTS = ("apollo11 hubble voyager world-domination acme-website client-billing "
            "invoicing q3-report internal admin sales-pipeline support onboarding "
            "migration-2024 bookkeeping").split()
TAGS = ("meeting review cats brakes steering lens design dev calls email ops "
        "writing research hotfix planning").split()


def dur(secs, short):
    h, m, s = secs // 3600, secs % 3600 // 60, secs % 60
    if h:
        return f"{h}h {m:02d}m {s:02d}s" if not short else f"{h}h {m:02d}m"
    return f"{m:02d}m {s:02d}s"


def generate(rng):
    d = Doc()
    short = rng.random() < 0.2
    year = rng.randint(2016, 2026)
    month = rng.randint(1, 12)
    day = rng.randint(10, 28)
    wd = rng.randint(0, 6)
    ndays = rng.randint(1, 4)
    for k in range(ndays):
        frames = []
        t = rng.randint(7 * 60, 10 * 60)
        for _ in range(rng.randint(1, 6)):
            t += rng.randint(0, 45)
            length = rng.randint(3, 180) * 60 + rng.randint(0, 59)
            st = f"{t // 60 % 24:02d}:{t % 60:02d}"
            t += length // 60
            en = f"{t // 60 % 24:02d}:{t % 60:02d}"
            tags = rng.sample(TAGS, rng.choice([0, 0, 1, 1, 2, 3]))
            frames.append((fake.hexid(rng, 7), f"{st} to {en}", length, rng.choice(PROJECTS), tags))
        total = sum(f[2] for f in frames)
        title = f"{DAYS[(wd - k) % 7]} {day - k:02d} {MONTHS[month - 1]} {year} ({dur(total, short)})"
        d.line(title, "section", [title])
        dw = max(len(dur(f[2], short)) for f in frames)
        pw = max(len(f[3]) for f in frames)
        for fid, span, length, proj, tags in frames:
            ds = dur(length, short)
            text = f"\t{fid}  {span}  {ds.rjust(dw + 4)}  {proj}"
            cells = [fid, span, ds, proj]
            if tags:
                tg = "[" + ", ".join(tags) + "]"
                text = text.ljust(len(text) + pw - len(proj)) + "  " + tg
                cells.append(tg)
            d.line(text, "row", cells)
        if k < ndays - 1:
            d.blank()
    return d
