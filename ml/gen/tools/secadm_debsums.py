"""`debsums` package integrity check: the default listing (path, status
right-aligned to column 80), `debsums -s` (only `debsums: changed/missing
file ... (from pkg package)` messages) or `debsums -c` (bare paths)."""
from lib import Doc, fake

TOOL = "debsums"

PKGS = {"openssh-server": ["/usr/sbin/sshd", "/usr/share/man/man8/sshd.8.gz", "/usr/lib/openssh/sftp-server",
                           "/usr/share/doc/openssh-server/README.Debian.gz", "/lib/systemd/system/ssh.service"],
        "sudo": ["/usr/bin/sudo", "/usr/bin/sudoedit", "/usr/lib/sudo/sudoers.so", "/usr/share/man/man8/sudo.8.gz",
                 "/usr/lib/sudo/libsudo_util.so.0.0.0"],
        "coreutils": ["/bin/ls", "/bin/cp", "/bin/mv", "/usr/bin/md5sum", "/usr/bin/sha256sum",
                      "/usr/share/doc/coreutils/README.gz"],
        "libpam-modules": ["/lib/x86_64-linux-gnu/security/pam_unix.so", "/lib/x86_64-linux-gnu/security/pam_faillock.so",
                           "/sbin/unix_chkpwd", "/usr/share/man/man8/pam_unix.8.gz"],
        "auditd": ["/sbin/auditd", "/sbin/auditctl", "/sbin/ausearch", "/usr/share/man/man8/auditd.8.gz"],
        "curl": ["/usr/bin/curl", "/usr/share/doc/curl/copyright", "/usr/share/man/man1/curl.1.gz"],
        "libssl3": ["/usr/lib/x86_64-linux-gnu/libssl.so.3", "/usr/lib/x86_64-linux-gnu/libcrypto.so.3",
                    "/usr/lib/x86_64-linux-gnu/engines-3/afalg.so", "/usr/share/doc/libssl3/changelog.Debian.gz"],
        "apparmor": ["/sbin/apparmor_parser", "/lib/apparmor/apparmor.systemd", "/usr/share/apparmor-features/features"],
        "login": ["/bin/login", "/usr/bin/newgrp", "/usr/share/man/man1/login.1.gz"],
        "base-files": ["/etc/debian_version", "/usr/lib/os-release", "/usr/share/common-licenses/GPL-3"],
        "libc-bin": ["/sbin/ldconfig", "/usr/bin/getent", "/usr/bin/iconv", "/usr/bin/locale"]}
CONF = ["/etc/ssh/sshd_config", "/etc/sudoers", "/etc/pam.d/common-auth", "/etc/audit/auditd.conf",
        "/etc/login.defs", "/etc/apparmor.d/usr.sbin.cupsd", "/etc/default/grub", "/etc/issue.net"]


def generate(rng):
    d = Doc()
    mode = rng.choice(["full", "full", "full", "silent", "changed"])
    pkgs = rng.sample(sorted(PKGS), rng.randint(1, 5))
    files = [(p, f) for p in pkgs for f in PKGS[p] if rng.random() < .85]
    if not files:
        files = [(pkgs[0], PKGS[pkgs[0]][0])]
    if mode == "full":
        for p, f in files:
            st = rng.choices(["OK", "FAILED", "REPLACED"], [40, 2, 1])[0]
            if rng.random() < .04:
                d.line(f"debsums: missing file {f} (from {p} package)", "row",
                       ["debsums", "missing file", f, f"(from {p} package)"])
                continue
            gap = max(1, 80 - len(f) - len(st))
            d.line(f + " " * gap + st, "row", [f, st])
        return d
    bad = [(p, f) for p, f in files if rng.random() < .3] or files[:2]
    bad += [(rng.choice(["openssh-server", "sudo", "libpam-runtime", "auditd", "login", "base-files"]), c)
            for c in rng.sample(CONF, rng.randint(0, 3))]
    if len(bad) < 2:
        bad.append(("login", "/etc/login.defs"))
    for p, f in bad:
        if mode == "changed":
            d.line(f, "row", [f])
        else:
            what = rng.choice(["changed", "changed", "missing"])
            d.line(f"debsums: {what} file {f} (from {p} package)", "row",
                   ["debsums", f"{what} file", f, f"(from {p} package)"])
    return d
