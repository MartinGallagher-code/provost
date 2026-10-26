"""FreeIPA `ipa user-find` / `ipa sudorule-find` / `ipa hbacrule-find`:
a dashed `N ... matched` banner, two-space-indented `Key: value` blocks per
entry separated by blank lines, and a `Number of entries returned N` footer."""
from lib import Doc, fake

TOOL = "ipa"


def banner(d, text):
    d.skip("-" * len(text))
    d.skip(text)
    d.skip("-" * len(text))


def user(rng, realm):
    login = rng.choice(["admin", "alice", "bob", "carol", "jsmith", "m.garcia", "svc-backup", "dave", "erin"])
    first, last = login.capitalize(), rng.choice(["Administrator", "Smith", "Garcia", "Nguyen", "Okafor", "Kowalski"])
    uid = str(rng.randint(1185200000, 1185299999))
    pairs = [("User login", login)]
    if login != "admin":
        pairs.append(("First name", first))
    pairs += [("Last name", last), ("Home directory", f"/home/{login}"), ("Login shell", rng.choice(["/bin/bash", "/bin/sh", "/bin/zsh"])),
              ("Principal name" if rng.random() < .5 else "Principal alias", f"{login}@{realm}")]
    if rng.random() < .6:
        pairs.append(("Email address", f"{login}@{realm.lower()}"))
    pairs += [("UID", uid), ("GID", uid if rng.random() < .8 else str(rng.randint(1185200000, 1185299999))),
              ("Account disabled", rng.choice(["False", "False", "False", "True"]))]
    return pairs


def sudorule(rng, realm):
    name = rng.choice(["allow_systemctl", "ops_all", "dba_postgres", "readonly_logs", "web_restart", "audit_tools"])
    pairs = [("Rule name", name), ("Enabled", rng.choice(["True", "True", "False"]))]
    if rng.random() < .5:
        pairs.append(("Description", rng.choice(["Let ops restart services", "DBA access", "log readers"])))
    if rng.random() < .4:
        pairs.append(("User category", "all"))
    else:
        pairs.append(("User Groups", ", ".join(rng.sample(["admins", "ops", "dba", "sre", "webadmins"], rng.randint(1, 3)))))
    if rng.random() < .5:
        pairs.append(("Host category", "all"))
    else:
        pairs.append(("Hosts", ", ".join(f"{fake.word(rng)}-{rng.randint(1, 9):02d}.{realm.lower()}" for _ in range(rng.randint(1, 3)))))
    if rng.random() < .3:
        pairs.append(("Command category", "all"))
    else:
        pairs.append(("Sudo Allow Commands", ", ".join(rng.sample(["/usr/bin/systemctl", "/usr/bin/journalctl",
                                                                    "/usr/sbin/ausearch", "/usr/bin/tail", "/usr/bin/psql"], rng.randint(1, 3)))))
    if rng.random() < .6:
        pairs.append(("RunAs User category", "all"))
    if rng.random() < .3:
        pairs.append(("Sudo Option", "!authenticate"))
    return pairs


def hbacrule(rng, realm):
    name = rng.choice(["allow_all", "allow_systemd-user", "ssh_admins", "web_ops", "db_access"])
    pairs = [("Rule name", name)]
    if name == "allow_all":
        pairs += [("User category", "all"), ("Host category", "all"), ("Service category", "all"),
                  ("Description", "Allow all users to access any host from any host")]
    else:
        pairs += [("User Groups", rng.choice(["admins", "ops, sre", "dba"])),
                  ("Host Groups", rng.choice(["webservers", "dbservers", "all-linux"])),
                  ("HBAC Services", rng.choice(["sshd", "sshd, sudo", "systemd-user", "login"]))]
    pairs.append(("Enabled", rng.choice(["True", "True", "False"])))
    return pairs


def generate(rng):
    d = Doc()
    realm = rng.choice(["EXAMPLE.COM", "IPA.INTERNAL", "LAB.TEST", "CORP.ACME.ORG"])
    kind, noun = rng.choice([(user, "user"), (user, "user"), (sudorule, "Sudo Rule"), (hbacrule, "HBAC rule")])
    n = rng.randint(1, 6)
    entries, seen = [], set()
    for _ in range(n * 3):
        p = kind(rng, realm)
        if p[0][1] not in seen:
            seen.add(p[0][1])
            entries.append(p)
        if len(entries) == n:
            break
    n = len(entries)
    banner(d, f"{n} {noun}{'s' if n != 1 else ''} matched")
    for i, pairs in enumerate(entries):
        if i:
            d.blank()
        for k, v in pairs:
            d.line(f"  {k}: {v}", "kv", [k, v])
    foot = f"Number of entries returned {n}"
    d.skip("-" * len(foot))
    d.line(foot, "kv", ["Number of entries returned", str(n)])
    d.skip("-" * len(foot))
    return d
