"""audit `aulastlog` (lastlog rebuilt from the audit trail): a header, then
fixed-width user/port/from columns and the latest login time, with
`**Never logged in**` for accounts that never logged in."""
from lib import Doc, fake

TOOL = "aulastlog"

USERS = ["root", "bin", "daemon", "adm", "lp", "sync", "shutdown", "halt", "mail", "operator", "games", "ftp",
         "nobody", "dbus", "systemd-coredump", "systemd-resolve", "tss", "polkitd", "sssd", "chrony", "sshd",
         "rngd", "alice", "bob", "carol", "deploy", "jsmith", "m.garcia", "svc-backup", "ansible"]


def generate(rng):
    d = Doc()
    if rng.random() < .3:
        users = [rng.choice(USERS[22:])]
        if rng.random() < .5:
            users.append(rng.choice(USERS[:22]))
    else:
        users = USERS[:rng.randint(6, len(USERS))]
    d.line(f"{'Username':<16} {'Port':<12} {'From':<26} Latest", "header", ["Username", "Port", "From", "Latest"])
    for u in users:
        human = u in USERS[22:] or u == "root"
        if (human and rng.random() < .85) or rng.random() < .05:
            port = rng.choice([f"pts/{rng.randint(0, 9)}", f"tty{rng.randint(1, 6)}", "ssh", "/dev/pts/1", "console"])
            frm = None if port.startswith(("tty", "console")) else rng.choice(
                [fake.ip(rng), fake.host(rng), fake.ip(rng), "?", "localhost"])
            frm = frm[:26] if frm else frm
            latest = f"{rng.randint(1, 12):02d}/{rng.randint(1, 28):02d}/{rng.choice([25, 26])} " \
                     f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
        else:
            port, frm, latest = None, None, "**Never logged in**"
        d.line(f"{u:<16} {(port or ''):<12.12} {(frm or ''):<26.26} {latest}", "row", [u, port, frm, latest])
    return d
