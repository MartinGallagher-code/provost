"""Gerrit `ssh -p 29418 host gerrit query` (TEXT format): one `change <Id>`
block per change with nested key: value fields, then a stats block."""
from lib import Doc, fake

TOOL = "gerrit-query"

SUBJ = ["Fix NPE in ChangeNotes", "Add REST endpoint for project labels", "Bump Bazel to 6.2",
        "Revert \"Use new index schema\"", "Document the replication plugin config",
        "Make submit rule evaluation lazy", "WIP: rework the dashboard"]
PEOPLE = [("John Doe", "jdoe"), ("Alice Smith", "asmith"), ("Bob", "bob"), ("Chen Wei", "cwei"),
          ("Jenkins CI", "jenkins")]


def stamp(rng):
    return fake.date(rng, "datetime") + " " + rng.choice(["UTC", "PST", "CET"])


def person(d, rng, title, ind):
    d.section(ind + title + ":")
    n, u = rng.choice(PEOPLE)
    d.kv("name", n, indent=ind + "  ")
    if rng.random() < .9:
        d.kv("email", f"{u}@example.com", indent=ind + "  ")
    d.kv("username", u, indent=ind + "  ")


def generate(rng):
    d = Doc()
    host = rng.choice(["review.example.com", "gerrit.lan", "review.opendev.org"])
    n = rng.choice([0, 1, 1, 2, 2, 3, 4])
    for _ in range(n):
        cid = "I" + fake.hexid(rng, 40)
        num = str(rng.randint(100, 900000))
        d.kv("change", cid, sep=" ")
        d.kv("project", rng.choice(["tools/gerrit", "platform/build", "infra/ansible", fake.name(rng)]), indent="  ")
        d.kv("branch", rng.choice(["master", "main", "stable-3.8", "refs/meta/config"]), indent="  ")
        if rng.random() < .4:
            d.kv("topic", fake.name(rng), indent="  ")
        d.kv("id", cid, indent="  ")
        d.kv("number", num, indent="  ")
        d.kv("subject", rng.choice(SUBJ), indent="  ")
        person(d, rng, "owner", "  ")
        d.kv("url", f"https://{host}/c/{num}", indent="  ")
        if rng.random() < .3:
            d.kv("hashtags", f"[{fake.word(rng)}]", indent="  ")
        d.kv("createdOn", stamp(rng), indent="  ")
        d.kv("lastUpdated", stamp(rng), indent="  ")
        st = rng.choice(["NEW", "NEW", "MERGED", "ABANDONED"])
        d.kv("open", "true" if st == "NEW" else "false", indent="  ")
        d.kv("status", st, indent="  ")
        if rng.random() < .4:
            d.section("  currentPatchSet:")
            d.kv("number", str(rng.randint(1, 30)), indent="    ")
            d.kv("revision", fake.hexid(rng, 40), indent="    ")
            d.kv("ref", f"refs/changes/{num[-2:]}/{num}/{rng.randint(1, 30)}", indent="    ")
            person(d, rng, "uploader", "    ")
            d.kv("createdOn", stamp(rng), indent="    ")
            if rng.random() < .6:
                d.section("    approvals:")
                for _ in range(rng.randint(1, 3)):
                    d.kv("type", rng.choice(["Code-Review", "Verified", "Workflow"]), indent="      ")
                    d.kv("value", rng.choice(["-2", "-1", "1", "2"]), indent="      ")
                    d.kv("grantedOn", stamp(rng), indent="      ")
            d.kv("sizeInsertions", str(rng.randint(0, 900)), indent="    ")
            d.kv("sizeDeletions", str(-rng.randint(0, 300)), indent="    ")
        d.blank()
    d.kv("type", "stats")
    d.kv("rowCount", str(n))
    d.kv("runTimeMilliseconds", str(rng.randint(1, 4000)))
    if rng.random() < .7:
        d.kv("moreChanges", rng.choice(["true", "false"]))
    return d
