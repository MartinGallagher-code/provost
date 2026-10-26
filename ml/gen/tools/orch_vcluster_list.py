"""`vcluster list`: a borderless tablewriter table, two-space indent, `|`
between columns, centred upper-case header and a `---+---` rule; columns
vary by release (VERSION, CREATED, DISTRO)."""
from lib import Doc, fake

TOOL = "vcluster-list"


def generate(rng):
    d = Doc()
    era = rng.choice(["old", "mid", "new"])
    header = {"old": ["NAME", "NAMESPACE", "STATUS", "CONNECTED", "CREATED", "AGE"],
              "mid": ["NAME", "NAMESPACE", "STATUS", "VERSION", "CONNECTED", "CREATED", "AGE", "DISTRO"],
              "new": ["NAME", "NAMESPACE", "STATUS", "VERSION", "CONNECTED", "AGE"]}[era]
    if era == "new" and rng.random() < .4:
        header = ["NAME", "NAMESPACE", "STATUS", "VERSION", "CONNECTED", "AGE", "PRO"]
    tz = rng.choice([("+0000", "UTC"), ("+0200", "CEST"), ("-0700", "PDT"), ("+0100", "CET"), ("+0530", "IST")])
    rows = []
    conn = rng.randrange(6)
    for i in range(rng.randint(0, 6)):
        name = rng.choice(["my-vcluster", "vcluster", "dev-" + fake.word(rng), fake.name(rng), "team-" + fake.word(rng),
                           "pr-" + fake.num(rng, 100, 9999) + "-preview"])
        vals = {"NAME": name,
                "NAMESPACE": rng.choice(["vcluster-" + name, "vcluster", "team-" + fake.word(rng), "default"]),
                "STATUS": rng.choice(["Running", "Running", "Running", "Paused", "Pending", "Unknown", "Failed"]),
                "VERSION": rng.choice(["0.15.0", "0.19.5", "0.20.0", "0.21.1", "0.20.0-beta.6", "0.23.0"]),
                "CONNECTED": rng.choice(["True", ""]) if i == conn else ("" if era != "old" else "False") if rng.random() < .7 else "False",
                "CREATED": f"{fake.date(rng, 'datetime')} {tz[0]} {tz[1]}",
                "AGE": rng.choice([f"{rng.randint(1, 59)}m{rng.randint(0, 59)}s", f"{rng.randint(1, 23)}h{rng.randint(0, 59)}m",
                                   f"{rng.randint(1, 400)}d", f"{rng.randint(1, 59)}s", f"{rng.randint(1, 30)}d{rng.randint(0, 23)}h"]),
                "DISTRO": rng.choice(["OSS", "OSS", "k3s", "k8s", "k0s", "eks"]),
                "PRO": rng.choice(["False", "False", "True"])}
        rows.append([vals[h] for h in header])
    ncol = len(header)
    w = [max(len(x) for x in [header[c]] + [r[c] for r in rows]) for c in range(ncol)]
    if rng.random() < .3:
        d.blank()
    d.line("  " + " | ".join(header[c].center(w[c]) for c in range(ncol)).rstrip(), "header", header)
    d.skip("  " + "-+-".join("-" * w[c] for c in range(ncol)))
    for r in rows:
        d.line("  " + " | ".join(r[c].ljust(w[c]) for c in range(ncol)).rstrip(), "row", [v if v else None for v in r])
    if rng.random() < .3:
        d.blank()
    return d
