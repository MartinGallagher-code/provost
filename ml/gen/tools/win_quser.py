"""cmd `quser` / `query user`: fixed columns USERNAME, SESSIONNAME, ID, STATE,
IDLE TIME, LOGON TIME (multi-word headers), a `>` marking the caller's own
session, empty SESSIONNAME for disconnected sessions, and idle times like
`none`, `.`, `5`, `1:12` or `2+03:11`."""
from lib import Doc, fake

TOOL = "quser"

NAMES = ["administrator", "alice", "bob.smith", "carol", "svc_backup", "jdoe", "m.gallagher",
         "helpdesk01", "sqladmin", "kiosk", "a.very.long.username.x", "deploy", "erin.o'neill"]


def _logon(rng, style):
    mo, dd, h, mi = rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59)
    if style == "us":
        return f"{mo}/{dd}/2026 {h % 12 or 12}:{mi:02d} {'AM' if h < 12 else 'PM'}"
    if style == "eu":
        return f"{dd:02d}.{mo:02d}.2026 {h:02d}:{mi:02d}"
    return f"2026-{mo:02d}-{dd:02d} {h:02d}:{mi:02d}"


def _idle(rng):
    return rng.choice(["none", "none", ".", str(rng.randint(1, 59)), f"{rng.randint(1, 23)}:{rng.randint(0, 59):02d}",
                       f"{rng.randint(1, 9)}+{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}"])


def generate(rng):
    d = Doc()
    style = rng.choice(["us", "us", "eu", "iso"])
    hdr = ["USERNAME", "SESSIONNAME", "ID", "STATE", "IDLE TIME", "LOGON TIME"]

    def render(mark, u, s, i, st, idle, logon):
        return f"{mark}{u:<22}{s:<17}{i:>4}  {st:<6}{idle:>11}  {logon}"

    d.line(render(" ", *hdr), "header", hdr)
    users = rng.sample(NAMES, rng.randint(1, 7))
    me = rng.randrange(len(users))
    ids = sorted(rng.sample(range(2, 40), len(users)))
    for k, u in enumerate(users):
        u = u[:20]
        disc = rng.random() < .3 and k != me
        sess = None if disc else ("console" if k == 0 and rng.random() < .6 else f"rdp-tcp#{rng.randint(0, 99)}")
        sid = str(1 if sess == "console" else ids[k])
        state = "Disc" if disc else "Active"
        idle = _idle(rng) if k != me else rng.choice(["none", ".", "none"])
        logon = _logon(rng, style)
        text = render(">" if k == me else " ", u, sess or "", sid, state, idle, logon)
        d.line(text, "row", [u, sess, sid, state, idle, logon])
    return d
