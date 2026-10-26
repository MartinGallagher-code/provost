"""shadow-utils `faillog -a` / `faillog -u user`: a fixed header
(Login / Failures / Maximum / Latest / On), a blank line, then one record
per account with right-aligned counters and an optional terminal."""
from lib import Doc, fake

TOOL = "faillog"


def generate(rng):
    d = Doc()
    d.line("Login       Failures Maximum Latest                   On", "header",
           ["Login", "Failures", "Maximum", "Latest", "On"])
    d.blank()
    users = ["root", "daemon", "bin", "sys", "sync", "games", "man", "lp", "mail", "news", "www-data", "backup",
             "nobody", "systemd-network", "sshd", "alice", "bob", "carol", "deploy", "postgres", "jsmith",
             "svc-monitoring"]
    pick = users[:rng.randint(1, len(users))] if rng.random() < .6 else rng.sample(users, rng.randint(1, 6))
    mx = rng.choice(["0", "0", "3", "5", "10"])
    tz = rng.choice(["+0000", "+0000", "-0500", "+0100", "+0530"])
    for u in pick:
        fails = rng.choice([0] * 6 + [1, 2, 3, 5, 12, 47])
        if fails or rng.random() < .3:
            latest = f"{rng.randint(1, 12):02d}/{rng.randint(1, 28):02d}/{rng.choice([24, 25, 26])} " \
                     f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {tz}"
            on = rng.choice([f"pts/{rng.randint(0, 9)}", "ssh", f"tty{rng.randint(1, 6)}", fake.ip(rng), None])
        else:
            latest, on = f"01/01/70 00:00:00 {tz}", None
        text = f"{u:<12}{fails:>8}{mx:>8} {latest}  {on or ''}"
        cells = [u, str(fails), mx, latest, on]
        if fails and mx != "0" and fails >= int(mx) and rng.random() < .5:
            lock = f"[{rng.randint(1, 900)}s left]"
            text += f" {lock}" if on else f"   {lock}"
            # the lock note rides along with the terminal column
            cells[4] = (on + " " + lock) if on else lock
        d.line(text.rstrip(), "row", cells)
    return d
