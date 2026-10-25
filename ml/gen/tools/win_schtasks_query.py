"""cmd `schtasks /query` (TABLE, or /fo LIST /v): `Folder: \\path` headings,
each followed by a fixed-width TaskName / Next Run Time / Status table under
a `====` rule or an INFO line; the LIST form is aligned `Key:  value` blocks."""
from lib import Doc, fake

TOOL = "schtasks-query"

FOLDERS = {
    "\\": ["MicrosoftEdgeUpdateTaskMachineCore", "MicrosoftEdgeUpdateTaskMachineUA", "GoogleUpdateTaskMachineCore{4A1B2C3D-0E5F-4A6B-8C7D-9E0F1A2B3C4D}",
           "OneDrive Reporting Task-S-1-5-21-3623811015-3361044348-30300820-1013",
           "OneDrive Standalone Update Task-S-1-5-21-3623811015-3361044348-30300820-1013",
           "Adobe Acrobat Update Task", "npcapwatchdog", "ZoomUpdateTaskUser-S-1-5-21-1004", "backup-nightly",
           "CCleaner Update"],
    "\\Microsoft": [],
    "\\Microsoft\\Windows": [],
    "\\Microsoft\\Windows\\Defrag": ["ScheduledDefrag"],
    "\\Microsoft\\Windows\\Diagnosis": ["RecommendedTroubleshootingScanner", "Scheduled", "UnexpectedCodepath"],
    "\\Microsoft\\Windows\\Windows Defender": ["Windows Defender Cache Maintenance", "Windows Defender Cleanup",
                                               "Windows Defender Scheduled Scan", "Windows Defender Verification"],
    "\\Microsoft\\Windows\\UpdateOrchestrator": ["Report policies", "Schedule Maintenance Work", "Schedule Scan",
                                                 "Schedule Scan Static Task", "UpdateModelTask", "USO_UxBroker"],
    "\\Microsoft\\Windows\\WindowsUpdate": ["Refresh Group Policy Cache", "Scheduled Start"],
    "\\Microsoft\\Windows\\Time Synchronization": ["ForceSynchronizeTime", "SynchronizeTime"],
    "\\Microsoft\\Windows\\Maintenance": ["WinSAT"],
    "\\Microsoft\\Office": ["Office Automatic Updates 2.0", "Office ClickToRun Service Monitor",
                            "Office Feature Updates", "Office Feature Updates Logon"],
}


def _when(rng):
    if rng.random() < .3:
        return "N/A"
    h = rng.randint(1, 12)
    return f"{rng.randint(10, 12)}/{rng.randint(1, 28)}/2026 {h}:{rng.randint(0, 59):02d}:00 {rng.choice(['AM', 'PM'])}"


def _status(rng):
    return rng.choices(["Ready", "Running", "Disabled", "Queued", "Could not start"], [12, 2, 3, 1, 1])[0]


def generate(rng):
    d = Doc()
    host = rng.choice(["DESKTOP-", "SRV-"]) + fake.token(rng, 7).upper()
    keys = sorted(FOLDERS)
    folders = [k for k in keys if rng.random() < .55] or ["\\"]
    if rng.random() < .3:
        # /fo LIST /v for a few tasks
        todo = [(f, t) for f in folders for t in FOLDERS[f][:rng.randint(1, 2)]]
        pad = rng.choice([38, 38, 38, 0])
        for f, t in todo[:rng.randint(1, 4)]:
            if True:
                path = (f.rstrip("\\") + "\\" + t) if f != "\\" else "\\" + t
                pairs = [("HostName", host), ("TaskName", path), ("Next Run Time", _when(rng)),
                         ("Status", _status(rng)),
                         ("Logon Mode", rng.choice(["Interactive/Background", "Interactive only", "Background only"])),
                         ("Last Run Time", rng.choice(["11/30/1999 12:00:00 AM", _when(rng).replace("N/A", "10/1/2026 3:00:00 AM")])),
                         ("Last Result", rng.choice(["0", "267011", "267009", "-2147020576", "1"])),
                         ("Author", rng.choice(["Microsoft Corporation", "N/A", host + "\\" + fake.user(rng), "$(@%SystemRoot%\\system32\\defrag.exe,-1001)"])),
                         ("Task To Run", rng.choice(["%windir%\\system32\\defrag.exe -c -h -o -$", "COM handler",
                                                     "\"C:\\Program Files (x86)\\Microsoft\\EdgeUpdate\\MicrosoftEdgeUpdate.exe\" /c",
                                                     "C:\\scripts\\backup.cmd"])),
                         ("Start In", rng.choice(["N/A", "C:\\scripts"])),
                         ("Comment", rng.choice(["N/A", "Keeps your Microsoft software up to date.",
                                                 "This task optimizes local storage drives."])),
                         ("Scheduled Task State", rng.choice(["Enabled", "Enabled", "Disabled"])),
                         ("Run As User", rng.choice(["SYSTEM", "Users", "LOCAL SERVICE", fake.user(rng)])),
                         ("Schedule Type", rng.choice(["Daily ", "Weekly", "At logon time", "One Time Only", "On idle"]).strip()),
                         ("Start Time", rng.choice(["N/A", "3:00:00 AM", "12:15:00 PM"])),
                         ("Start Date", rng.choice(["N/A", "1/1/2024", "6/14/2025"])),
                         ("Repeat: Every", rng.choice(["Disabled", "1 Hour(s), 0 Minute(s)", "0 Hour(s), 30 Minute(s)"])),
                         ("Repeat: Until: Time", rng.choice(["Disabled", "None"])),
                         ("Repeat: Stop If Still Running", "Disabled")]
                d.blank()
                for k, v in pairs[:rng.randint(8, len(pairs))]:
                    d.line((k + ":").ljust(pad or len(k) + 2) + v, "kv", [k, v])
        return d
    for f in folders:
        d.blank()
        d.section(f"Folder: {f}", f"Folder: {f}")
        tasks = FOLDERS[f]
        if not tasks:
            d.skip("INFO: There are no scheduled tasks presently available at your access level.")
            continue
        tasks = sorted(rng.sample(tasks, rng.randint(1, len(tasks))))
        hdr = ["TaskName", "Next Run Time", "Status"]
        d.line("TaskName".ljust(40) + " " + "Next Run Time".ljust(22) + " " + "Status", "header", hdr)
        d.skip("=" * 40 + " " + "=" * 22 + " " + "=" * 15)
        for t in tasks:
            name = t[:40]
            when, st = _when(rng), _status(rng)
            if st == "Disabled":
                when = "N/A"
            d.line((name.ljust(40) + " " + when.ljust(22) + " " + st).rstrip(), "row", [name, when, st])
    return d
