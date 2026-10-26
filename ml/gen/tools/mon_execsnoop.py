"""bcc `execsnoop [-t|-T] [-U] [-x]`: one line per exec() traced, under a
fixed-layout header (PCOMM PID PPID RET ARGS) with optional time and UID
columns; ARGS is the free-text command line."""
from lib import Doc, fake

TOOL = "execsnoop"

CMDS = [("bash", "/bin/bash"), ("sh", "/bin/sh -c {cmd}"), ("ls", "/usr/bin/ls --color=auto {path}"),
        ("cat", "/usr/bin/cat {path}"), ("grep", "/usr/bin/grep -E {w} {path}"), ("ps", "/usr/bin/ps -ef"),
        ("git", "/usr/bin/git status --porcelain"), ("sed", "/usr/bin/sed -n 1,20p {path}"),
        ("run-parts", "/bin/run-parts --report /etc/cron.hourly"), ("curl", "/usr/bin/curl -sS https://{host}/healthz"),
        ("python3", "/usr/bin/python3 /opt/{w}/manage.py {w}"), ("node", "/usr/bin/node /srv/{w}/index.js"),
        ("systemctl", "/usr/bin/systemctl is-active {w}.service"), ("date", "/usr/bin/date +%s"),
        ("id", "/usr/bin/id -u"), ("uname", "/usr/bin/uname -r"), ("awk", "/usr/bin/awk {{print $1}} {path}"),
        ("docker", "/usr/bin/docker ps --format {{{{.Names}}}}"), ("kubectl", "/usr/local/bin/kubectl get pods -n {w}"),
        ("check_disk", "/usr/lib/nagios/plugins/check_disk -w 20% -c 10% -p /"), ("man", "/usr/bin/man ls"),
        ("pager", "/usr/bin/pager -s"), ("preconv", "/usr/bin/preconv -e UTF-8"), ("tbl", "/usr/bin/tbl"),
        ("nroff", "/usr/bin/nroff -mandoc -Tutf8"), ("groff", "/usr/bin/groff -mtty-char -Tutf8 -mandoc -rLL=169n -rLT=169n"),
        ("sleep", "/usr/bin/sleep {n}"), ("mktemp", "/usr/bin/mktemp -d"), ("ssh", "/usr/bin/ssh -o BatchMode=yes {host} uptime")]


def generate(rng):
    d = Doc()
    tmode = rng.choice([None, None, "t", "T"])
    uid = rng.random() < .3
    failed = rng.random() < .3
    header, fmt = [], []
    if tmode == "t":
        header.append("TIME(s)")
        fmt.append(8)
    elif tmode == "T":
        header.append("TIME")
        fmt.append(8)
    if uid:
        header.append("UID")
        fmt.append(6)
    header += ["PCOMM", "PID", "PPID", "RET", "ARGS"]
    fmt += [16, 7, 7, -3, 0]

    def render(cells):
        out = []
        for c, w in zip(cells, fmt):
            out.append(c.rjust(-w) if w < 0 else (c.ljust(w) if w else c))
        return " ".join(out).rstrip()

    d.line(render(header), "header", header)
    t0 = rng.uniform(0, 3)
    clock = rng.randint(0, 86000)
    pid = rng.randint(1000, 4000000)
    parent = pid - 1
    for i in range(rng.randint(2, 30)):
        comm, args = rng.choice(CMDS)
        args = args.format(cmd=rng.choice(["'echo hi'", "/usr/local/bin/backup.sh", "\"test -x /usr/sbin/anacron\""]),
                           path=fake.path(rng), w=fake.word(rng), host=fake.host(rng), n=rng.randint(1, 60))
        if rng.random() < .05:
            args = args + " " + " ".join(fake.word(rng) for _ in range(rng.randint(8, 20))) + " ..."
        ret = "0"
        if failed and rng.random() < .3:
            ret = rng.choice(["-2", "-13", "-8"])
        pid += rng.randint(1, 40)
        if rng.random() < .4:
            parent = pid - rng.randint(1, 5)
        t0 += rng.uniform(0, 2)
        clock += rng.randint(0, 2)
        row = []
        if tmode == "t":
            row.append(f"{t0:.3f}")
        elif tmode == "T":
            row.append(f"{clock // 3600 % 24:02d}:{clock // 60 % 60:02d}:{clock % 60:02d}")
        if uid:
            row.append(rng.choice(["0", "0", "1000", "33", "998"]))
        row += [comm[:16], str(pid), str(parent), ret, args]
        d.line(render(row), "row", row)
    return d
