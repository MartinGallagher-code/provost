"""Koyeb CLI `koyeb services list` (and -o wide style extra columns): an aligned
table with short hex IDs, multi-word STATUS / CREATED AT values, empty cells."""
from lib import Doc, fake

TOOL = "koyeb-services-list"


def generate(rng):
    d = Doc()
    wide = rng.random() < .35
    hdr = ["ID", "APP", "NAME", "TYPE", "STATUS", "CREATED AT"] + (["UPDATED AT", "ACTIVE DEPLOYMENT"] if wide else [])
    apps = [fake.name(rng) for _ in range(rng.randint(1, 4))]
    rows = []
    for _ in range(rng.randint(1, 10)):
        y, mo, dd = rng.randint(2022, 2026), rng.randint(1, 12), rng.randint(1, 28)
        created = f"{dd:02d} {['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][mo - 1]} {y % 100:02d} {fake.date(rng, 'time')[:5]} UTC"
        r = [fake.hexid(rng, 8), rng.choice(apps), rng.choice([fake.word(rng), fake.name(rng), "web", "api", "worker"]),
             rng.choice(["WEB", "WEB", "WORKER", "DATABASE"]),
             rng.choice(["HEALTHY", "HEALTHY", "HEALTHY", "DEGRADED", "UNHEALTHY", "STARTING", "PAUSED", "RESUMING", "DELETED"]),
             created]
        if wide:
            r += [rng.choice([fake.ago(rng), created]), rng.choice([fake.hexid(rng, 8), "", fake.hexid(rng, 8)])]
        rows.append(r)
    d.table(hdr, rows, gap=rng.choice([1, 2, 3]))
    return d
