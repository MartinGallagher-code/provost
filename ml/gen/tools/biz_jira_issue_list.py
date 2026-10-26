"""jira-cli `jira issue list --plain`: a tabwriter table padded with tab
characters (columns chosen with --columns, header dropped with --no-headers),
empty cells for unassigned / unresolved issues."""
from lib import Doc

TOOL = "jira-issue-list"

ALL = ["TYPE", "KEY", "SUMMARY", "STATUS", "ASSIGNEE", "REPORTER", "PRIORITY", "RESOLUTION", "CREATED", "UPDATED", "LABELS"]
SUMM = ["Invoice PDF missing VAT line", "Add SEPA direct debit support", "Quarterly revenue report shows wrong totals",
        "Customer cannot update payment method", "Migrate CRM contacts to new schema", "Refund flow times out",
        "Export ledger to CSV", "Spike: evaluate Stripe Tax", "Dunning emails sent twice",
        "Budget dashboard: add FY filter", "Sales pipeline stage names out of date", "Fix rounding in multi-currency totals",
        "Onboard Globex as enterprise customer", "Purchase order approval workflow"]
PEOPLE = ["John Doe", "Jane Smith", "Priya Patel", "Marco Rossi", "Li Wei", "Fatima Khan", "Ole Nordmann", "Ana Souza"]


def tabpad(cells, widths):
    out = ""
    for i, (c, w) in enumerate(zip(cells, widths)):
        c = c or ""
        if i == len(cells) - 1:
            out += c
        else:
            cw = ((w + 1 + 7) // 8) * 8
            out += c + "\t" * ((cw - len(c) // 8 * 8) // 8)
    return out.rstrip("\t")


def generate(rng):
    d = Doc()
    if rng.random() < 0.5:
        cols = ALL[:10]
    else:
        cols = ["KEY", "SUMMARY"] + [c for c in rng.sample(ALL, rng.randint(1, 5)) if c not in ("KEY", "SUMMARY")]
        cols = sorted(cols, key=ALL.index)
    proj = rng.choice(["PROJ", "FIN", "BILL", "CRM", "SALES", "ACC"])
    rows = []
    for _ in range(rng.randint(2, 14)):
        status = rng.choice(["To Do", "In Progress", "In Review", "Done", "Backlog", "Blocked"])
        y, m = rng.randint(2020, 2026), rng.randint(1, 12)
        cr = f"{y}-{m:02d}-{rng.randint(1, 28):02d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
        up = f"{y}-{min(12, m + rng.randint(0, 2)):02d}-{rng.randint(1, 28):02d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
        v = {"TYPE": rng.choice(["Bug", "Story", "Task", "Epic", "Sub-task"]), "KEY": f"{proj}-{rng.randint(1, 4999)}",
             "SUMMARY": rng.choice(SUMM), "STATUS": status,
             "ASSIGNEE": rng.choice(PEOPLE) if rng.random() < .8 else None, "REPORTER": rng.choice(PEOPLE),
             "PRIORITY": rng.choice(["Highest", "High", "Medium", "Low", "Lowest"]),
             "RESOLUTION": rng.choice(["Done", "Won't Do", "Duplicate"]) if status == "Done" else None,
             "CREATED": cr, "UPDATED": up,
             "LABELS": ",".join(rng.sample(["billing", "finance", "q3", "tech-debt", "customer"], rng.randint(0, 2))) or None}
        rows.append([v[c] for c in cols])
    head = rng.random() < 0.8
    widths = [max(len(x or "") for x in col) for col in zip(*([cols] if head else []), *rows)]
    if head:
        d.line(tabpad(cols, widths), "header", cols)
    for r in rows:
        txt = tabpad(r, widths)
        d.line(txt, "row", r if head else [c for c in r if c])
    return d
