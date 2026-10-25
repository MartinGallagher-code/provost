"""cmd `sc query` / `sc queryex`: one block per service, `SERVICE_NAME:` and
`DISPLAY_NAME:` then indented `KEY : code  NAME` lines (one key, two values),
with the controls-accepted flags wrapped onto a continuation line."""
from lib import Doc

TOOL = "sc-query"

SERVICES = [("wuauserv", "Windows Update", 20), ("Spooler", "Print Spooler", 110),
            ("Dnscache", "DNS Client", 30), ("BITS", "Background Intelligent Transfer Service", 30),
            ("WinDefend", "Microsoft Defender Antivirus Service", 10), ("EventLog", "Windows Event Log", 30),
            ("LanmanServer", "Server", 30), ("LanmanWorkstation", "Workstation", 30),
            ("W32Time", "Windows Time", 30), ("WinRM", "Windows Remote Management (WS-Management)", 20),
            ("TermService", "Remote Desktop Services", 20), ("sshd", "OpenSSH SSH Server", 10),
            ("MSSQLSERVER", "SQL Server (MSSQLSERVER)", 10), ("Tcpip", "TCP/IP Protocol Driver", 1),
            ("AudioSrv", "Windows Audio", 20), ("Schedule", "Task Scheduler", 30),
            ("CDPUserSvc_4a1b2", "Connected Devices Platform User Service_4a1b2", 240),
            ("vmms", "Hyper-V Virtual Machine Management", 10), ("Netlogon", "Netlogon", 20),
            ("WSearch", "Windows Search", 10), ("gupdate", "Google Update Service (gupdate)", 10),
            ("NVDisplay.ContainerLocalSystem", "NVIDIA Display Container LS", 10)]

TYPES = {1: "KERNEL_DRIVER", 2: "FILE_SYSTEM_DRIVER", 10: "WIN32_OWN_PROCESS", 20: "WIN32_SHARE_PROCESS",
         30: "WIN32", 110: "WIN32_OWN_PROCESS  (interactive)", 240: "USER_SHARE_PROCESS INSTANCE"}

STATES = [("4", "RUNNING"), ("4", "RUNNING"), ("4", "RUNNING"), ("1", "STOPPED"), ("1", "STOPPED"),
          ("2", "START_PENDING"), ("3", "STOP_PENDING"), ("7", "PAUSED")]

FLAGS = ["(STOPPABLE, NOT_PAUSABLE, ACCEPTS_SHUTDOWN)", "(STOPPABLE, PAUSABLE, ACCEPTS_SHUTDOWN)",
         "(STOPPABLE, NOT_PAUSABLE, ACCEPTS_PRESHUTDOWN)", "(NOT_STOPPABLE, NOT_PAUSABLE, IGNORES_SHUTDOWN)",
         "(STOPPABLE, NOT_PAUSABLE, IGNORES_SHUTDOWN)"]

IND = " " * 8


def _kv(d, key, vals):
    head = IND + key.ljust(19) + ": "
    if not vals:
        d.line(head, "kv", [key])
    else:
        d.line(head + "  ".join(vals), "kv", [key] + vals)


def generate(rng):
    d = Doc()
    ex = rng.random() < .4
    if rng.random() < .15:
        d.line("[SC] EnumQueryServicesStatus:OpenService FAILED 1060:", "skip")
        d.blank()
        d.skip("The specified service does not exist as an installed service.")
        d.blank()
    for name, disp, t in rng.sample(SERVICES, rng.randint(1, 5)):
        d.blank()
        d.kv("SERVICE_NAME", name)
        if rng.random() < .85:
            d.kv("DISPLAY_NAME", disp)
        code, state = rng.choice(STATES) if t != 1 else ("4", "RUNNING")
        _kv(d, "TYPE", [str(t), TYPES[t]])
        _kv(d, "STATE", [code, state])
        if state != "STOPPED":
            fl = rng.choice(FLAGS) if t != 1 else "(STOPPABLE, NOT_PAUSABLE, IGNORES_SHUTDOWN)"
            d.line(" " * 32 + fl, "cont", [fl])
        if state == "STOPPED" and rng.random() < .4:
            err = rng.choice([("1077", "(0x435)"), ("1066", "(0x42a)"), ("0", "(0x0)")])
        else:
            err = ("0", "(0x0)")
        _kv(d, "WIN32_EXIT_CODE", list(err))
        _kv(d, "SERVICE_EXIT_CODE", ["0", "(0x0)"])
        _kv(d, "CHECKPOINT", ["0x0" if "PENDING" not in state else f"0x{rng.randint(1, 9)}"])
        _kv(d, "WAIT_HINT", ["0x0" if "PENDING" not in state else rng.choice(["0x7d0", "0xbb8", "0x4e20"])])
        if ex:
            pid = "0" if state == "STOPPED" else str(rng.randint(4, 30000) // 4 * 4)
            _kv(d, "PID", [pid])
            _kv(d, "FLAGS", [] if state != "RUNNING" or rng.random() < .8 else ["RUNS_IN_SYSTEM_PROCESS"])
    return d
