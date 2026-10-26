"""Sendmail `mailq`: per-queue banner, dashed header, one row per message
with deferral reason and recipients on continuation lines, totals."""
from lib import Doc, fake

TOOL = "mailq"

REASONS = ["Deferred: Connection refused by {mx}.", "Deferred: Connection timed out with {mx}.",
           "Deferred: 450 4.2.0 <{rcpt}>: Recipient address rejected: Greylisted",
           "Deferred: Name server: {dom}.: host name lookup failure",
           "Deferred: 421 4.7.0 Try again later, closing connection.",
           "Deferred: 452 4.2.2 Mailbox full", "Deferred", "Deferred: Operation timed out",
           "Expired: service unavailable"]
DOMS = "example.com example.org mail.example.net gmail.com yahoo.co.uk corp.local lists.example.org".split()
DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def addr(rng):
    return f"{rng.choice(fake.USERS + ['info', 'noreply', 'sales', 'j.smith', 'mailer-daemon'])}@{rng.choice(DOMS)}"


def qid(rng):
    al = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    return (rng.choice("tuvwx") + str(rng.randint(1, 9)) + rng.choice("ABCDEFGHIJKL")
            + "".join(rng.choice(al) for _ in range(5)) + f"{rng.randint(0, 999999):06d}")


def queue(d, rng, path):
    n = rng.choice([0, rng.randint(1, 3), rng.randint(1, 9)])
    if n == 0:
        d.line(f"{path} is empty", "kv", [path, "is empty"])
        d.line("\t\tTotal requests: 0", "kv", ["Total requests", "0"])
        return
    title = f"{path} ({n} request{'s' if n > 1 else ''})"
    d.section("\t\t" + title, title)
    d.line("-----Q-ID----- --Size-- -----Q-Time----- ------------Sender/Recipient-----------",
           "header", ["Q-ID", "Size", "Q-Time", "Sender/Recipient"])
    for _ in range(n):
        q = qid(rng)
        flag = rng.choice([" ", " ", " ", "*", "X", "-"])
        size = str(rng.choice([rng.randint(200, 9000), rng.randint(1000, 99999), rng.randint(100000, 9999999)]))
        when = f"{rng.choice(DAYS)} {rng.choice(MONS)} {rng.randint(1, 28):2d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}"
        sender = "<" + addr(rng) + ">" if rng.random() < .9 else "<>"
        qcell = q + flag if flag != " " else q
        text = q + flag + size.rjust(8) + " " + when + " " + sender
        d.line(text, "row", [qcell, size, when, sender])
        if rng.random() < 0.75:
            mx = f"{rng.choice(['mx', 'mx1', 'mail', 'smtp'])}.{rng.choice(DOMS)}"
            rcpt = addr(rng)
            r = "(" + rng.choice(REASONS).format(mx=mx, rcpt=rcpt, dom=rng.choice(DOMS)) + ")"
            d.line(" " * 17 + r, "cont", [r])
        for _ in range(rng.choice([1, 1, 1, 2, 3])):
            rc = "<" + addr(rng) + ">"
            d.line("\t\t\t\t\t " + rc, "cont", [rc])
    d.line(f"\t\tTotal requests: {n}", "kv", ["Total requests", str(n)])


def generate(rng):
    d = Doc()
    if rng.random() < 0.4:
        d.section("MSP Queue status...", "MSP Queue status")
        queue(d, rng, "/var/spool/clientmqueue")
        d.section("MTA Queue status...", "MTA Queue status")
    queue(d, rng, rng.choice(["/var/spool/mqueue", "/var/spool/mqueue", "/var/spool/mqueue/q1"]))
    return d
