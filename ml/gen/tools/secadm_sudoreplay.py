"""`sudoreplay -l` session log listing: one line per recorded session,
`date : user : KEY=value ; KEY=value ; ... ; COMMAND=...`."""
from lib import Doc, fake

TOOL = "sudoreplay"

CMDS = ["/usr/bin/systemctl restart nginx", "/bin/bash", "/usr/bin/apt-get update", "/usr/bin/apt upgrade -y",
        "/usr/bin/journalctl -u sshd --since today", "/usr/bin/vi /etc/sudoers.d/90-ops", "/bin/su -",
        "/usr/sbin/ausearch -m USER_LOGIN -ts today", "/usr/bin/tail -f /var/log/secure", "/usr/bin/id",
        "/usr/sbin/aureport --summary", "/usr/bin/cat /etc/shadow", "/usr/sbin/visudo",
        "/usr/bin/docker ps -a", "/usr/bin/dnf install -y aide", "/usr/sbin/aide --check",
        "/usr/bin/kubectl -n kube-system get pods", "/usr/sbin/reboot", "/usr/bin/passwd bob",
        "/usr/bin/chown -R www-data:www-data /var/www/html", "/usr/sbin/setenforce 1", "/usr/bin/ls -la /root"]
MON = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def generate(rng):
    d = Doc()
    with_host = rng.random() < .3
    with_group = rng.random() < .25
    seq = rng.random() < .6
    y = rng.choice([2024, 2025, 2026])
    m = rng.randint(0, 11)
    day = rng.randint(1, 20)
    n = rng.randint(2, 18)
    sid = rng.randint(1, 200)
    hosts = [fake.host(rng).split(".")[0] for _ in range(3)]
    B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    times = []
    for i in range(n):
        day = min(28, day + (1 if rng.random() < .2 else 0))
        times.append((day, rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)))
    times.sort()
    for day, H, M, S in times:
        ts = f"{MON[m]} {day:2d} {H:02d}:{M:02d}:{S:02d} {y}"
        user = rng.choice(["alice", "bob", "carol", "deploy", "jsmith", "m.garcia", "ansible"])
        tty = rng.choice([f"/dev/pts/{rng.randint(0, 12)}", f"/dev/pts/{rng.randint(0, 3)}", "unknown"])
        cwd = rng.choice(["/home/" + user, "/home/" + user, "/", "/etc", "/var/www/html", "/tmp", "/root"])
        runas = rng.choice(["root", "root", "root", "postgres", "www-data"])
        sid += 1
        b = B36[sid // 46656 % 36] + B36[sid // 1296 % 36] + B36[sid // 36 % 36] + B36[sid % 36]
        tsid = f"00/{b[:2]}/{b[2:]}" if seq else f"{sid:06X}"
        pairs = []
        if with_host:
            pairs.append(("HOST", rng.choice(hosts)))
        pairs += [("TTY", tty), ("CWD", cwd), ("USER", runas)]
        if with_group:
            pairs.append(("GROUP", rng.choice(["root", "wheel", "adm"])))
        pairs += [("TSID", tsid), ("COMMAND", rng.choice(CMDS))]
        text = f"{ts} : {user} : " + " ; ".join(f"{k}={v}" for k, v in pairs)
        cells = [ts, user]
        for k, v in pairs:
            cells += [k, v]
        d.line(text, "row", cells)
    return d
