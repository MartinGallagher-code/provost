"""`doing show` / `doing recent --totals`: one `date | title` line per entry
(tags and @done(...) inside the title, interval appended with --times),
indented note lines under some entries, then an optional Tag Totals block."""
from lib import Doc

TOOL = "doing-show"

TITLES = ["Working on invoice template", "Call with Globex about renewal", "Reconcile March statements",
          "Write proposal for Initech", "Expense reports", "Standup", "Payroll review",
          "Update CRM pipeline", "Fix VAT rounding in quotes", "Lunch", "Client onboarding: Hooli",
          "Prepare board deck numbers", "Answer support tickets", "Budget planning for FY26"]
TAGS = ["meeting", "billing", "admin", "client", "finance", "writing", "sales", "support", "project(acme)"]
NOTES = ["Sent draft to Bob for review", "Need sign-off from finance before Friday",
         "Ticket #4521", "Follow up next week", "See shared folder /Clients/Initech/2025",
         "Rate: $150/h, 6h estimated"]


def generate(rng):
    d = Doc()
    times = rng.random() < 0.5
    totals = rng.random() < 0.6
    y, mo, dd = rng.randint(2015, 2026), rng.randint(1, 12), rng.randint(1, 26)
    t = rng.randint(7 * 60, 10 * 60)
    tagtot = {}
    tracked = 0
    for i in range(rng.randint(2, 10)):
        if t > 23 * 60:
            dd, t = dd + 1, rng.randint(7 * 60, 10 * 60)
        date = f"{y}-{mo:02d}-{dd:02d} {t // 60:02d}:{t % 60:02d}"
        tags = rng.sample(TAGS, rng.choice([0, 1, 1, 2]))
        title = rng.choice(TITLES) + "".join(" @" + g for g in tags)
        ln = rng.randint(5, 180)
        done = rng.random() < 0.8
        if done:
            e = t + ln
            title += f" @done({y}-{mo:02d}-{dd:02d} {e // 60 % 24:02d}:{e % 60:02d})"
            tracked += ln
            for g in tags + ["done"] if rng.random() < .5 else tags:
                tagtot[g.split("(")[0]] = tagtot.get(g.split("(")[0], 0) + ln
        text = f"{date} | {title}"
        cells = [date, title]
        if times and done:
            iv = f"{ln // 60:02d}:{ln % 60:02d}:00"
            text += f"  {iv}"
            cells.append(iv)
        d.line(text, "row", cells)
        if rng.random() < 0.25:
            for _ in range(rng.randint(1, 2)):
                n = rng.choice(NOTES)
                d.line("\t\t" + n, "cont", [n])
        t += ln + rng.randint(0, 60)

    def hms(m):
        return f"{m // 60:02d}:{m % 60:02d}:00"

    if totals and tagtot:
        d.blank()
        d.section("--- Tag Totals ---", "Tag Totals")
        w = max(len(k) for k in tagtot) + 1
        for k, v in sorted(tagtot.items(), key=lambda kv: -kv[1]):
            d.line((k + ":").ljust(w + rng.choice([1, 2])) + hms(v), "kv", [k, hms(v)])
        d.blank()
        d.kv("Total tracked", hms(tracked))
    return d
