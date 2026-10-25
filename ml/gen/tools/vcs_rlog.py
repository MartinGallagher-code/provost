"""RCS `rlog FILE`: a key/value header (RCS file, head, locks, symbolic
names, totals), a description, then dashed revision entries with a
`date: ...;  author: ...;  state: ...;  lines: ...` line and the log
message, closed by a rule of '='."""
from lib import Doc, fake

TOOL = "rlog"

MSGS = ["Initial revision", "fix off-by-one in buffer handling", "add usage message",
        "merge changes from branch", "*** empty log message ***", "update copyright",
        "rewrite the option parser so it handles long options like everyone else"]


def generate(rng):
    d = Doc()
    for fi in range(rng.randint(1, 2)):
        name = rng.choice(["main.c", "Makefile", "README", "notes.txt", "hosts", "util.sh", "config.h"])
        dir_ = rng.choice(["RCS/", "", "/etc/RCS/", "src/RCS/"])
        n = rng.randint(1, 6)
        head = f"1.{n}"
        if fi:
            d.blank()
        d.blank()
        d.kv("RCS file", f"{dir_}{name},v")
        d.kv("Working file", name)
        d.kv("head", head)
        d.skip("branch:")
        locker = fake.user(rng)
        if rng.random() < .4:
            d.kv("locks", "strict")
            d.line(f"\t{locker}: {head}", "kv", [locker, head])
        else:
            d.kv("locks", "strict")
        d.skip("access list:")
        names = [(f"REL_{rng.randint(0, 5)}_{rng.randint(0, 9)}", f"1.{rng.randint(1, n)}")
                 for _ in range(rng.choice([0, 0, 1, 2, 3]))]
        if names:
            d.section("symbolic names:")
            for t, r in names:
                d.line(f"\t{t}: {r}", "kv", [t, r])
        else:
            d.skip("symbolic names:")
        d.kv("keyword substitution", rng.choice(["kv", "kv", "b", "o"]))
        sel = n if rng.random() < .8 else rng.randint(1, n)
        d.line(f"total revisions: {n};\tselected revisions: {sel}", "row",
               ["total revisions", str(n), "selected revisions", str(sel)])
        d.section("description:")
        if rng.random() < .5:
            desc = rng.choice(["Main program.", "Host table for the lab network.", "build rules"])
            d.line(desc, "row", [desc])
        for k in range(sel):
            r = f"1.{n - k}"
            d.skip("-" * 28)
            if k == 0 and rng.random() < .3:
                d.line(f"revision {r}\tlocked by: {locker};", "row", ["revision", r, "locked by", locker])
            else:
                d.line(f"revision {r}", "kv", ["revision", r])
            date = fake.date(rng, "datetime").replace("-", "/")
            if rng.random() < .3:
                date = fake.date(rng, "datetime") + rng.choice(["+00", "-05", "+01"])
            who = fake.user(rng)
            st = rng.choice(["Exp", "Exp", "Rel", "Stab"])
            text = f"date: {date};  author: {who};  state: {st};"
            cells = ["date", date, "author", who, "state", st]
            if n - k > 1:
                lines_ = f"+{rng.randint(0, 200)} -{rng.randint(0, 80)}"
                text += f"  lines: {lines_}"
                cells += ["lines", lines_]
            d.line(text, "row", cells)
            if rng.random() < .1:
                br = f"1.{n - k}.1"
                d.line(f"branches:  {br};", "kv", ["branches", br])
            msg = "Initial revision" if n - k == 1 else rng.choice(MSGS)
            d.line(msg, "row", [msg])
        d.skip("=" * 77)
    return d
