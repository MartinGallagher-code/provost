"""Subversion `svnlook tree REPOS [PATH] [--show-ids | --full-paths]`: an
indented directory tree (one space per level), or full paths."""
from lib import Doc, fake

TOOL = "svnlook-tree"

DIRS = ["trunk", "branches", "tags", "src", "lib", "docs", "tests", "include", "vendor", "tools",
        "release-1.0", "release-2.0", "feature-login", "assets", "scripts"]
FILES = ["README", "Makefile", "main.c", "util.c", "util.h", "index.html", "setup.py", "LICENSE",
         "CHANGES.txt", "config.yaml", "build.xml", "app.js", "very_long_generated_parser_tables.c"]


def generate(rng):
    d = Doc()
    mode = rng.choice(["indent", "indent", "ids", "full"])
    rev = rng.randint(1, 9000)
    entries = [("", "/", True, -1)]

    def walk(prefix, depth):
        if depth > 3:
            return
        for name in rng.sample(DIRS, rng.randint(1, 4) if depth == 0 else rng.randint(0, 3 if depth < 2 else 1)):
            entries.append((prefix + name + "/", name + "/", True, depth))
            walk(prefix + name + "/", depth + 1)
        for name in rng.sample(FILES, rng.randint(0, 4)):
            entries.append((prefix + name, name, False, depth))

    walk("", 0)
    if len(entries) < 3:
        entries.append(("README", "README", False, 0))
    for full, name, isdir, depth in entries:
        if mode == "full":
            p = full or "/"
            d.line(p, "row", [p])
            continue
        ind = " " * (depth + 1)
        if mode == "ids":
            nid = f"<{rng.randint(0, 99)}.0.r{rng.randint(1, rev)}/{rng.randint(1, 99999)}>"
            if rng.random() < .3:
                nid = f"<{fake.token(rng, 2)}.0.r{rng.randint(1, rev)}/{rng.randint(1, 99999)}>"
            d.line(f"{ind}{name} {nid}", "row", [name, nid])
        else:
            d.line(ind + name, "row", [name])
    return d
