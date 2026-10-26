"""Salesforce `sfdx force:data:soql:query`: optional `Querying Data... done`,
an uppercase header, a ─── rule per column, one row per record (null fields
blank or `null`), then `Total number of records retrieved: N.`"""
from lib import Doc

TOOL = "sfdx-force-data-soql-query"

ACCTS = ["Edge Communications", "Burlington Textiles Corp of America", "Pyramid Construction Inc.",
         "Dickenson plc", "Grand Hotels & Resorts Ltd", "United Oil & Gas Corp.", "Express Logistics and Transport",
         "University of Arizona", "GenePoint", "sForce", "Acme", "Global Media", "salesforce.com"]
FIRST = ["Rose", "Sean", "Jack", "Tim", "John", "Lauren", "Babara", "Josh", "Jane", "Arthur", "Ashley", "Stella"]
LAST = ["Gonzalez", "Forbes", "Rogers", "Barr", "Bond", "Boyle", "Levy", "Davis", "Grey", "Song", "James", "Pavlova"]
STAGES = ["Prospecting", "Qualification", "Needs Analysis", "Value Proposition", "Id. Decision Makers",
          "Perception Analysis", "Proposal/Price Quote", "Negotiation/Review", "Closed Won", "Closed Lost"]
INDUSTRY = ["Electronics", "Apparel", "Construction", "Consulting", "Hospitality", "Energy", "Transportation",
            "Education", "Biotechnology", "Media"]


def sfid(rng, prefix):
    al = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    return prefix + "".join(rng.choice(al) for _ in range(12)) + "".join(rng.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ") for _ in range(3))


def generate(rng):
    d = Doc()
    obj = rng.choice(["Account", "Contact", "Opportunity", "Case"])
    nul = rng.choice(["", "null"])
    n = rng.randint(1, 14) if rng.random() < .93 else 0
    rows = []
    if obj == "Account":
        hdr = ["ID", "NAME"] + rng.sample(["INDUSTRY", "TYPE", "BILLINGCITY", "ANNUALREVENUE", "PHONE"], rng.randint(0, 3))
    elif obj == "Contact":
        hdr = ["ID", "FIRSTNAME", "LASTNAME"] + rng.sample(["EMAIL", "ACCOUNT.NAME", "TITLE"], rng.randint(0, 2))
    elif obj == "Opportunity":
        hdr = ["ID", "NAME", "STAGENAME", "AMOUNT"] + (["CLOSEDATE"] if rng.random() < .6 else [])
    else:
        hdr = ["ID", "CASENUMBER", "SUBJECT", "STATUS", "PRIORITY"]
    pre = {"Account": "001", "Contact": "003", "Opportunity": "006", "Case": "500"}[obj]
    for i in range(n):
        f, l, a = rng.choice(FIRST), rng.choice(LAST), rng.choice(ACCTS)
        val = {
            "ID": sfid(rng, pre), "NAME": a if obj == "Account" else f"{a} - {rng.choice(['Renewal', 'Add-On', 'New Business', '2,000 units', 'Upgrade'])}",
            "INDUSTRY": rng.choice(INDUSTRY), "TYPE": rng.choice(["Customer - Direct", "Customer - Channel", "Prospect", "Partner"]),
            "BILLINGCITY": rng.choice(["Austin", "Burlington", "Paris", "London", "Chicago", "Tucson", "Singapore"]),
            "ANNUALREVENUE": str(rng.choice([139000000, 350000000, 950000000, 5600000000, 30000000])),
            "PHONE": f"({rng.randint(200, 999)}) {rng.randint(200, 999)}-{rng.randint(1000, 9999)}",
            "FIRSTNAME": f, "LASTNAME": l, "EMAIL": f"{f[0].lower()}{l.lower()}@{a.split()[0].lower().strip('.,')}.com",
            "ACCOUNT.NAME": a, "TITLE": rng.choice(["SVP, Finance", "CFO", "VP, Facilities", "Buyer", "Director, IT"]),
            "STAGENAME": rng.choice(STAGES), "AMOUNT": str(rng.choice([15000, 120000, 270000, 675000, 1000000, 85000])),
            "CLOSEDATE": f"20{rng.randint(15, 26)}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}",
            "CASENUMBER": f"{1000 + rng.randint(1, 30):08d}",
            "SUBJECT": rng.choice(["Starting generator after electrical failure", "Seeking guidance on electrical wiring installation",
                                   "Billing discrepancy on invoice INV-0042", "Cannot track shipment", "Design issue with mechanical rotor"]),
            "STATUS": rng.choice(["New", "Working", "Escalated", "Closed"]), "PRIORITY": rng.choice(["High", "Medium", "Low"]),
        }
        rows.append([val[h] if h in ("ID", "NAME") or rng.random() > 0.15 else None for h in hdr])
    if n == 0 or rng.random() < 0.5:
        d.skip("Querying Data... done")
    if n:
        w = [max(len(x or nul) for x in col) for col in zip(hdr, *rows)]
        d.line("  ".join(h.ljust(wi) for h, wi in zip(hdr, w)).rstrip(), "header", hdr)
        d.skip("  ".join("─" * wi for wi in w))
        for r in rows:
            d.line("  ".join((c or nul).ljust(wi) for c, wi in zip(r, w)).rstrip(), "row",
                   [c if c else (nul or None) for c in r])
    d.kv("Total number of records retrieved", f"{n}.")
    return d
