"""`wevtutil qe <log> /c:N /rd:true /f:text`: one `Event[N]:` block per
event, indented `Key: value` lines, and the description text on the lines
after `Description:`."""
from lib import Doc, fake

TOOL = "wevtutil-qe"

EVENTS = {
    "System": [
        ("Microsoft-Windows-Kernel-General", "16", "Information", "None", "Info",
         ["The access history in hive \\??\\C:\\Users\\{u}\\AppData\\Local\\Packages\\Microsoft.Windows.Search_cw5n1h2txyewy\\Settings\\settings.dat was cleared updating {n} keys and creating {m} modified pages."]),
        ("Service Control Manager", "7036", "Information", "None", "Info",
         ["The {svc} service entered the {state} state."]),
        ("Microsoft-Windows-Time-Service", "35", "Information", "None", "Info",
         ["The time service is now synchronizing the system time with the time source time.windows.com,0x9 (ntp.m|0x9|0.0.0.0:123->{ip}:123) with reference id {n}. Current local stratum number is 4."]),
        ("Microsoft-Windows-DistributedCOM", "10016", "Warning", "None", "Info",
         ["The application-specific permission settings do not grant Local Activation permission for the COM Server application with CLSID ",
          "{{{g}}}",
          " and APPID ",
          "Unavailable",
          " to the user NT AUTHORITY\\SYSTEM SID (S-1-5-18) from address LocalHost (Using LRPC) running in the application container Unavailable SID (Unavailable). This security permission can be modified using the Component Services administrative tool."]),
        ("disk", "153", "Warning", "None", "Info",
         ["The IO operation at logical block address 0x{h} for Disk 1 (PDO name: \\Device\\0000003{m}) was retried."]),
        ("Microsoft-Windows-WindowsUpdateClient", "19", "Information", "Windows Update Agent", "Installation",
         ["Installation Successful: Windows successfully installed the following update: 2026-10 Cumulative Update for Windows 11 Version 24H2 for x64-based Systems (KB50{n})"]),
    ],
    "Application": [
        ("Application Error", "1000", "Error", "Application Crashing Events", "Info",
         ["Faulting application name: {exe}, version: {v}, time stamp: 0x{h}",
          "Faulting module name: ntdll.dll, version: 10.0.26100.1, time stamp: 0x{h}",
          "Exception code: 0xc0000005",
          "Fault offset: 0x00000000000{n}",
          "Faulting process id: 0x{h}"]),
        ("Microsoft-Windows-Security-SPP", "16384", "Information", "None", "Info",
         ["Successfully scheduled Software Protection service for re-start at 2026-10-26T0{m}:12:44Z. Reason: RulesEngine."]),
        ("MsiInstaller", "11707", "Information", "None", "Info",
         ["Product: {app} -- Installation completed successfully."]),
        ("ESENT", "916", "Information", "General", "Info",
         ["svchost ({n},G,98) The beta feature EseDiskFlushConsistency is enabled in ESENT due to the beta site mode settings 0x800000."]),
    ],
    "Security": [
        ("Microsoft-Windows-Security-Auditing", "4624", "Information", "Logon", "Info",
         ["An account was successfully logged on.", "", "Subject:", "\tSecurity ID:\t\tS-1-5-18",
          "\tAccount Name:\t\t{host}$", "\tLogon ID:\t\t0x3E7", "", "Logon Type:\t\t\t{m}"]),
        ("Microsoft-Windows-Security-Auditing", "4672", "Information", "Special Logon", "Info",
         ["Special privileges assigned to new logon."]),
    ],
}


def _date(rng):
    y, mo, dd = 2026, rng.randint(1, 10), rng.randint(1, 28)
    t = f"{y}-{mo:02d}-{dd:02d}T{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
    return t + rng.choice([f".{rng.randint(0, 9999999):07d}Z", f".{rng.randint(0, 999):03d}", ""])


def generate(rng):
    d = Doc()
    log = rng.choice(list(EVENTS))
    host = rng.choice(["DESKTOP-", "LAPTOP-", "WS-", "SRV-"]) + fake.token(rng, 7).upper()
    fqdn = host + (rng.choice(["", ".corp.example.com", ".ad.local"]) if rng.random() < .5 else "")
    for i in range(rng.randint(1, 5)):
        src, eid, level, task, opcode, desc = rng.choice(EVENTS[log])
        if rng.random() < .1:
            level = rng.choice(["Error", "Critical", "Warning"])
        user = rng.choice([("S-1-5-18", "NT AUTHORITY\\SYSTEM"), ("N/A", None),
                           ("S-1-5-19", "NT AUTHORITY\\LOCAL SERVICE"),
                           ("S-1-5-21-" + "-".join(str(rng.randint(10 ** 8, 4 * 10 ** 9)) for _ in range(3)) + "-1001",
                            host.lower() + "\\" + fake.user(rng))])
        fill = dict(u=fake.user(rng), n=rng.randint(1, 99999), m=rng.randint(1, 9), ip=fake.ip(rng),
                    svc=rng.choice(["Windows Update", "Background Intelligent Transfer Service",
                                    "WinHTTP Web Proxy Auto-Discovery Service", "Print Spooler"]),
                    state=rng.choice(["running", "stopped"]), g=fake.uuid(rng).upper(), h=fake.hexid(rng, 8),
                    exe=rng.choice(["explorer.exe", "OUTLOOK.EXE", "chrome.exe", "Teams.exe"]),
                    v=f"10.0.{rng.randint(19000, 26200)}.{rng.randint(1, 5000)}", host=host,
                    app=rng.choice(["Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.40.33810", "7-Zip 24.08 (x64)"]))
        d.line(f"Event[{i}]:", "section", [f"Event[{i}]"])
        pairs = [("Log Name", log), ("Source", src), ("Date", _date(rng)), ("Event ID", eid),
                 ("Task", task if task != "None" else "N/A"), ("Level", level), ("Opcode", opcode),
                 ("Keyword", rng.choice(["N/A", "Classic", "N/A"]) if log != "Security" else "Audit Success"),
                 ("User", user[0])]
        if user[1]:
            pairs.append(("User Name", user[1]))
        pairs.append(("Computer", fqdn))
        for k, v in pairs:
            d.kv(k, v, indent="  ")
        text = "".join(desc) if desc[0].startswith("The application-specific") else None
        lines = [text] if text else desc
        lines = [x.format(**fill) for x in lines]
        if len(lines) == 1 and rng.random() < .25:
            d.kv("Description", lines[0], indent="  ")
        else:
            d.line("  Description: ", "kv", ["Description"])
            for x in lines:
                if not x.strip():
                    d.blank()
                elif "\t" in x and x.strip().split(":")[0] and ":\t" in x:
                    k, v = x.split(":", 1)
                    d.line(x, "kv", [k.strip(), v.strip()])
                elif x.startswith("Faulting") or x.startswith("Exception") or x.startswith("Fault "):
                    cells = [c for seg in x.split(", ") for c in seg.split(": ", 1)]
                    d.line(x, "kv" if len(cells) == 2 else "row", cells)
                elif x.endswith(":"):
                    d.section(x)
                else:
                    d.line(x, "cont", [x])
        d.blank()
    return d
