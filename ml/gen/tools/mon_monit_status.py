"""`monit status`: a daemon banner, then one block per service: a quoted
service heading followed by indented, column-aligned key/value lines."""
from lib import Doc, fake

TOOL = "monit-status"

DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def _uptime(rng):
    d, h, m = rng.randint(0, 120), rng.randint(0, 23), rng.randint(0, 59)
    return (f"{d}d " if d else "") + f"{h}h {m}m"


def _stamp(rng):
    return (f"{rng.choice(DAYS)}, {rng.randint(1, 28):02d} {rng.choice(MONS)} 2026 "
            f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}")


def _mb(rng):
    return rng.choice([f"{rng.uniform(1, 999):.1f} MB", f"{rng.uniform(1, 30):.1f} GB",
                       f"{rng.randint(1, 999)} kB", "0 B"])


def _common(rng, ok):
    status = "OK" if ok else rng.choice(["Does not exist", "Connection failed", "Resource limit matched",
                                         "Execution failed | Does not exist", "Not monitored"])
    pairs = [("status", status),
             ("monitoring status", "Monitored" if ok or rng.random() < .6 else "Not monitored"),
             ("monitoring mode", rng.choice(["active", "active", "passive", "manual"])),
             ("on reboot", rng.choice(["start", "start", "nostart", "laststate"]))]
    return pairs


def _process(rng, ok):
    pairs = _common(rng, ok)
    if not ok and rng.random() < .5:
        return pairs + [("data collected", _stamp(rng))]
    pairs += [("pid", str(rng.randint(300, 99999))), ("parent pid", str(rng.choice([1, rng.randint(2, 9999)]))),
              ("uid", rng.choice(["0", "33", "999", "1000"])), ("effective uid", rng.choice(["0", "33", "999"])),
              ("gid", rng.choice(["0", "33", "999"])), ("uptime", _uptime(rng))]
    if rng.random() < .8:
        pairs += [("threads", str(rng.randint(1, 64)))]
    pairs += [("children", str(rng.randint(0, 32))),
              ("cpu", f"{rng.uniform(0, 30):.1f}%"), ("cpu total", f"{rng.uniform(0, 60):.1f}%"),
              ("memory", f"{rng.uniform(0, 20):.1f}% [{_mb(rng)}]"),
              ("memory total", f"{rng.uniform(0, 40):.1f}% [{_mb(rng)}]")]
    if rng.random() < .6:
        pairs += [("security attribute", rng.choice(["unconfined", "(null)", "system_u:system_r:httpd_t:s0"]))]
    if rng.random() < .7:
        pairs += [("disk read", f"{rng.randint(0, 900)} B/s [{_mb(rng)} total]"),
                  ("disk write", f"{rng.randint(0, 900)} B/s [{_mb(rng)} total]")]
    for _ in range(rng.randint(0, 2)):
        port = fake.port(rng)
        proto = rng.choice(["HTTP", "DEFAULT", "MYSQL", "PGSQL", "REDIS", "SSH"])
        pairs.append(("port response time",
                      f"{rng.uniform(0.05, 80):.3f} ms to {rng.choice(['localhost', '127.0.0.1', fake.ip(rng)])}:{port} "
                      f"type TCP/IP protocol {proto}"))
    if rng.random() < .3:
        pairs.append(("unix socket response time", f"{rng.uniform(0.01, 5):.3f} ms to /run/php/php-fpm.sock type UNIX protocol DEFAULT"))
    pairs.append(("data collected", _stamp(rng)))
    return pairs


def _system(rng):
    pairs = _common(rng, True)
    pairs += [("load average", [f"[{rng.uniform(0, 8):.2f}]" for _ in range(3)])]
    cpu = [f"{rng.uniform(0, 40):.1f}%usr", f"{rng.uniform(0, 15):.1f}%sys", f"{rng.uniform(0, 2):.1f}%nice",
           f"{rng.uniform(0, 10):.1f}%iowait", f"{rng.uniform(0, 1):.1f}%hardirq",
           f"{rng.uniform(0, 2):.1f}%softirq", f"{rng.uniform(0, 3):.1f}%steal",
           f"{0:.1f}%guest", f"{0:.1f}%guestnice"]
    pairs += [("cpu", cpu if rng.random() < .8 else cpu[:4]),
              ("memory usage", f"{_mb(rng)} [{rng.uniform(1, 99):.1f}%]"),
              ("swap usage", f"{_mb(rng)} [{rng.uniform(0, 50):.1f}%]"),
              ("uptime", _uptime(rng)), ("boot time", _stamp(rng))]
    if rng.random() < .7:
        pairs.append(("filedescriptors", f"{rng.randint(300, 40000)} [{rng.uniform(0, 5):.1f}% of 9223372036854775807 limit]"))
    pairs.append(("data collected", _stamp(rng)))
    return pairs


def _filesystem(rng):
    pairs = _common(rng, True)
    tot = rng.uniform(5, 2000)
    pairs += [("filesystem type", rng.choice(["ext4", "xfs", "btrfs", "zfs"])),
              ("filesystem flags", rng.choice(["rw,relatime", "rw,noatime,errors=remount-ro", "rw,relatime,attr2,inode64"])),
              ("permission", rng.choice(["755", "700", "1777"])), ("uid", "0"), ("gid", "0"),
              ("block size", rng.choice(["4 kB", "512 B"])),
              ("space total", f"{tot:.1f} GB (of which {rng.uniform(0, 5):.1f}% is reserved for root user)"),
              ("space free for non superuser", f"{tot * rng.uniform(.05, .9):.1f} GB [{rng.uniform(5, 90):.1f}%]"),
              ("space free total", f"{tot * rng.uniform(.05, .9):.1f} GB [{rng.uniform(5, 95):.1f}%]")]
    if rng.random() < .7:
        n = rng.randint(100000, 9000000)
        pairs += [("inodes total", str(n)),
                  ("inodes free", f"{rng.randint(1000, n)} [{rng.uniform(5, 99):.1f}%]")]
    if rng.random() < .6:
        pairs += [("read bytes", f"{rng.uniform(0, 900):.1f} B/s [{_mb(rng)} total]"),
                  ("disk read operations", f"{rng.uniform(0, 90):.1f} reads/s [{rng.randint(100, 9999999)} reads total]"),
                  ("write bytes", f"{rng.uniform(0, 900):.1f} kB/s [{_mb(rng)} total]"),
                  ("disk write operations", f"{rng.uniform(0, 90):.1f} writes/s [{rng.randint(100, 9999999)} writes total]")]
    pairs.append(("data collected", _stamp(rng)))
    return pairs


def _other(rng, kind):
    pairs = _common(rng, rng.random() < .85)
    if kind == "Remote Host":
        pairs += [("ping response time", f"{rng.uniform(0.1, 90):.3f} ms")]
        if rng.random() < .6:
            pairs += [("port response time", f"{rng.uniform(0.1, 90):.3f} ms to {fake.host(rng)}:{fake.port(rng)} type TCP/IP protocol HTTP")]
    elif kind == "File":
        pairs += [("permission", rng.choice(["644", "640", "600"])), ("uid", "0"), ("gid", "0"),
                  ("size", f"{rng.randint(0, 999999)} B"), ("access timestamp", _stamp(rng)),
                  ("change timestamp", _stamp(rng)), ("modify timestamp", _stamp(rng))]
        if rng.random() < .5:
            pairs.append(("checksum", f"{fake.hexid(rng, 32)} (MD5)"))
    elif kind == "Program":
        pairs += [("last exit value", str(rng.choice([0, 0, 1, 2]))),
                  ("last output", rng.choice(["OK", "backup completed", "-", "WARNING: 3 jobs queued"]))]
    elif kind == "Net":
        pairs += [("link", f"{rng.randint(0, 999)} errors"),
                  ("capacity", rng.choice(["1 Gb/s full-duplex", "10 Gb/s full-duplex", "100 Mb/s half-duplex"])),
                  ("download packets", f"{rng.randint(0, 9999)} per second [{rng.randint(1000, 99999999)} total]"),
                  ("download bytes", f"{rng.uniform(0, 999):.1f} kB/s [{_mb(rng)} total]"),
                  ("upload packets", f"{rng.randint(0, 9999)} per second [{rng.randint(1000, 99999999)} total]"),
                  ("upload bytes", f"{rng.uniform(0, 999):.1f} kB/s [{_mb(rng)} total]")]
    pairs.append(("data collected", _stamp(rng)))
    return pairs


def generate(rng):
    d = Doc()
    ver = f"5.{rng.randint(20, 34)}.{rng.randint(0, 3)}"
    if rng.random() < .8:
        up = _uptime(rng)
        d.line(f"Monit {ver} uptime: {up}", "kv", [f"Monit {ver} uptime", up])
    else:
        up = _uptime(rng)
        d.line(f"The Monit daemon {ver} uptime: {up}", "kv", [f"The Monit daemon {ver} uptime", up])
    width = rng.choice([28, 28, 30, 33])
    host = f"{fake.word(rng)}-{rng.randint(1, 30):02d}"
    blocks = []
    for _ in range(rng.randint(1, 5)):
        kind = rng.choice(["Process", "Process", "Process", "Filesystem", "Remote Host", "File", "Program", "Net"])
        name = {"Process": rng.choice(["nginx", "sshd", "postgresql", "redis", "php-fpm", "cron", "mysqld",
                                       "docker", fake.word(rng), fake.name(rng, "_")]),
                "Filesystem": rng.choice(["rootfs", "datafs", "var", "home_fs", f"{fake.word(rng)}_disk"]),
                "Remote Host": rng.choice([fake.host(rng), fake.ip(rng), f"{fake.word(rng)}_gateway"]),
                "File": rng.choice(["nginx_conf", "passwd", "syslog", f"{fake.word(rng)}.log"]),
                "Program": rng.choice(["backup_check", "cert_expiry", f"check_{fake.word(rng)}"]),
                "Net": rng.choice(["eth0", "ens3", "enp0s31f6", "bond0", "wg0"])}[kind]
        if kind == "Process":
            blocks.append((kind, name, _process(rng, rng.random() < .85)))
        elif kind == "Filesystem":
            blocks.append((kind, name, _filesystem(rng)))
        else:
            blocks.append((kind, name, _other(rng, kind)))
    pos = rng.randint(0, len(blocks))
    blocks.insert(pos, ("System", host, _system(rng)))
    for kind, name, pairs in blocks:
        d.blank()
        head = f"{kind} '{name}'"
        d.section(head, head)
        for k, v in pairs:
            vals = v if isinstance(v, list) else [v]
            d.line("  " + k.ljust(width) + " " + " ".join(vals), "kv", [k] + vals)
    if rng.random() < .3:
        d.blank()
    return d
