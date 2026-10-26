"""cmd `tasklist` (plain, /v or /svc): fixed-width columns under a `====`
rule, right-aligned PID / Session# / `Mem Usage` with thousands separators
and a `K` unit, image names cut at 25 chars, and /svc service lists that wrap
onto continuation lines."""
from lib import Doc, fake

TOOL = "tasklist"

PROCS = [("System Idle Process", None), ("System", None), ("Registry", None), ("smss.exe", None),
         ("csrss.exe", None), ("wininit.exe", None), ("services.exe", None), ("lsass.exe", "KeyIso, SamSs, VaultSvc"),
         ("svchost.exe", "BrokerInfrastructure, DcomLaunch, PlugPlay, Power, SystemEventsBroker"),
         ("svchost.exe", "RpcEptMapper, RpcSs"), ("svchost.exe", "Dnscache"), ("svchost.exe", "Schedule"),
         ("svchost.exe", "LanmanWorkstation"), ("svchost.exe", "EventLog"), ("svchost.exe", "wuauserv"),
         ("svchost.exe", "Appinfo, gpsvc, ProfSvc, SENS, ShellHWDetection, Themes, UserManager, Winmgmt"),
         ("spoolsv.exe", "Spooler"), ("MsMpEng.exe", "WinDefend"), ("winlogon.exe", None), ("dwm.exe", None),
         ("explorer.exe", None), ("fontdrvhost.exe", None), ("RuntimeBroker.exe", None), ("sihost.exe", None),
         ("SearchHost.exe", None), ("StartMenuExperienceHost.exe", None), ("ShellExperienceHost.exe", None),
         ("TextInputHost.exe", None), ("ctfmon.exe", None), ("conhost.exe", None), ("cmd.exe", None),
         ("powershell.exe", None), ("WindowsTerminal.exe", None), ("OpenConsole.exe", None),
         ("chrome.exe", None), ("msedge.exe", None), ("Code.exe", None), ("Teams.exe", None),
         ("OneDrive.exe", None), ("SecurityHealthSystray.exe", None), ("SecurityHealthService.exe", "SecurityHealthService"),
         ("Microsoft.Photos.exe", None), ("ApplicationFrameHost.exe", None), ("NVDisplay.Container.exe", "NVDisplay.ContainerLocalSystem"),
         ("vmmem", None), ("wslservice.exe", "WSLService"), ("sqlservr.exe", "MSSQLSERVER"), ("tasklist.exe", None),
         ("WmiPrvSE.exe", None), ("dllhost.exe", None), ("audiodg.exe", None), ("SgrmBroker.exe", "SgrmBroker")]

TITLES = ["N/A", "N/A", "N/A", "OleMainThreadWndName", "Task Manager", "Windows PowerShell",
          "Command Prompt - tasklist /v", "Inbox - alice@example.com - Outlook", "Program Manager",
          "MSCTFIME UI", "Default IME", "README.md - provost - Visual Studio Code", "Settings"]


def _mem(rng):
    return f"{rng.choice([rng.randint(8, 999), rng.randint(1000, 99999), rng.randint(100000, 2400000)]):,} K"


def generate(rng):
    d = Doc()
    mode = rng.choice(["plain", "plain", "v", "svc"])
    host = "DESKTOP-" + fake.token(rng, 7).upper()
    user = host + "\\" + fake.user(rng)
    if mode == "svc":
        cols = [("Image Name", 25, False), ("PID", 8, True), ("Services", 44, False)]
    else:
        cols = [("Image Name", 25, False), ("PID", 8, True), ("Session Name", 16, False),
                ("Session#", 11, True), ("Mem Usage", 12, True)]
        if mode == "v":
            cols += [("Status", 15, False), ("User Name", 50, False), ("CPU Time", 12, True),
                     ("Window Title", 72, False)]

    def render(vals):
        out = []
        for (name, w, right), v in zip(cols, vals):
            v = v or ""
            out.append(v.rjust(w) if right else v.ljust(w))
        return " ".join(out).rstrip()

    d.blank()
    names = [c[0] for c in cols]
    d.line(render(names), "header", names)
    d.skip(" ".join("=" * c[1] for c in cols))
    pid = 0
    usess = rng.choice([("Console", "1"), ("Console", "1"), ("Console", "2"), (f"RDP-Tcp#{rng.randint(0, 40)}", str(rng.randint(2, 6)))])
    procs = PROCS[:4] + sorted(rng.sample(PROCS[4:], rng.randint(3, 22)), key=lambda _: rng.random())
    for i, (img, svcs) in enumerate(procs):
        pid = 0 if i == 0 else (4 if i == 1 else pid + rng.choice([4, 8, 12, 16, 40, 120, 400, 1200]))
        img = img[:25]
        if mode == "svc":
            svc = svcs or "N/A"
            parts, lines = svc.split(", "), [""]
            for p in parts:
                piece = (", " if lines[-1] else "") + p
                if len(lines[-1]) + len(piece) > 44:
                    lines[-1] += ","
                    lines.append(p)
                else:
                    lines[-1] += piece
            d.line(render([img, str(pid), lines[0]]), "row", [img, str(pid), lines[0]])
            for x in lines[1:]:
                d.line(" " * 35 + x, "cont", [x])
            continue
        services = i < 4 or svcs is not None or rng.random() < .25
        sess, sno = ("Services", "0") if services else usess
        vals = [img, str(pid), sess, sno, _mem(rng)]
        if mode == "v":
            u = "NT AUTHORITY\\SYSTEM" if services and rng.random() < .6 else (
                "N/A" if services else user)
            if services and u != "N/A" and rng.random() < .3:
                u = rng.choice(["NT AUTHORITY\\LOCAL SERVICE", "NT AUTHORITY\\NETWORK SERVICE"])
            cpu = f"{rng.choice([0, 0, 0, 1, 12])}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
            title = "N/A" if services else rng.choice(TITLES)
            vals += [rng.choice(["Running", "Running", "Unknown", "Not Responding"]) if not services else "Unknown",
                     u, cpu, title]
        d.line(render(vals), "row", vals)
    return d
