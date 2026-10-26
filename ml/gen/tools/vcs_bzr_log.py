"""Bazaar `bzr log` (long format): dashed rules between revisions, key/value
headers, an indented message block, optional -v file lists and nested merges."""
from lib import Doc, fake

TOOL = "bzr-log"

NAMES = ["Alice Smith", "Bob Jones", "Carol Wu", "Dave O'Brien", "Erin Kowalski", "Frank Li",
         "Grace Hopper-Bailey", "Ian"]
MSGS = ["Fix crash when the branch has no revisions", "Merge trunk", "Add --dry-run option",
        "Update translations", "Refactor transport layer to use the new API",
        "Tidy up imports", "Release 2.6.0", "Document the plugin hooks",
        "Handle EINTR in the smart server", "Bump version", "Don't follow symlinks outside the tree"]
DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()


def stamp(rng):
    d = fake.date(rng, "datetime")
    return f"{rng.choice(DAYS)} {d} {rng.choice(['+0000', '+0100', '-0500', '+0530', '+0200'])}"


def person(rng):
    n = rng.choice(NAMES)
    mail = n.split()[0].lower().replace("'", "") + "@" + rng.choice(["example.com", "canonical.com", "lists.lan"])
    return f"{n} <{mail}>"


def revision(d, rng, revno, ind, verbose, show_ids, depth):
    rule = "-" * 60
    d.skip(ind + rule)
    merge = rng.random() < .2 and depth == 0
    if merge:
        d.line(f"{ind}revno: {revno} [merge]", "kv", ["revno", revno, "[merge]"])
    else:
        d.kv("revno", revno, indent=ind)
    if show_ids:
        d.kv("revision-id", f"{rng.choice(NAMES).split()[0].lower()}@example.com-"
             f"{rng.randint(2010, 2024)}{rng.randint(1, 12):02d}{rng.randint(1, 28):02d}"
             f"{rng.randint(0, 235959):06d}-{fake.token(rng, 16)}", indent=ind)
    if rng.random() < .15:
        d.kv("tags", f"bzr-{fake.version(rng)}", indent=ind)
    d.kv("committer", person(rng), indent=ind)
    if rng.random() < .25:
        d.kv("author", person(rng), indent=ind)
    d.kv("branch nick", rng.choice(["trunk", "2.6", "dev", "fix-" + fake.word(rng), "bzr.dev"]), indent=ind)
    d.kv("timestamp", stamp(rng), indent=ind)
    if rng.random() < .1:
        d.kv("fixes bugs", f"https://launchpad.net/bugs/{rng.randint(100000, 2000000)}", indent=ind)
    d.section(ind + "message:")
    for _ in range(rng.choice([1, 1, 1, 2, 3])):
        m = rng.choice(MSGS)
        d.line(ind + "  " + m, "row", [m])
    if verbose:
        for kind in rng.sample(["added:", "modified:", "removed:", "renamed:"], rng.randint(1, 2)):
            d.section(ind + kind)
            for _ in range(rng.randint(1, 4)):
                p = fake.path(rng, "")[:] + rng.choice([".py", ".txt", "/", ".c"])
                if kind == "renamed:":
                    q = fake.path(rng, "") + ".py"
                    d.line(f"{ind}  {p} => {q}", "row", [p, q])
                else:
                    d.line(f"{ind}  {p}", "row", [p])
    return merge


def generate(rng):
    d = Doc()
    verbose = rng.random() < .3
    show_ids = rng.random() < .2
    top = rng.randint(5, 3000)
    for i in range(rng.randint(1, 5)):
        revno = str(top - i)
        if revision(d, rng, revno, "", verbose, show_ids, 0):
            for j in range(rng.randint(1, 2)):
                revision(d, rng, f"{int(revno) - 1}.{rng.randint(1, 9)}.{j + 1}", "    ",
                         verbose, show_ids, 1)
    if rng.random() < .2:
        d.line("Use --include-merged or -n0 to see merged revisions.", "skip")
    return d
