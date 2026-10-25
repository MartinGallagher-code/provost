"""`monit summary` (version/uptime line + box-drawn table of services) or
`monit status` (per-service headings over aligned key/value blocks)."""
from lib import Doc, fake

TOOL = "monit"

SERVICES = [("Process", "nginx"), ("Process", "sshd"), ("Process", "postgresql"), ("Process", "redis"),
            ("Process", "php-fpm"), ("Process", "cron"), ("Process", "docker"), ("Filesystem", "rootfs"),
            ("Filesystem", "data"), ("Host", "upstream-api"), ("Program", "backup-check"), ("File", "nginx.conf"),
            ("Directory", "spool"), ("Network", "eth0"), ("Fifo", "logpipe"), ("Remote Host", "mx.example.com")]
STATUS = {"Process": ["OK", "OK", "OK", "Not monitored", "Does not exist", "Initializing", "Execution failed | Does not exist"],
          "Filesystem": ["OK", "OK", "Accessible", "Resource limit matched", "Space usage limit matched"],
          "Host": ["OK", "Connection failed", "Online with all services"],
          "Remote Host": ["OK", "Connection failed", "Online with all services"],
          "Program": ["OK", "Status failed", "Status ok"],
          "File": ["OK", "Accessible", "Checksum changed"],
          "Directory": ["OK", "Accessible"],
          "Network": ["OK", "Link down", "UP"],
          "Fifo": ["OK", "Accessible"],
          "System": ["OK", "OK", "Resource limit matched"]}


def uptime(rng):
    return rng.choice([f"{rng.randint(0, 400)}d {rng.randint(0, 23)}h {rng.randint(0, 59)}m",
                       f"{rng.randint(0, 23)}h {rng.randint(0, 59)}m", f"{rng.randint(0, 59)}m"])


def summary(d, rng, host, svcs):
    rows = [(host, rng.choice(STATUS["System"]), "System")] + [(n, rng.choice(STATUS[t]), t) for t, n in svcs]
    hdr = ("Service Name", "Status", "Type")
    w = [max(33, max(len(r[c]) for r in rows) + 2) if c == 0 else
         max(28 if c == 1 else 15, max(len(r[c]) for r in rows) + 2) for c in range(3)]
    H = "─"

    def rule(l, m, r):
        return l + m.join(H * (x + 1) for x in w) + r

    def render(cells):
        return "│" + "│".join(" " + c.ljust(w[i]) for i, c in enumerate(cells)) + "│"

    d.skip(rule("┌", "┬", "┐"))
    d.line(render(hdr), "header", list(hdr))
    d.skip(rule("├", "┼", "┤"))
    sep = rng.random() < 0.7
    for i, r in enumerate(rows):
        d.line(render(r), "row", list(r))
        if sep and i < len(rows) - 1:
            d.skip(rule("├", "┼", "┤"))
    d.skip(rule("└", "┴", "┘"))


def status(d, rng, host, svcs):
    when = fake.date(rng, "rfc")[:-4]
    for t, n in [("System", host)] + svcs:
        d.section(f"{t} '{n}'", f"{t} '{n}'")
        st = rng.choice(STATUS[t])
        mon = "Not monitored" if st == "Not monitored" else rng.choice(["Monitored", "Monitored", "Waiting"])
        pairs = [("status", [st]), ("monitoring status", [mon]), ("monitoring mode", [rng.choice(["active", "passive"])]),
                 ("on reboot", [rng.choice(["start", "nostart", "laststate"])])]
        if t == "Process" and mon == "Monitored":
            pairs += [("pid", [str(rng.randint(100, 99999))]), ("parent pid", ["1"]),
                      ("uid", [str(rng.choice([0, 33, 999]))]), ("effective uid", [str(rng.choice([0, 33]))]),
                      ("gid", [str(rng.choice([0, 33]))]), ("uptime", [uptime(rng)]),
                      ("threads", [str(rng.randint(1, 64))]), ("children", [str(rng.randint(0, 16))]),
                      ("cpu", [f"{rng.uniform(0, 30):.1f}%"]), ("cpu total", [f"{rng.uniform(0, 60):.1f}%"]),
                      ("memory", [f"{rng.uniform(0, 9):.1f}%", f"[{rng.uniform(1, 900):.1f} MB]"]),
                      ("memory total", [f"{rng.uniform(0, 20):.1f}%", f"[{rng.uniform(1, 2000):.1f} MB]"]),
                      ("security attribute", ["unconfined"])]
            if rng.random() < .5:
                pairs.append(("port response time", [f"{rng.uniform(0, 9):.3f} ms to localhost:{fake.port(rng)} type TCP/IP protocol HTTP"]))
        elif t == "System":
            pairs += [("load average", [f"[{rng.uniform(0, 4):.2f}]", f"[{rng.uniform(0, 4):.2f}]", f"[{rng.uniform(0, 4):.2f}]"]),
                      ("cpu", [f"{rng.uniform(0, 40):.1f}%usr", f"{rng.uniform(0, 9):.1f}%sys",
                               f"{rng.uniform(0, 2):.1f}%nice", f"{rng.uniform(0, 5):.1f}%iowait",
                               f"{rng.uniform(0, 1):.1f}%hardirq", f"{rng.uniform(0, 1):.1f}%softirq",
                               f"{rng.uniform(0, 1):.1f}%steal", f"{rng.uniform(0, 1):.1f}%guest",
                               f"{rng.uniform(0, 1):.1f}%guestnice"]),
                      ("memory usage", [f"{rng.uniform(100, 9000):.1f} MB", f"[{rng.uniform(1, 90):.1f}%]"]),
                      ("swap usage", [f"{rng.uniform(0, 900):.1f} kB", f"[{rng.uniform(0, 9):.1f}%]"]),
                      ("uptime", [uptime(rng)]),
                      ("boot time", [fake.date(rng, "rfc")[:-4]]),
                      ("filedescriptors", [f"{rng.randint(500, 9000)}", f"[{rng.uniform(0, 5):.1f}% of {rng.choice([9223372036854775807, 1048576])} limit]"])]
        elif t == "Filesystem":
            pairs += [("filesystem type", [rng.choice(["ext4", "xfs", "btrfs", "zfs"])]),
                      ("filesystem flags", ["rw,relatime"]),
                      ("permission", ["755"]), ("uid", ["0"]), ("gid", ["0"]),
                      ("block size", ["4 kB"]),
                      ("space total", [f"{rng.uniform(1, 999):.1f} GB", f"(of which {rng.uniform(0, 6):.1f}% is reserved for root user)"]),
                      ("space free for non superuser", [f"{rng.uniform(1, 500):.1f} GB", f"[{rng.uniform(1, 99):.1f}%]"]),
                      ("space free total", [f"{rng.uniform(1, 500):.1f} GB", f"[{rng.uniform(1, 99):.1f}%]"]),
                      ("inodes total", [str(rng.randint(100000, 90000000))]),
                      ("inodes free", [str(rng.randint(1000, 9000000)), f"[{rng.uniform(1, 99):.1f}%]"])]
        elif t in ("Host", "Remote Host"):
            pairs += [("ping response time", [f"{rng.uniform(0, 90):.3f} ms"]),
                      ("port response time", [f"{rng.uniform(0, 200):.3f} ms to {n}:{fake.port(rng)} type TCP/IP protocol DEFAULT"])]
        pairs.append(("data collected", [when]))
        w = 34
        for k, vals in pairs:
            d.line("  " + k.ljust(w) + " ".join(vals), "kv", [k] + vals)
        d.blank()
    d.lines.pop(), d.labels.pop()


def generate(rng):
    d = Doc()
    ver = rng.choice(["5.26.0", "5.27.2", "5.32.0", "5.33.0", "5.34.3"])
    host = fake.host(rng).split(".")[0]
    up = uptime(rng)
    d.line(f"Monit {ver} uptime: {up}", "row", ["Monit", ver, "uptime", up])
    svcs = rng.sample(SERVICES, rng.randint(1, 10))
    if rng.random() < 0.65:
        if rng.random() < 0.5:
            d.blank()
        summary(d, rng, host, svcs)
    else:
        d.blank()
        status(d, rng, host, svcs)
    return d
