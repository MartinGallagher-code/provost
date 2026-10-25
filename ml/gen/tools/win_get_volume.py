"""PowerShell `Get-Volume` (default Format-Table view): a blank line, the
header, a dash rule as long as each header name, right-aligned size columns,
and blank lines after."""
from lib import Doc

TOOL = "Get-Volume"

LABELS = ["OS", "Windows", "Data", "Recovery", "Backup", "SYSTEM", "Games", "Media",
          "Local Disk", "New Volume", "Archive 2024", "USB DRIVE", "WinRE tools", "Scratch"]


def _size(rng):
    n = rng.choice([rng.uniform(0, 999), rng.uniform(0, 99), rng.uniform(1, 9)])
    unit = rng.choice(["B", "KB", "MB", "GB", "GB", "GB", "TB"])
    if unit == "B" and rng.random() < .7:
        return "0 B"
    s = f"{n:.2f}".rstrip("0").rstrip(".") if rng.random() < .8 else str(int(n))
    return f"{s} {unit}"


def _ps_table(d, header, rows, right):
    ncol = len(header)
    width = [max([len(header[c])] + [len(r[c] or "") for r in rows]) for c in range(ncol)]

    def render(cells):
        out = []
        for c in range(ncol):
            v = cells[c] or ""
            out.append(v.rjust(width[c]) if c in right else v.ljust(width[c]))
        return " ".join(out).rstrip()

    d.line(render(header), "header", header)
    d.skip(render(["-" * len(h) for h in header]))
    for r in rows:
        d.line(render(r), "row", [v if v else None for v in r])


def generate(rng):
    d = Doc()
    modern = rng.random() < .6
    if modern:
        header = ["DriveLetter", "FriendlyName", "FileSystemType", "DriveType", "HealthStatus",
                  "OperationalStatus", "SizeRemaining", "Size"]
    else:
        header = ["DriveLetter", "FileSystemLabel", "FileSystem", "DriveType", "HealthStatus",
                  "OperationalStatus", "SizeRemaining", "Size"]
    letters = list("CDEFGHIJKLMNOPQRSTUVWXYZ")
    rows = []
    for i in range(rng.randint(1, 8)):
        letter = letters.pop(0) if rng.random() < .75 else None
        kind = rng.choices(["Fixed", "Removable", "CD-ROM", "Network"], [8, 2, 1, 1])[0]
        if kind == "CD-ROM":
            fs, label, rem, size = "Unknown", None, "0 B", "0 B"
            op = "Unknown"
        else:
            fs = rng.choice(["NTFS", "NTFS", "NTFS", "FAT32", "ReFS", "exFAT"]) if kind != "Network" else "NTFS"
            label = rng.choice(LABELS) if rng.random() < .85 else None
            rem, size = _size(rng), _size(rng)
            op = rng.choices(["OK", "Degraded", "Unknown"], [10, 1, 1])[0]
        if not letter and fs == "NTFS" and rng.random() < .5:
            label = rng.choice(["Recovery", "WinRE", None])
        health = rng.choices(["Healthy", "Warning", "Unhealthy", "Unknown"], [12, 1, 1, 1])[0]
        rows.append([letter, label, fs, kind, health, op, rem, size])
    d.blank()
    _ps_table(d, header, rows, right={6, 7})
    d.blank()
    if rng.random() < .7:
        d.blank()
    return d
