"""Samba `smbclient -L HOST [-N|-U user]`: tab-indented share list
(Sharename / Type / Comment, fixed widths, dashed rules), connection notes,
then optional Server and Workgroup tables from the SMB1 browse list."""
from lib import Doc, fake


TOOL = "smbclient-L"

SHARES = [("print$", "Disk", "Printer Drivers"), ("IPC$", "IPC", None), ("public", "Disk", "Public files"),
          ("homes", "Disk", "Home Directories"), ("media", "Disk", "Media library"), ("backup", "Disk", None),
          ("timemachine", "Disk", "Time Machine"), ("scans", "Disk", "Scanner drop folder"),
          ("Users", "Disk", None), ("C$", "Disk", "Default share"), ("ADMIN$", "Disk", "Remote Admin"),
          ("NETLOGON", "Disk", "Logon server share"), ("SYSVOL", "Disk", "Logon server share"),
          ("HP_LaserJet_M404", "Printer", "HP LaserJet Pro M404dn"), ("projects", "Disk", "Team projects"),
          ("photo", "Disk", "System default shared folder"), ("docker", "Disk", None), ("web", "Disk", None)]


def _t(d, cells, widths, header=False):
    text = "\t"
    for c, w in zip(cells[:-1], widths):
        text += (c or "").ljust(w - 1) + " " if w == 16 else (c or "").ljust(w)
    text += cells[-1] or ""
    d.line(text.rstrip() if not header else text, "header" if header else "row",
           cells if header else [c if c else None for c in cells])


def generate(rng):
    d = Doc()
    host = rng.choice(["NAS01", "FILESRV", "fileserver", fake.ip(rng), fake.host(rng), "DC01"])
    ver = rng.choice(["4.15.13-Ubuntu", "4.17.12-Debian", "4.19.5", "4.18.9-SerNet-RedHat", "4.20.2"])
    auth = rng.choice(["anon", "pw", "none"])
    if auth == "pw":
        d.line(f"Password for [{rng.choice(['WORKGROUP', 'CORP', 'EXAMPLE'])}\\{fake.user(rng)}]:", "skip")
    elif auth == "anon" and rng.random() < .5:
        d.skip("Anonymous login successful")
    d.blank()
    w = [16, 10]
    _t(d, ["Sharename", "Type", "Comment"], w, header=True)
    d.skip("\t---------       ----      -------")
    picked = rng.sample(SHARES, rng.randint(2, 9))
    if not any(s[0] == "IPC$" for s in picked):
        picked.append(("IPC$", "IPC", None))
    windows = any(s[0] in ("C$", "ADMIN$") for s in picked)
    for name, typ, comment in picked:
        if name == "IPC$":
            comment = "Remote IPC" if windows else f"IPC Service (Samba {ver})"
        if name == "homes" and rng.random() < .6:
            name = fake.user(rng)
        _t(d, [name, typ, comment], w)
    smb1 = rng.random() < .55
    if not smb1:
        d.skip("SMB1 disabled -- no workgroup available")
        return d
    d.skip("Reconnecting with SMB1 for workgroup listing.")
    if rng.random() < .3:
        d.skip(f"do_connect: Connection to {host} failed (Error NT_STATUS_RESOURCE_NAME_NOT_FOUND)")
        d.skip("Unable to connect with SMB1 -- no workgroup available")
        return d
    if rng.random() < .3:
        d.skip("Anonymous login successful")
    d.blank()
    w2 = [21]
    _t(d, ["Server", "Comment"], w2, header=True)
    d.skip("\t---------            -------")
    servers = rng.sample(["NAS01", "FILESRV", "PRINTSRV", "DESKTOP-" + fake.token(rng, 7).upper(), "RASPBERRYPI", "MEDIA", "BACKUP"],
                         rng.randint(0, 4))
    for s in servers:
        _t(d, [s, rng.choice([f"Samba {ver}", "", "nas server", "pi"])], w2)
    d.blank()
    _t(d, ["Workgroup", "Master"], w2, header=True)
    d.skip("\t---------            -------")
    for wg in rng.sample(["WORKGROUP", "HOME", "CORP", "MSHOME"], rng.randint(1, 2)):
        _t(d, [wg, rng.choice(servers or ["NAS01"]) if rng.random() < .9 else ""], w2)
    return d
