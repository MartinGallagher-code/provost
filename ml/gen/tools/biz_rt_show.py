"""Request Tracker CLI `rt show ticket/N` (one or several tickets, separated
by `--`): `Field: value` lines, empty fields bare, `Not set` dates, custom
fields as `CF.{Name}:`; old servers prefix an `RT/x.y.z 200 Ok` status."""
from lib import Doc

TOOL = "rt-show"

QUEUES = ["General", "Support", "Billing", "Sales", "Accounts Receivable", "IT", "HR"]
SUBJ = ["test ticket", "Invoice INV-2023-0412 not received", "Refund request for order #88123",
        "Cannot log in to customer portal", "Update billing address", "Quote for 50 licences",
        "Payment failed - card declined", "VAT number missing on invoice", "Contract renewal 2025",
        "Duplicate charge on statement"]
USERS = ["root", "Nobody", "alice", "bob", "carol", "dave", "billing-team"]
WD = "Mon Tue Wed Thu Fri Sat Sun".split()
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def rtdate(rng):
    return (f"{rng.choice(WD)} {rng.choice(MON)} {rng.randint(1, 28):02d} "
            f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {rng.randint(2008, 2026)}")


def email(rng):
    return f"{rng.choice(['jsmith', 'ap', 'finance', 'm.garcia', 'help', 'li.wei'])}@{rng.choice(['example.com', 'acme.io', 'globex.co.uk', 'initech.com'])}"


def generate(rng):
    d = Doc()
    if rng.random() < 0.3:
        d.skip(f"RT/{rng.choice(['3.8.7', '4.2.16', '4.4.4', '5.0.3'])} 200 Ok")
        d.blank()
    n = rng.choice([1, 1, 1, 2, 3])
    for t in range(n):
        if t:
            d.skip("--")
            d.blank() if rng.random() < 0.2 else None
        status = rng.choice(["new", "open", "stalled", "resolved", "rejected"])
        worked = rng.choice([0, 0, rng.randint(5, 600)])
        pairs = [("id", f"ticket/{rng.randint(1, 99999)}"), ("Queue", rng.choice(QUEUES)),
                 ("Owner", rng.choice(USERS)), ("Creator", rng.choice(USERS + [email(rng)])),
                 ("Subject", rng.choice(SUBJ)), ("Status", status), ("Priority", str(rng.choice([0, 0, 10, 50, 90]))),
                 ("InitialPriority", str(rng.choice([0, 0, 10]))), ("FinalPriority", str(rng.choice([0, 0, 100]))),
                 ("Requestors", ", ".join(email(rng) for _ in range(rng.choice([1, 1, 2])))),
                 ("Cc", email(rng) if rng.random() < .2 else ""), ("AdminCc", ""),
                 ("Created", rtdate(rng)),
                 ("Starts", "Not set"), ("Started", rtdate(rng) if status != "new" else "Not set"),
                 ("Due", rtdate(rng) if rng.random() < .3 else "Not set"),
                 ("Resolved", rtdate(rng) if status in ("resolved", "rejected") else "Not set"),
                 ("Told", rtdate(rng) if rng.random() < .5 else "Not set"),
                 ("LastUpdated", rtdate(rng)),
                 ("TimeEstimated", str(rng.choice([0, 0, 60, 120]))), ("TimeWorked", f"{worked} minutes" if worked and rng.random() < .5 else str(worked)),
                 ("TimeLeft", "0")]
        for cf in rng.sample(["Customer", "Account Number", "Invoice", "Severity", "Product", "Contract ID"], rng.randint(0, 3)):
            v = {"Customer": rng.choice(["Acme Corp", "Globex", "Initech", "Hooli"]),
                 "Account Number": f"AC-{rng.randint(10000, 99999)}", "Invoice": f"INV-{rng.randint(1000, 9999)}",
                 "Severity": rng.choice(["Low", "Medium", "High", "Critical"]),
                 "Product": rng.choice(["Payroll", "Invoicing", "CRM"]), "Contract ID": ""}[cf]
            pairs.append((f"CF.{{{cf}}}", v if rng.random() < .85 else ""))
        for k, v in pairs:
            if v:
                d.kv(k, v)
            else:
                d.line(f"{k}:", "kv", [k])
    return d
