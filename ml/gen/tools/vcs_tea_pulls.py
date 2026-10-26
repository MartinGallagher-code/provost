"""Gitea's `tea pulls list` (table output): a +---+ boxed table with a
centred upper-case header and pipe-separated cells."""
from lib import Doc, fake

TOOL = "tea-pulls"

TITLES = ["Fix CI on arm64", "Add dark mode", "WIP: migrate to tokio 1.x", "Update README.md",
          "chore(deps): bump golang.org/x/net from 0.17.0 to 0.23.0", "Refactor auth middleware",
          "docs: typo", "feat: support SSH certificates for push"]


def generate(rng):
    d = Doc()
    cols = ["INDEX", "TITLE", "STATE", "AUTHOR"]
    extra = [c for c in ["MILESTONE", "UPDATED", "LABELS", "MERGEABLE"] if rng.random() < .45]
    cols += extra
    rows = []
    idx = rng.randint(5, 3000)
    for _ in range(rng.randint(0, 10)):
        idx -= rng.randint(1, 30)
        r = {"INDEX": str(idx), "TITLE": rng.choice(TITLES), "STATE": rng.choice(["open", "open", "closed", "merged"]),
             "AUTHOR": fake.user(rng),
             "MILESTONE": rng.choice(["", "", f"v{fake.version(rng)}", "1.0"]),
             "UPDATED": fake.date(rng, "datetime"),
             "LABELS": rng.choice(["", "bug", "enhancement", "kind/docs,size/S"]),
             "MERGEABLE": rng.choice(["true", "false"])}
        rows.append([r[c] or None for c in cols])
    w = [max([len(c)] + [len(r[i] or "") for r in rows]) for i, c in enumerate(cols)]
    rule = "+" + "+".join("-" * (x + 2) for x in w) + "+"
    d.skip(rule)
    d.line("|" + "|".join(" " + c.center(w[i]) + " " for i, c in enumerate(cols)) + "|", "header", cols)
    d.skip(rule)
    for r in rows:
        txt = "|" + "|".join(" " + ((r[i] or "").rjust(w[i]) if cols[i] == "INDEX" else (r[i] or "").ljust(w[i])) + " "
                             for i in range(len(cols))) + "|"
        d.line(txt, "row", r)
    d.skip(rule)
    return d
