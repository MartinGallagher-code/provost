"""smartmontools `smartd` messages as syslog / `journalctl -u smartd` lines:
timestamp, host, `smartd[pid]:`, then a free-text message (startup banner,
device registration, attribute changes, temperature and pending-sector
warnings, state file writes)."""
from lib import Doc, fake

TOOL = "smartd-log"

MODELS = [("WDC WD40EFRX-68N32N0", "WD-WCC7K", "4.00 TB", "Western Digital Red"),
          ("ST4000VN008-2DR166", "ZGY", "4.00 TB", "Seagate IronWolf"),
          ("Samsung SSD 870 EVO 1TB", "S6PTNM0", "1.00 TB", "Samsung based SSDs"),
          ("TOSHIBA MG08ACA16TE", "X0L0A", "16.0 TB", "Toshiba MG08ACA... Enterprise Capacity HDD"),
          ("CT1000MX500SSD1", "2117E", "1.00 TB", "Crucial/Micron Client SSDs"),
          ("HGST HUH721010ALE604", "7JG", "10.0 TB", "HGST Ultrastar He10")]
ATTRS = [("Prefailure", "1 Raw_Read_Error_Rate"), ("Usage", "190 Airflow_Temperature_Cel"),
         ("Usage", "194 Temperature_Celsius"), ("Prefailure", "7 Seek_Error_Rate"),
         ("Usage", "195 Hardware_ECC_Recovered"), ("Prefailure", "3 Spin_Up_Time"),
         ("Usage", "199 UDMA_CRC_Error_Count"), ("Prefailure", "5 Reallocated_Sector_Ct")]


def generate(rng):
    d = Doc()
    host = rng.choice([fake.host(rng).split(".")[0], "nas", "pve01", "truenas", "fileserver", "backup-01"])
    pid = str(rng.randint(300, 99999))
    mon, day = rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()), rng.randint(1, 28)
    t = rng.randint(0, 20000)
    devs = [f"/dev/sd{c}" for c in "abcdefgh"[:rng.randint(1, 6)]]
    nvme = rng.random() < .4
    info = {dv: rng.choice(MODELS) for dv in devs}
    journal = rng.random() < .3
    prog = "smartd"

    def emit(msg, quick=False):
        nonlocal t
        t += rng.choice([0, 0, 1]) if quick else rng.choice([0, 0, 0, 1, rng.randint(1, 1800)])
        ts = f"{mon} {day:2d} {t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}"
        d.line(f"{ts} {host} {prog}[{pid}]: {msg}", "row", [ts, host, prog, pid, msg])

    if journal:
        d.skip(f"-- Logs begin at {rng.choice(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])} 2026-0{rng.randint(1, 9)}-1{rng.randint(0, 9)} 0{rng.randint(0, 9)}:12:01 UTC, end at {rng.choice(['Mon', 'Fri'])} 2026-10-2{rng.randint(0, 5)} 1{rng.randint(0, 9)}:40:02 UTC. --")
    startup = rng.random() < .6
    if startup:
        ver = rng.choice(["7.2 2020-12-30 r5155", "7.3 2022-02-28 r5338", "7.4 2023-08-01 r5530"])
        emit(quick=True, msg=f"smartd {ver} [x86_64-linux-{rng.choice(['5.15.0-91-generic', '6.1.0-18-amd64', '6.8.12-4-pve'])}] (local build)")
        emit(quick=True, msg="Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org")
        emit(quick=True, msg="Opened configuration file /etc/smartd.conf")
        emit(quick=True, msg="Configuration file /etc/smartd.conf was parsed, found DEVICESCAN, scanning devices")
        for dv in devs:
            model, sn, cap, db = info[dv]
            serial = sn + fake.hexid(rng, 6).upper()
            emit(quick=True, msg=f"Device: {dv}, type changed from 'scsi' to 'sat'")
            emit(quick=True, msg=f"Device: {dv} [SAT], opened")
            emit(quick=True, msg=f"Device: {dv} [SAT], {model}, S/N:{serial}, WWN:5-{fake.hexid(rng, 6)}-{fake.hexid(rng, 9)}, FW:{rng.choice(['82.00A82', 'SC60', 'SVQ02B6Q', '0105', 'M022'])}, {cap}")
            emit(quick=True, msg=f"Device: {dv} [SAT], found in smartd database {ver.split()[0]}/{rng.randint(5100, 5600)}: {db}")
            emit(quick=True, msg=f"Device: {dv} [SAT], is SMART capable. Adding to \"monitor\" list.")
            if rng.random() < .5:
                emit(quick=True, msg=f"Device: {dv} [SAT], state read from /var/lib/smartmontools/smartd.{model.replace(' ', '_')}-{serial}.ata.state")
        if nvme:
            emit(quick=True, msg="Device: /dev/nvme0, opened")
            emit(quick=True, msg=f"Device: /dev/nvme0, {rng.choice(['Samsung SSD 980 PRO 1TB', 'WD_BLACK SN770 2TB', 'KINGSTON SNV2S1000G'])}, S/N:{fake.hexid(rng, 14).upper()}, FW:{rng.choice(['5B2QGXA7', '731100WD', 'SBM02103'])}, 1.00 TB")
            emit(quick=True, msg="Device: /dev/nvme0, is SMART capable. Adding to \"monitor\" list.")
        emit(quick=True, msg=f"Monitoring {len(devs)} ATA/SATA, 0 SCSI/SAS and {int(nvme)} NVMe devices")
    for _ in range(rng.randint(2, 18)):
        dv = rng.choice(devs)
        k = rng.random()
        if k < .45:
            kind, attr = rng.choice(ATTRS)
            a = rng.randint(20, 253)
            b = a + rng.choice([-2, -1, 1, 2, 3])
            emit(f"Device: {dv} [SAT], SMART {kind} Attribute: {attr} changed from {a} to {b}")
        elif k < .6:
            c = rng.randint(30, 61)
            emit(f"Device: {dv} [SAT], Temperature {c} Celsius reached limit of {rng.choice([45, 50, 55])} Celsius (Min/Max {rng.randint(18, 29)}/{c})"
                 if rng.random() < .5 else f"Device: {dv} [SAT], Temperature changed {rng.choice(['+', '-'])}{rng.randint(1, 5)} Celsius to {c} Celsius (Min/Max {rng.randint(18, 29)}/{c + rng.randint(0, 8)})")
        elif k < .72:
            n = rng.randint(1, 900)
            emit(rng.choice([f"Device: {dv} [SAT], {n} Currently unreadable (pending) sectors",
                             f"Device: {dv} [SAT], {n} Offline uncorrectable sectors",
                             f"Device: {dv} [SAT], ATA error count increased from {n} to {n + rng.randint(1, 4)}"]))
        elif k < .85:
            model, sn, _, _ = info[dv]
            emit(f"Device: {dv} [SAT], state written to /var/lib/smartmontools/smartd.{model.replace(' ', '_')}-{sn}.ata.state")
        elif k < .93:
            emit(f"Device: {dv} [SAT], starting scheduled {rng.choice(['Short', 'Long', 'Offline'])} Self-Test.")
        else:
            emit(f"Device: {dv} [SAT], previous self-test completed without error"
                 if rng.random() < .7 else f"Device: {dv} [SAT], Self-Test Log error count increased from 0 to 1")
    return d
