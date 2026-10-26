"""libcap-ng `pscap` (optionally -a): a header line, then fixed-width
ppid/pid/name/command columns followed by a free-width comma-separated
capability list, with ` +` / ` @` suffixes for bounding/ambient sets."""
from lib import Doc, fake

TOOL = "pscap"

PROCS = [("root", "systemd-journal", "chown, dac_override, dac_read_search, fowner, setgid, setuid, sys_ptrace, sys_admin, audit_control, mac_override, syslog, audit_read"),
         ("root", "systemd-udevd", "full"),
         ("root", "NetworkManager", "dac_override, kill, setgid, setuid, net_bind_service, net_admin, net_raw, sys_chroot, sys_ptrace, sys_resource, audit_write, setfcap"),
         ("chrony", "chronyd", "net_bind_service, sys_time"),
         ("root", "sshd", "full"),
         ("root", "auditd", "full"),
         ("root", "rsyslogd", "full"),
         ("root", "crond", "full"),
         ("dbus", "dbus-broker-lau", "full"),
         ("root", "polkitd", "full"),
         ("root", "firewalld", "full"),
         ("avahi", "avahi-daemon", "setgid, setuid, sys_chroot"),
         ("systemd-resolve", "systemd-resolve", "net_bind_service, net_raw"),
         ("systemd-network", "systemd-network", "net_bind_service, net_broadcast, net_admin, net_raw"),
         ("systemd-timesync", "systemd-timesyn", "sys_time"),
         ("root", "containerd", "full"),
         ("root", "dockerd", "full"),
         ("nginx", "nginx", "net_bind_service"),
         ("root", "nginx", "full"),
         ("ntp", "ntpd", "net_bind_service, sys_time"),
         ("root", "sssd_be", "chown, dac_override, setgid, setuid"),
         ("root", "fail2ban-server", "full"),
         ("root", "rngd", "sys_admin"),
         ("haproxy", "haproxy", "net_bind_service"),
         ("root", "cupsd", "full"),
         ("root", "gssproxy", "full"),
         ("unbound", "unbound", "net_bind_service, sys_chroot")]


def generate(rng):
    d = Doc()
    procs = rng.sample(PROCS, rng.randint(2, 16))
    ppids = [1] * 8 + [rng.randint(500, 3000) for _ in range(2)]
    rows = []
    for name, cmd, caps in procs:
        pid = str(rng.randint(300, 400000) if rng.random() < .7 else rng.randint(300, 9999))
        if rng.random() < .15 and caps != "full":
            caps += rng.choice([" +", " @", " +"])
        rows.append([str(rng.choice(ppids)), pid, name, cmd, caps])
    rows.sort(key=lambda r: int(r[1]))

    def fmt(r):
        return f"{r[0]:<5} {r[1]:<5} {r[2]:<10}  {r[3]:<18}  {r[4]}"

    hdr = ["ppid", "pid", "name", "command", "capabilities"]
    d.line(fmt(hdr), "header", hdr)
    for r in rows:
        d.line(fmt(r), "row", r)
    return d
