"""systemd `userdbctl user` / `userdbctl group`: an upper-case header,
single-space-separated columns with right-aligned IDs, and an `N users
listed.` footer."""
from lib import Doc, fake

TOOL = "userdbctl"

SYSUSERS = [("root", "intrinsic", 0, "Super User", "/root", "/bin/bash"),
            ("bin", "system", 1, "bin", "/bin", "/usr/sbin/nologin"),
            ("daemon", "system", 2, "daemon", "/usr/sbin", "/usr/sbin/nologin"),
            ("mail", "system", 8, "mail", "/var/mail", "/usr/sbin/nologin"),
            ("www-data", "system", 33, "www-data", "/var/www", "/usr/sbin/nologin"),
            ("systemd-network", "system", 998, "systemd Network Management", "/", "/usr/sbin/nologin"),
            ("systemd-timesync", "system", 997, "systemd Time Synchronization", "/", "/usr/sbin/nologin"),
            ("systemd-resolve", "system", 996, "systemd Resolver", "/", "/usr/sbin/nologin"),
            ("messagebus", "system", 101, "", "/nonexistent", "/usr/sbin/nologin"),
            ("sshd", "system", 105, "", "/run/sshd", "/usr/sbin/nologin"),
            ("polkitd", "system", 994, "polkit", "/", "/usr/sbin/nologin"),
            ("postgres", "system", 113, "PostgreSQL administrator", "/var/lib/postgresql", "/bin/bash"),
            ("systemd-coredump", "dynamic", 61183, "systemd Core Dumper", "/", "/usr/sbin/nologin"),
            ("systemd-oom", "system", 993, "systemd Userspace OOM Killer", "/", "/usr/sbin/nologin"),
            ("nobody", "intrinsic", 65534, "Kernel Overflow User", "/", "/usr/sbin/nologin")]
PEOPLE = ["alice", "bob", "carol", "dave", "erin", "mgallagher", "jdoe", "testuser", "deploy", "kiosk"]


def generate(rng):
    d = Doc()
    group = rng.random() < 0.35
    dash = rng.random() < 0.5
    ents = rng.sample(SYSUSERS, rng.randint(2, len(SYSUSERS)))
    for i, p in enumerate(rng.sample(PEOPLE, rng.randint(0, 4))):
        real = p.capitalize() + " " + rng.choice(["Smith", "Jones", "O'Brien", "van der Berg", "Example", ""])
        ents.append((p, "regular", 1000 + i + rng.choice([0, 0, 100]), real.strip(), f"/home/{p}", rng.choice(
            ["/bin/bash", "/bin/zsh", "/usr/bin/fish", "/bin/sh"])))
    ents.sort(key=lambda e: e[2])
    if group:
        hdr = ["NAME", "DISPOSITION", "GID", "DESCRIPTION"]
        rows = [[n, disp, str(i), (desc if desc else ("-" if dash else None))] for n, disp, i, desc, _, _ in ents]
        right = (2,)
    else:
        hdr = ["NAME", "DISPOSITION", "UID", "GID", "REALNAME", "HOME", "SHELL"]
        rows = [[n, disp, str(i), str(i), (rn if rn else ("-" if dash else None)), home, sh]
                for n, disp, i, rn, home, sh in ents]
        right = (2, 3)
    if rng.random() < 0.4:
        lo = rng.choice([1000, 60001, 524288])
        hi = {1000: 60000, 60001: 60513, 524288: 1879048191}[lo]
        what = {1000: "regular", 60001: "dynamic", 524288: "container"}[lo]
        row = ([f"<{what}>", what, str(lo), "-"] if group else
               [f"<{what}>", what, str(lo), str(lo), "-", "-", "-"])
        rows.insert(len([r for r in rows if int(r[2]) < lo]), row)
    d.table(hdr, rows, gap=1, right=right)
    if rng.random() < 0.85:
        d.blank()
        n = len(rows)
        d.skip(f"{n} {'groups' if group else 'users'} listed.")
    return d
