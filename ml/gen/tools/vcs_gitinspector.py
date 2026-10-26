"""`gitinspector` text report: prose banners introducing fixed-width tables
(commits by author, surviving rows by author), plus optional extension and
timeline/metrics sections."""
from lib import Doc, fake

TOOL = "gitinspector"

AUTHORS = ["Alice Smith", "Bob", "Carol Wu", "Dave O'Brien", "Erin Kowalski-Nakamura", "Frank Li",
           "dependabot[bot]", "Grace", "Heidi Schmidt", "root"]


def generate(rng):
    d = Doc()
    repo = fake.name(rng)
    when = fake.date(rng, "date").replace("-", "/")
    d.skip(f"Statistical information for the repository '{repo}' was gathered on {when}.")
    if rng.random() < .5:
        d.skip("The extensions below were found in the repository history")
        d.skip("(extensions used during statistical analysis are marked):")
        exts = rng.sample(["c", "h", "py", "md", "txt", "js", "json", "yml", "sh", "cpp", "java"], rng.randint(3, 8))
        d.skip(" ".join(f"[{e}]" if rng.random() < .6 else e for e in exts))
        d.blank()
    authors = rng.sample(AUTHORS, rng.randint(1, 7))
    d.skip("The following historical commit information, by author, was found:")
    d.blank()
    d.line("Author                     Commits    Insertions      Deletions    % of changes", "header",
           ["Author", "Commits", "Insertions", "Deletions", "% of changes"])
    stats = [(a, rng.randint(1, 900), rng.randint(0, 90000), rng.randint(0, 40000)) for a in authors]
    tot = sum(i + x for _, _, i, x in stats) or 1
    for a, c, i, x in stats:
        name = a[:26]
        cells = [name, str(c), str(i), str(x), f"{100 * (i + x) / tot:.2f}"]
        d.line(f"{name.ljust(27)}{cells[1]:>7}{cells[2]:>14}{cells[3]:>15}{cells[4]:>16}", "row", cells)
    d.blank()
    d.skip("Below are the number of rows from each author that have survived and are still "
           "intact in the current revision:")
    d.blank()
    d.line("Author                     Rows      Stability          Age       % in comments", "header",
           ["Author", "Rows", "Stability", "Age", "% in comments"])
    for a, c, i, x in stats:
        if rng.random() < .15:
            continue
        rows = rng.randint(0, min(max(i, 1), 9999))
        cells = [a[:26], str(rows), f"{100 * rows / max(i, 1):.1f}", f"{rng.uniform(0, 9):.1f}", f"{rng.uniform(0, 40):.2f}"]
        d.line(f"{cells[0].ljust(27)}{cells[1]:>4}{cells[2]:>15}{cells[3]:>13}{cells[4]:>20}", "row", cells)
    if rng.random() < .4:
        d.blank()
        d.skip("The following history timeline has been gathered from the repository:")
        d.blank()
        y = rng.randint(2015, 2025)
        periods = [f"{y}-{q:02d}" for q in sorted(rng.sample(range(1, 13), rng.randint(2, 6)))]
        d.line("Author".ljust(20) + "".join(p.rjust(10) for p in periods), "header", ["Author"] + periods)
        for a in authors:
            cells = [a[:19]] + [rng.choice(["", "-", "+", "-+", "++++", "---+++"]) or None for _ in periods]
            d.line((a[:19].ljust(20) + "".join((c or "").rjust(10) for c in cells[1:])).rstrip(), "row", cells)
        mods = " ".join(str(rng.randint(0, 9000)) for _ in periods)
        d.line("Modified Rows:".ljust(20) + "".join(m.rjust(10) for m in mods.split()), "row",
               ["Modified Rows:"] + mods.split())
    if rng.random() < .3:
        d.blank()
        d.section("The following files are suspiciously big (in order of severity):")
        for _ in range(rng.randint(1, 3)):
            p = fake.path(rng, "") + ".c"
            n = str(rng.randint(1000, 9000))
            d.line(f"{p} ({n} estimated lines of code)", "row", [p, n])
    return d
