"""`gita ll`: one line per registered repo, name, branch, status symbols
(+ staged, * unstaged, ? untracked, $ stash, ↑/↓ ahead/behind) and the last
commit subject, aligned into columns with no header."""
from lib import Doc, fake

TOOL = "gita-ll"

SUBJ = ["fix typo in README", "Merge pull request #412 from alice/feature", "wip",
        "bump deps", "add tests for the parser", "Initial commit", "refactor: split config module",
        "release v2.3.1", "docs: explain the sync flags in more detail than anyone needs"]


def generate(rng):
    d = Doc()
    rows = []
    for _ in range(rng.randint(2, 14)):
        name = fake.name(rng) if rng.random() < .6 else fake.word(rng)
        branch = rng.choice(["master", "main", "dev", "develop", f"feat/{fake.word(rng)}", "gh-pages",
                             f"fix-{rng.randint(1, 999)}"])
        sym = "".join(s for s in "+*?$" if rng.random() < .25)
        if rng.random() < .15:
            sym = rng.choice(["↑", "↓", "⇕"]) + sym
        rows.append([name, branch, sym or None, rng.choice(SUBJ)])
    w = [max(len(r[c] or "") for r in rows) for c in range(3)]
    for r in rows:
        text = r[0].ljust(w[0]) + " " + r[1].ljust(w[1]) + " " + (r[2] or "").ljust(w[2]) + " " + r[3]
        d.line(text, "row", r)
    return d
