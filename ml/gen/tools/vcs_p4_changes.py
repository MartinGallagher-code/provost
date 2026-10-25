"""Perforce `p4 changes [-t] [-l]`: one fixed-layout line per changelist,
`Change N on DATE by USER@CLIENT [*pending*] 'desc'`, or with -l the full
description on tab-indented lines below."""
from lib import Doc, fake

TOOL = "p4-changes"

DESCS = ["Fix the build on arm64", "Integrate //depot/main to //depot/rel-2.4",
         "Update copyright headers", "Add retry logic to the uploader", "Revert CL 4411",
         "Bump protobuf to 3.21", "WIP: shader cache", "Remove dead code in the parser",
         "Merge down from dev", "Tweak logging levels in the asset pipeline for release builds"]


def generate(rng):
    d = Doc()
    times = rng.random() < .4
    long_ = rng.random() < .3
    cl = rng.randint(1000, 2000000)
    for _ in range(rng.randint(2, 12)):
        cl -= rng.randint(1, 400)
        date = fake.date(rng, "date").replace("-", "/")
        if times:
            date += " " + fake.date(rng, "time")
        who = f"{fake.user(rng)}@{fake.user(rng)}-{rng.choice(['ws', 'main', 'laptop', 'build'])}"
        pending = rng.random() < .2
        desc = rng.choice(DESCS)
        head = f"Change {cl} on {date} by {who}"
        cells = [str(cl), date, who]
        if pending:
            head += " *pending*"
        if long_:
            d.line(head, "row", cells + ["*pending*" if pending else None])
            d.blank()
            for k in range(rng.randint(1, 3)):
                text = desc if k == 0 else rng.choice(DESCS)
                d.line("\t" + text, "cont", [text])
            d.blank()
        else:
            short = desc[:31] + " " if len(desc) <= 31 else desc[:31]
            q = f"'{short}'"
            d.line(f"{head} {q}", "row", cells + ["*pending*" if pending else None, q])
    return d
