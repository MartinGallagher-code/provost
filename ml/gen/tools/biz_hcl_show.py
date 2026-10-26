"""hcl (Harvest command line) `hcl show`: one tab-indented line per day entry
(hours, optional `(running)`, project: last line of the notes), cut at the
terminal width, then a dash rule and the total line."""
from lib import Doc

TOOL = "hcl-show"

PROJ = ["Acme Corp", "Globex - Website Redesign", "Internal", "Initech - Support Retainer",
        "Umbrella", "Admin", "Sales & Marketing", "Hooli - Q4 Audit", "Wayne Enterprises",
        "Stark Industries - API", "Bookkeeping"]
NOTES = ["wiki entry for slicing", "fixed the login bug", "weekly sync", "call with accountant",
         "invoice #2231 and follow-up emails about the overdue balance from last quarter",
         "reviewed pull requests", "", "timesheets", "drafted SOW for phase 2 including estimates, "
         "assumptions, and the change-request process", "standup", "expense report", "onboarding",
         "migrated the reporting dashboards to the new warehouse"]


def generate(rng):
    d = Doc()
    cols = rng.choice([80, 80, 80, 100, 120, 200])
    total = 0
    n = rng.randint(1, 8)
    for i in range(n):
        mins = rng.choice([rng.randint(1, 16) * 15, rng.randint(1, 300)])
        total += mins
        hrs = f"{mins // 60}:{mins % 60:02d}"
        running = i == n - 1 and rng.random() < 0.25
        proj = rng.choice(PROJ)
        note = rng.choice(NOTES)
        text = f"\t{hrs}\t" + ("(running) " if running else "") + f"{proj}: {note}"
        text = text[:cols - 1]
        cells = [hrs] + (["(running)"] if running else [])
        if len(text) >= text.find(proj) + len(proj):
            cells.append(proj)
            rest = text[text.find(proj) + len(proj) + 2:]
            if rest.strip():
                cells.append(rest.strip())
        else:
            cells.append(text[text.find("\t", 1) + 1:].replace("(running) ", ""))
        d.line(text, "row", [c for c in cells if c])
    d.skip("\t" + "-" * 13)
    h, m = rng.randint(1, 12), rng.randint(0, 59)
    tot = f"{total // 60}:{total % 60:02d}"
    lab = f"total (as of {h}:{m:02d} {rng.choice(['am', 'pm'])})"
    d.line(f"\t{tot}\t{lab}", "row", [tot, lab])
    return d
