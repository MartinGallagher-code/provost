"""CVS `cvs status [-v]`: one block per file, ruled with '=', a File/Status
line, tab-separated revision fields, and (with -v) an Existing Tags list."""
from lib import Doc, fake

TOOL = "cvs-status"

STATUSES = ["Up-to-date", "Up-to-date", "Locally Modified", "Needs Patch", "Needs Checkout",
            "Locally Added", "Needs Merge", "Unknown", "File had conflicts on merge"]


def rev(rng):
    r = f"1.{rng.randint(1, 140)}"
    if rng.random() < .15:
        r += f".2.{rng.randint(1, 9)}"
    return r


def generate(rng):
    d = Doc()
    module = rng.choice(["proj", "webapp", "libfoo", "tools", "src/kernel"])
    cvsroot = rng.choice(["/cvsroot", "/usr/local/cvs", "/var/lib/cvs", "/home/cvs/repo"])
    tags_mode = rng.random() < .4
    for _ in range(rng.randint(1, 5)):
        sub = rng.choice(["", "src/", "lib/", "doc/", "tests/unit/"])
        if sub and rng.random() < .3:
            d.line(f"cvs status: Examining {sub.rstrip('/')}", "skip")
        fname = rng.choice(["main.c", "Makefile", "README", "util.h", "config.in", "parser.y",
                            "ChangeLog", "build-all-the-things.sh"])
        st = rng.choice(STATUSES)
        d.skip("=" * 67)
        sp = "\t" * rng.choice([1, 2, 3])
        d.line(f"File: {fname}{sp}Status: {st}", "row", ["File", fname, "Status", st])
        d.blank()
        w = rev(rng)
        if st == "Unknown":
            d.line("   Working revision:\tNo entry for " + fname, "kv", ["Working revision", "No entry for " + fname])
            d.line("   Repository revision:\tNo revision control file", "kv",
                   ["Repository revision", "No revision control file"])
        else:
            wr = "New file!" if st == "Locally Added" else w
            if st == "Locally Added":
                d.line(f"   Working revision:\t{wr}", "kv", ["Working revision", wr])
                d.line("   Repository revision:\tNo revision control file", "kv",
                       ["Repository revision", "No revision control file"])
            else:
                d.line(f"   Working revision:\t{wr}", "kv", ["Working revision", wr])
                rr = w if st in ("Up-to-date", "Locally Modified") else rev(rng)
                path = f"{cvsroot}/{module}/{sub}{fname},v"
                d.line(f"   Repository revision:\t{rr}\t{path}", "kv", ["Repository revision", rr, path])
                if rng.random() < .5:
                    cid = fake.token(rng, 16)
                    d.line(f"   Commit Identifier:\t{cid}", "kv", ["Commit Identifier", cid])
        for k in ("Sticky Tag", "Sticky Date", "Sticky Options"):
            v = "(none)"
            if k == "Sticky Tag" and rng.random() < .2:
                v = f"RELENG_{rng.randint(1, 9)}_{rng.randint(0, 9)} (branch: {w}.2)"
            if k == "Sticky Options" and rng.random() < .15:
                v = "-kb"
            tabs = "\t\t" if k != "Sticky Options" else "\t"
            d.line(f"   {k}:{tabs}{v}", "kv", [k, v])
        if tags_mode:
            d.blank()
            d.section("   Existing Tags:")
            ntag = rng.randint(0, 5)
            if not ntag:
                d.line("\tNo Tags Exist", "skip")
            for _ in range(ntag):
                t = rng.choice(["REL_", "RELENG_", "BETA_", "start", "vendor"]) + (
                    f"{rng.randint(0, 4)}_{rng.randint(0, 20)}" if rng.random() < .7 else "")
                kind = "branch" if rng.random() < .3 else "revision"
                rv = f"{rev(rng)}.2" if kind == "branch" else rev(rng)
                d.line(f"\t{t.ljust(25)}\t({kind}: {rv})", "row", [t, kind, rv])
        d.blank()
    return d
