"""cmd `whoami /all` (or /user, /groups, /priv): upper-case section titles
underlined with dashes, each holding a table whose `====` rule spans its
columns (Group Name / Type / SID / Attributes, Privilege Name / Description /
State), empty Attributes cells, and a closing claims/Kerberos note."""
from lib import Doc, fake

TOOL = "whoami-all"

GROUPS = [("Everyone", "Well-known group", "S-1-1-0"),
          ("NT AUTHORITY\\Local account and member of Administrators group", "Well-known group", "S-1-5-114"),
          ("BUILTIN\\Administrators", "Alias", "S-1-5-32-544"),
          ("BUILTIN\\Users", "Alias", "S-1-5-32-545"),
          ("BUILTIN\\Performance Log Users", "Alias", "S-1-5-32-559"),
          ("BUILTIN\\Remote Desktop Users", "Alias", "S-1-5-32-555"),
          ("NT AUTHORITY\\INTERACTIVE", "Well-known group", "S-1-5-4"),
          ("CONSOLE LOGON", "Well-known group", "S-1-2-1"),
          ("NT AUTHORITY\\Authenticated Users", "Well-known group", "S-1-5-11"),
          ("NT AUTHORITY\\This Organization", "Well-known group", "S-1-5-15"),
          ("NT AUTHORITY\\Local account", "Well-known group", "S-1-5-113"),
          ("LOCAL", "Well-known group", "S-1-2-0"),
          ("NT AUTHORITY\\NTLM Authentication", "Well-known group", "S-1-5-64-10"),
          ("Authentication authority asserted identity", "Well-known group", "S-1-18-1"),
          ("CORP\\Domain Users", "Group", "S-1-5-21-1004336348-1177238915-682003330-513"),
          ("CORP\\VPN-Users", "Group", "S-1-5-21-1004336348-1177238915-682003330-4211")]

ATTRS = ["Mandatory group, Enabled by default, Enabled group",
         "Mandatory group, Enabled by default, Enabled group",
         "Group used for deny only",
         "Mandatory group, Enabled by default, Enabled group, Group owner"]

PRIVS = [("SeShutdownPrivilege", "Shut down the system"),
         ("SeChangeNotifyPrivilege", "Bypass traverse checking"),
         ("SeUndockPrivilege", "Remove computer from docking station"),
         ("SeIncreaseWorkingSetPrivilege", "Increase a process working set"),
         ("SeTimeZonePrivilege", "Change the time zone"),
         ("SeSecurityPrivilege", "Manage auditing and security log"),
         ("SeBackupPrivilege", "Back up files and directories"),
         ("SeRestorePrivilege", "Restore files and directories"),
         ("SeDebugPrivilege", "Debug programs"),
         ("SeImpersonatePrivilege", "Impersonate a client after authentication"),
         ("SeCreateSymbolicLinkPrivilege", "Create symbolic links"),
         ("SeDelegateSessionUserImpersonatePrivilege", "Obtain an impersonation token for another user in the same session")]


def _section(d, title):
    d.blank()
    d.section(title)
    d.skip("-" * len(title))
    d.blank()


def _table(d, header, rows):
    d.table(header, rows, gap=1, rule="=")


def generate(rng):
    d = Doc()
    what = rng.choice(["all", "all", "all", "groups", "priv", "user"])
    dom = rng.choice(["corp", "desktop-" + fake.token(rng, 7), "laptop-" + fake.token(rng, 7)])
    user = f"{dom}\\{fake.user(rng)}"
    sid = "S-1-5-21-" + "-".join(str(rng.randint(10 ** 8, 4 * 10 ** 9)) for _ in range(3)) + f"-{rng.randint(1000, 9999)}"
    if what in ("all", "user"):
        _section(d, "USER INFORMATION")
        _table(d, ["User Name", "SID"], [[user, sid]])
        d.blank()
    if what in ("all", "groups"):
        _section(d, "GROUP INFORMATION")
        picks = [g for g in GROUPS if rng.random() < .6] or GROUPS[:2]
        rows = [[n, t, s, rng.choice(ATTRS)] for n, t, s in picks]
        lvl = rng.choice([("Mandatory Label\\Medium Mandatory Level", "S-1-16-8192"),
                          ("Mandatory Label\\High Mandatory Level", "S-1-16-12288")])
        rows.append([lvl[0], "Label", lvl[1], None])
        _table(d, ["Group Name", "Type", "SID", "Attributes"], rows)
        d.blank()
    if what in ("all", "priv"):
        _section(d, "PRIVILEGES INFORMATION")
        picks = [p for p in PRIVS if rng.random() < .5] or PRIVS[:2]
        rows = [[n, desc, "Enabled" if n == "SeChangeNotifyPrivilege" or rng.random() < .3 else "Disabled"] for n, desc in picks]
        _table(d, ["Privilege Name", "Description", "State"], rows)
        d.blank()
    if what == "all":
        _section(d, "USER CLAIMS INFORMATION")
        d.skip("User claims unknown.")
        d.blank()
        d.skip(rng.choice(["Kerberos support for Dynamic Access Control on this device has been disabled.",
                           "Kerberos support for Dynamic Access Control on this device has been disabled."]))
    return d
