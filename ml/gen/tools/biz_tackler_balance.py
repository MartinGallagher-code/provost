"""tackler (plain-text accounting) balance report: an optional Git Storage
metadata block (right-aligned `key : value`), the `Balance Report` title and
rule, then one line per account (own balance, accumulated balance, account
path, optional commodity), a `====` rule and the total."""
from lib import Doc, fake

TOOL = "tackler-balance"

TREE = {
    "Assets": ["Assets:Cash", "Assets:Bank:Checking", "Assets:Bank:Savings", "Assets:Receivables"],
    "Expenses": ["Expenses:Food", "Expenses:Sweets", "Expenses:Rent", "Expenses:Travel:Train",
                 "Expenses:Travel:Hotel", "Expenses:Office", "Expenses:Software"],
    "Income": ["Income:Salary", "Income:Consulting", "Income:Interest"],
    "Liabilities": ["Liabilities:CreditCard", "Liabilities:VAT"],
}


def generate(rng):
    d = Doc()
    comm = rng.choice([None, None, "EUR", "USD", "SEK", "coffee"])
    if rng.random() < 0.5:
        d.section("Git Storage")
        pairs = [("commit", fake.hexid(rng, 40)), ("reference", rng.choice(["main", "master", "txns-2024", "HEAD"])),
                 ("directory", rng.choice(["txns", "journal", "txns/2024"])), ("suffix", ".txn"),
                 ("message", rng.choice(["2024-Q1 bank import", "fix: Rent posting", "add March receipts", "Initial commit"]))]
        if rng.random() < 0.5:
            pairs.insert(1, ("time", f"{fake.date(rng, 'datetime')}{rng.choice(['+02:00', 'Z', '-05:00'])}"))
        w = max(len(k) for k, _ in pairs) + rng.randint(4, 10)
        for k, v in pairs:
            d.line(k.rjust(w) + " : " + v, "kv", [k, v])
        d.blank()
    if rng.random() < 0.3:
        d.section("Account Selector Checksum")
        h = fake.hexid(rng, 64)
        d.line("SHA-256".rjust(rng.randint(10, 18)) + " : " + h, "kv", ["SHA-256", h])
        d.blank()
    title = rng.choice(["Balance Report", "BALANCE"])
    d.section(title)
    d.skip("-" * len(title))
    lines = []
    total = 0.0
    for top in sorted(rng.sample(list(TREE), rng.randint(1, 4))):
        kids = sorted(rng.sample(TREE[top], rng.randint(1, len(TREE[top]))))
        sign = -1 if top in ("Income", "Liabilities") else 1
        vals = [round(sign * rng.choice([rng.uniform(1, 99), rng.uniform(100, 5000)]), 2) for _ in kids]
        acc = sum(vals)
        own = round(rng.choice([0.0, 0.0, rng.uniform(1, 50)]), 2)
        lines.append((own, own + acc, top))
        for k, v in zip(kids, vals):
            lines.append((v, v, k))
        total += own + acc
    w = max(len(f"{x:.2f}") for a, b, _ in lines for x in (a, b))
    w = max(w, len(f"{total:.2f}")) + rng.randint(2, 6)
    for own, acc, name in lines:
        a, b = f"{own:.2f}", f"{acc:.2f}"
        text = " " * 2 + a.rjust(w) + "   " + b.rjust(w) + ("  " + comm if comm else "") + "  " + name
        d.line(text, "row", [a, b] + ([comm] if comm else []) + [name])
    d.skip("=" * (2 + w * 2 + 3 + (len(comm) + 2 if comm else 0)))
    t = f"{total:.2f}"
    d.line(" " * 2 + " " * (w + 3) + t.rjust(w) + ("  " + comm if comm else ""), "row", [t] + ([comm] if comm else []))
    return d
