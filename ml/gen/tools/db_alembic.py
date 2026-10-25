"""`alembic history` (one `down -> up (flags), message` line per revision) and
`alembic history --verbose` (Rev/Parent/Path key-values, the docstring, and
Revision ID / Revises / Create Date)."""
from lib import Doc, fake

TOOL = "alembic-history"

MSGS = ["create users table", "add email to users", "add index on users email", "create orders table",
        "add status column to orders", "drop legacy sessions", "rename account to tenant", "add audit log",
        "backfill created_at", "merge heads", "initial schema", "add fk orders.user_id", "widen sku to 64 chars",
        "create invoices and invoice_lines tables", "add partial index for active subscriptions", "empty message"]


def generate(rng):
    d = Doc()
    n = rng.randint(2, 12)
    revs = [fake.hexid(rng, 12) for _ in range(n)]
    msgs = [rng.choice(MSGS) for _ in range(n)]
    # newest first, the way alembic prints it
    chain = []
    for i in range(n - 1, -1, -1):
        parent = revs[i - 1] if i else "<base>"
        flags = []
        if i == n - 1:
            flags.append("(head)")
        if i == n // 2 and rng.random() < .25:
            flags.append("(branchpoint)")
        chain.append((parent, revs[i], " ".join(flags), msgs[i]))
    verbose = rng.random() < .45
    if rng.random() < .3:
        d.line("INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.", "row",
               ["INFO", "[alembic.runtime.migration]", "Context impl PostgresqlImpl."])
        d.line("INFO  [alembic.runtime.migration] Will assume transactional DDL.", "row",
               ["INFO", "[alembic.runtime.migration]", "Will assume transactional DDL."])
    root = rng.choice(["/app/migrations", "/srv/api/alembic", "/home/deploy/project/db/migrations"])
    for parent, rev, flags, msg in chain:
        if not verbose:
            text = f"{parent} -> {rev}" + (f" {flags}" if flags else "") + f", {msg}"
            d.line(text, "row", [parent, rev, flags or None, msg])
            continue
        d.line(f"Rev: {rev}" + (f" {flags}" if flags else ""), "kv", ["Rev", rev] + ([flags] if flags else []))
        d.kv("Parent", parent)
        if flags and "branchpoint" in flags:
            d.kv("Branches into", fake.hexid(rng, 12) + ", " + fake.hexid(rng, 12))
        slug = msg.replace(" ", "_").replace(".", "_")[:40]
        d.kv("Path", f"{root}/versions/{rev}_{slug}.py")
        d.blank()
        d.skip(f"    {msg}")
        d.blank()
        d.kv("Revision ID", rev, indent="    ")
        if parent == "<base>":
            d.line("    Revises: ", "kv", ["Revises"])
        else:
            d.kv("Revises", parent, indent="    ")
        d.kv("Create Date", fake.date(rng, "datetime") + f".{rng.randint(0, 999999):06d}", indent="    ")
        d.blank()
    return d
