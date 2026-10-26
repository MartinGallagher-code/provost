"""`rails db:migrate:status`: per database a `database: name` line, a
centered Status column, 14-digit migration ids and names, with
`********** NO FILE **********` for orphaned versions."""
from lib import Doc, fake

TOOL = "rails-db-migrate-status"

NAMES = ["Create users", "Add email to users", "Devise create users", "Create active storage tables.active storage",
         "Create orders", "Add index to orders user", "Create products", "Add price cents to products",
         "Remove legacy columns from accounts", "Create friendly id slugs", "Add confirmable to devise",
         "Create action text tables.action text", "Change column default for status", "Create solid queue tables",
         "Add tenant id to everything", "Backfill order totals", "Create noticed notifications"]


def generate(rng):
    d = Doc()
    app = rng.choice(["myapp", "storefront", "billing", "acme_crm", "blog"])
    env = rng.choice(["development", "production", "test"])
    dbs = [f"{app}_{env}"] if rng.random() < .75 else [f"{app}_{env}", f"{app}_{env}_{rng.choice(['queue', 'cache', 'animals', 'analytics'])}"]
    if rng.random() < .2:
        dbs = [f"db/{env}.sqlite3"]
    for db in dbs:
        d.blank()
        d.kv("database", db)
        d.blank()
        d.line(f"{'Status'.center(8)}  {'Migration ID'.ljust(14)}  Migration Name", "header",
               ["Status", "Migration ID", "Migration Name"])
        d.skip("-" * 50)
        n = rng.randint(1, 16)
        y = rng.randint(2014, 2024)
        stamps = sorted(f"{y + i // 5}{rng.randint(1, 12):02d}{rng.randint(1, 28):02d}{rng.randint(0, 23):02d}"
                        f"{rng.randint(0, 59):02d}{rng.randint(0, 59):02d}" for i in range(n))
        pending_from = n - rng.choice([0, 0, 0, 1, 2, 3])
        for i, st in enumerate(stamps):
            status = "down" if i >= pending_from else "up"
            name = rng.choice(NAMES) if rng.random() > .08 else "********** NO FILE **********"
            d.line(f"{status.center(8)}  {st.ljust(14)}  {name}", "row", [status, st, name])
    d.blank()
    return d
