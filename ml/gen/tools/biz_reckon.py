"""reckon (CSV bank statement -> ledger): an optional guess notice, then
either the parsed table (-p: terminal-table with Date/Amount/Description
header) or the interactive loop: each transaction in its own +---+ box
followed by the account prompt and the typed answer."""
from lib import Doc

TOOL = "reckon"

DESC = ["AMAZON MKTPLACE PMTS AMZN.COM/BILL WA", "WALGREENS #00000 DES:PURCHASE", "PAYROLL ACME CORP DIRECT DEP",
        "CHECK 1043", "SAFEWAY STORE 1234 SAN FRANCISCO CA", "TRANSFER TO SAVINGS 0042",
        "PG&E WEB ONLINE", "STARBUCKS #1182 SEATTLE", "INTEREST PAYMENT", "UBER *TRIP HELP.UBER.COM",
        "COMCAST CABLE COMM", "VENMO PAYMENT 1023881", "ATM WITHDRAWAL 0331 MAIN ST", "NETFLIX.COM"]
ACCT_OUT = ["Expenses:Shopping", "Expenses:Pharmacy", "Expenses:Groceries", "Expenses:Utilities:Electric",
            "Expenses:Coffee", "Expenses:Transport", "Expenses:Cable", "Assets:Savings", "Expenses:Cash"]
ACCT_IN = ["Income:Salary", "Income:Interest", "Income:Refunds", "Income:Venmo"]
NOTICES = ["I didn't find a high-likelyhood money column, but I'm taking my best guess with column 4.",
           "I didn't find a high-likelyhood money column, but I'm taking my best guess with column 3."]


def box(cells, widths):
    return "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"


def rule(widths):
    return "+" + "+".join("-" * (w + 2) for w in widths) + "+"


def generate(rng):
    d = Doc()
    datefmt = rng.choice(["{y}-{m:02d}-{d:02d}", "{y}/{m:02d}/{d:02d}"])
    cur = rng.choice(["$", "$", "€", "£"])
    y, mo, dd = rng.randint(2010, 2026), rng.randint(1, 12), rng.randint(1, 10)
    txns = []
    for _ in range(rng.randint(2, 9)):
        income = rng.random() < 0.25
        amt = rng.choice([rng.uniform(1, 99), rng.uniform(100, 4999)])
        a = f"{'' if income else '-'}{cur}{amt:,.2f}"
        txns.append((datefmt.format(y=y, m=mo, d=dd), a, rng.choice(DESC), income))
        dd = min(28, dd + rng.randint(0, 3))
    if rng.random() < 0.4:
        d.skip(rng.choice(NOTICES))
    dw = max(len(t[0]) for t in txns)
    aw = max(10, max(len(t[1]) for t in txns))
    sw = max(rng.choice([40, 48, 56]), max(len(t[2]) for t in txns))
    if rng.random() < 0.4:
        w = [max(dw, 4), aw, sw]
        d.skip(rule(w))
        d.line(box(["Date", "Amount", "Description"], w), "header", ["Date", "Amount", "Description"])
        d.skip(rule(w))
        for t in txns:
            d.line(box(t[:3], w), "row", list(t[:3]))
        d.skip(rule(w))
        return d
    w = [dw, aw, sw]
    for i, t in enumerate(txns):
        d.skip(rule(w))
        d.line(box(t[:3], w), "row", list(t[:3]))
        d.skip(rule(w))
        q = ("From which account did this money come?" if t[3] else "To which account did this money go?")
        ans = rng.choice(ACCT_IN if t[3] else ACCT_OUT)
        r = rng.random()
        if r < 0.1:
            ans = "s"
        elif r < 0.15 and i < len(txns) - 1:
            ans = "q"
        d.skip(f"{q} ([account]/[q]uit/[s]kip) {ans}")
        if ans == "q":
            break
    return d
