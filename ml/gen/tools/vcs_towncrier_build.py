"""`towncrier build --draft`: progress lines, then the rendered changelog
draft: a version heading, category sections and bullet entries with issue
references (reStructuredText or Markdown flavour)."""
from lib import Doc, fake

TOOL = "towncrier-build"

CATS = ["Features", "Bugfixes", "Improved Documentation", "Deprecations and Removals", "Misc",
        "Trivial/Internal Changes", "Breaking Changes"]
ENTRIES = ["Added support for Python 3.13.", "Fixed a crash when the config file is empty.",
           "The ``--quiet`` flag now silences warnings too.", "Dropped support for Python 3.8.",
           "Documented the plugin API.", "Improved performance of the resolver by caching lookups.",
           "Renamed ``foo`` to ``bar``; the old name still works but warns.",
           "Fixed handling of non-UTF-8 filenames on Windows when extracting archives."]


def generate(rng):
    d = Doc()
    md = rng.random() < .35
    proj = fake.name(rng)
    ver = fake.version(rng)
    date = fake.date(rng, "date")
    if rng.random() < .85:
        d.skip("Loading template...")
        d.skip("Finding news fragments...")
        d.skip("Rendering news fragments...")
        d.skip("Draft only -- nothing has been written.")
        d.skip("What is seen below is what would be written.")
        d.blank()
    title = f"{proj} {ver} ({date})" if rng.random() < .8 else f"{ver} ({date})"
    if md:
        d.section("## " + title, title)
    else:
        d.section(title)
        d.skip("=" * len(title))
    d.blank()
    for cat in rng.sample(CATS, rng.randint(1, 4)):
        if md:
            d.section("### " + cat, cat)
        else:
            d.section(cat)
            d.skip("-" * len(cat))
        d.blank()
        issues = lambda: [str(rng.randint(1, 3000)) for _ in range(rng.choice([1, 1, 1, 2]))]
        if cat in ("Misc", "Trivial/Internal Changes"):
            refs = ", ".join(f"#{i}" for i in issues() + issues())
            d.line("- " + refs, "row", [refs])
        else:
            for _ in range(rng.randint(1, 5)):
                e = rng.choice(ENTRIES)
                if md:
                    ref = "(" + ", ".join(f"[#{i}](https://github.com/{proj}/issues/{i})" for i in issues()) + ")"
                else:
                    ref = "(" + ", ".join(f"#{i}" for i in issues()) + ")"
                d.line(f"- {e} {ref}", "row", [e, ref])
        d.blank()
        if not md:
            d.blank()
    return d
