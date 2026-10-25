"""Samba `testparm -s` / `testparm -sv`: load messages and warnings on
stderr, `Server role: ...`, then the effective smb.conf as `[share]`
sections of tab-indented `key = value` lines."""
from lib import Doc, fake

TOOL = "testparm-s"

GLOBAL = [("workgroup", lambda r: r.choice(["WORKGROUP", "EXAMPLE", "CORP", "HOME", "SAMBA"])),
          ("server string", lambda r: r.choice(["%h server (Samba, Ubuntu)", "Samba %v", "NAS", "File Server"])),
          ("netbios name", lambda r: r.choice(["NAS01", "FILESRV", "STORAGE", "TRUENAS"])),
          ("log file", lambda r: "/var/log/samba/log.%m"),
          ("max log size", lambda r: r.choice(["1000", "50", "5000"])),
          ("logging", lambda r: "file"),
          ("map to guest", lambda r: "Bad User"),
          ("obey pam restrictions", lambda r: "Yes"),
          ("pam password change", lambda r: "Yes"),
          ("panic action", lambda r: "/usr/share/samba/panic-action %d"),
          ("passwd chat", lambda r: "*Enter\\snew\\s*\\spassword:* %n\\n *Retype\\snew\\s*\\spassword:* %n\\n *password\\supdated\\ssuccessfully* ."),
          ("passwd program", lambda r: "/usr/bin/passwd %u"),
          ("security", lambda r: r.choice(["USER", "ADS"])),
          ("realm", lambda r: r.choice(["EXAMPLE.COM", "CORP.LAN", "AD.EXAMPLE.ORG"])),
          ("server min protocol", lambda r: r.choice(["SMB2_10", "SMB3", "SMB2"])),
          ("server role", lambda r: "standalone server"),
          ("unix password sync", lambda r: "Yes"),
          ("usershare allow guests", lambda r: "Yes"),
          ("idmap config * : backend", lambda r: "tdb"),
          ("idmap config * : range", lambda r: "3000-7999"),
          ("winbind enum users", lambda r: r.choice(["Yes", "No"])),
          ("fruit:metadata", lambda r: "stream"),
          ("vfs objects", lambda r: r.choice(["catia fruit streams_xattr", "acl_xattr", "shadow_copy2"])),
          ("printcap name", lambda r: r.choice(["cups", "/dev/null"])),
          ("load printers", lambda r: "No"),
          ("disable spoolss", lambda r: "Yes")]

SHARE = [("comment", lambda r: r.choice(["Home Directories", "Public files", "Team share", "Time Machine backups",
                                         "All Printers", "Media library", fake.word(r).title() + " data"])),
         ("path", lambda r: fake.path(r)),
         ("browseable", lambda r: r.choice(["No", "Yes"])),
         ("read only", lambda r: r.choice(["No", "Yes"])),
         ("guest ok", lambda r: r.choice(["Yes", "No"])),
         ("valid users", lambda r: r.choice(["%S", "@staff", "@" + fake.word(r), f"{fake.user(r)} {fake.user(r)}"])),
         ("write list", lambda r: "@" + fake.word(r)),
         ("create mask", lambda r: r.choice(["0700", "0664", "0644", "0775"])),
         ("directory mask", lambda r: r.choice(["0700", "0775", "0755"])),
         ("force user", lambda r: fake.user(r)),
         ("force group", lambda r: r.choice(["users", "staff", fake.word(r)])),
         ("fruit:time machine", lambda r: "Yes"),
         ("fruit:time machine max size", lambda r: r.choice(["1T", "500G", "2T"])),
         ("inherit permissions", lambda r: "Yes"),
         ("hide dot files", lambda r: "No"),
         ("veto files", lambda r: "/._*/.DS_Store/"),
         ("printable", lambda r: "Yes")]


def generate(rng):
    d = Doc()
    conf = rng.choice(["/etc/samba/smb.conf", "/etc/samba/smb.conf", "/usr/local/etc/smb4.conf"])
    d.skip(f"Load smb config files from {conf}")
    for _ in range(rng.choice([0, 0, 1, 2])):
        d.skip(rng.choice([
            "WARNING: The \"syslog\" option is deprecated",
            "WARNING: The 'netbios name' is too long (max. 15 chars).",
            "Unknown parameter encountered: \"client ntlmv2 auth\"",
            "Ignoring unknown parameter \"client ntlmv2 auth\"",
            "lp_load_ex: changing to config backend registry"]))
    if rng.random() < .2:
        d.skip(f"Processing section \"[{rng.choice(['homes', 'printers', 'public'])}]\"")
    d.skip("Loaded services file OK.")
    if rng.random() < .6:
        d.skip("Weak crypto is allowed by GnuTLS (e.g. NTLM as a compatibility fallback)")
    d.blank()
    d.kv("Server role", rng.choice(["ROLE_STANDALONE", "ROLE_STANDALONE", "ROLE_DOMAIN_MEMBER", "ROLE_ACTIVE_DIRECTORY_DC"]))
    d.blank()
    if rng.random() < .3:
        d.skip("Press enter to see a dump of your service definitions")
        d.blank()
    d.skip("# Global parameters")
    d.section("[global]")
    keys = sorted(rng.sample(GLOBAL, rng.randint(4, len(GLOBAL))), key=lambda kv: kv[0].lower())
    for k, f in keys:
        d.kv(k, f(rng), sep=" = ", indent="\t")
    shares = ["homes"] * (rng.random() < .7) + ["printers"] * (rng.random() < .4) + ["print$"] * (rng.random() < .2)
    shares += rng.sample(["public", "media", "backup", "timemachine", "scans", "projects", fake.word(rng), "share"],
                         rng.randint(0, 4))
    for s in dict.fromkeys(shares):
        d.blank()
        d.section(f"[{s}]")
        for k, f in sorted(rng.sample(SHARE, rng.randint(1, 7)), key=lambda kv: kv[0]):
            d.kv(k, f(rng), sep=" = ", indent="\t")
    return d
