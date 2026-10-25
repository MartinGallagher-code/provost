"""xlsx2csv (optionally -a, all sheets): each sheet introduced by the
`-------- N - Name` delimiter, then its rows as CSV, the first row naming the
columns; fields with commas are quoted, empty cells leave bare commas."""
from lib import Doc

TOOL = "xlsx2csv"

SHEETS = {
    "Invoices": ["Invoice", "Date", "Customer", "Net", "VAT", "Total", "Paid"],
    "Expenses": ["Date", "Category", "Description", "Amount", "Receipt"],
    "Budget 2025": ["Account", "Jan", "Feb", "Mar", "Q1 Total"],
    "Timesheet": ["Employee", "Week", "Project", "Hours", "Rate", "Billable"],
    "Customers": ["ID", "Name", "Country", "Email", "Credit Limit"],
    "Sheet1": ["Item", "Qty", "Unit Price", "Total"],
}
CUST = ["Acme, Inc.", "Globex Corporation", "Initech", "Hooli", "Umbrella Corp", "Wayne Enterprises",
        "Stark Industries", "Soylent Green Ltd", "Vandelay Industries", "Bluth Company, LLC"]
CAT = ["Travel", "Meals", "Software", "Office Supplies", "Hardware", "Training", "Postage"]
DESC = ["Train to Leeds", "Team lunch", "Annual licence, JetBrains", "Printer toner", "Taxi to airport",
        "Monitor 27\"", "Conference ticket", "Stamps"]
ACCT = ["Salaries", "Rent", "Marketing", "Cloud hosting", "Travel", "Legal & accounting", "Insurance"]


def q(v):
    return '"' + v.replace('"', '""') + '"' if ("," in v or '"' in v) else v


def cell_rows(rng, name, datefmt):
    def date():
        y, m, d = rng.randint(2019, 2026), rng.randint(1, 12), rng.randint(1, 28)
        return datefmt.format(y=y, m=m, d=d, yy=y % 100)
    out = []
    for i in range(rng.randint(1, 12)):
        if name == "Invoices":
            net = rng.randint(100, 20000) + rng.choice([0, 0.5, 0.25, 0.99])
            vat = round(net * 0.2, 2)
            r = [f"INV-{1000 + i + rng.randint(0, 50)}", date(), rng.choice(CUST), f"{net:g}", f"{vat:g}",
                 f"{round(net + vat, 2):g}", rng.choice(["Yes", "No", ""])]
        elif name == "Expenses":
            r = [date(), rng.choice(CAT), rng.choice(DESC), f"{rng.uniform(2, 900):.2f}", rng.choice(["yes", "no", ""])]
        elif name == "Budget 2025":
            v = [rng.randint(0, 50000) for _ in range(3)]
            r = [rng.choice(ACCT)] + [str(x) if rng.random() > .1 else "" for x in v] + [str(sum(v))]
        elif name == "Timesheet":
            h = rng.choice([7.5, 8, 37.5, 40, 12.25, 3])
            r = [rng.choice(["A. Smith", "B. Jones", "C. Nguyen", "D. Okafor"]), f"W{rng.randint(1, 52)}",
                 rng.choice(["Acme ERP", "Globex audit", "Internal"]), f"{h:g}", str(rng.choice([85, 120, 150])),
                 rng.choice(["TRUE", "FALSE"])]
        elif name == "Customers":
            c = rng.choice(CUST)
            r = [str(rng.randint(1, 9999)), c, rng.choice(["UK", "US", "DE", "FR", "NL", ""]),
                 f"ap@{c.split()[0].lower().strip(',')}.com" if rng.random() < .8 else "", str(rng.choice([5000, 10000, 25000, 0]))]
        else:
            qty, up = rng.randint(1, 40), rng.choice([1.5, 9.99, 24, 120, 0.35])
            r = [rng.choice(["Widget", "Gadget", "Bracket, steel", "Cable 2m", "Service hours"]), str(qty), f"{up:g}", f"{qty * up:.2f}"]
        out.append(r)
    return out


def generate(rng):
    d = Doc()
    datefmt = rng.choice(["{y}-{m:02d}-{d:02d}", "{y}-{m:02d}-{d:02d}", "{m:02d}-{d:02d}-{yy:02d}", "{d:02d}/{m:02d}/{y}"])
    allsheets = rng.random() < 0.6
    names = rng.sample(list(SHEETS), rng.randint(2, 4) if allsheets else 1)
    for i, name in enumerate(names):
        if allsheets:
            d.line(f"-------- {i + 1} - {name}", "section", [name])
        hdr = SHEETS[name]
        d.line(",".join(q(h) for h in hdr), "header", hdr)
        for r in cell_rows(rng, name, datefmt):
            d.line(",".join(q(c) for c in r), "row", [c if c else None for c in r])
    return d
