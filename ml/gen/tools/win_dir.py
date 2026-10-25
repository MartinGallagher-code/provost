"""cmd `dir` (optionally /s): volume label and serial lines, `Directory of`
headings, one entry per line (date and time as one stamp, `<DIR>` or a
right-aligned byte count with thousands separators, then the name), and the
`N File(s) ... bytes` / `N Dir(s) ... bytes free` summary lines."""
from lib import Doc, fake

TOOL = "dir"

FILES = ["report.docx", "budget 2026.xlsx", "notes.txt", "IMG_4021.JPG", "video.mp4", "setup.exe",
         "data.csv", "presentation final v3.pptx", "archive.zip", "README.md", "desktop.ini",
         "backup.bak", "invoice-0042.pdf", "main.py", "index.html", "photo (1).png", ".gitignore",
         "package.json", "build.ps1", "ntuser.dat.LOG1", "a-file-with-a-rather-long-name-for-testing.log"]
DIRS = ["Projects", "Photos", "Archive", "Scans", "src", "node_modules", "My Music", "Saved Games",
        "OneDrive - Example Corp", ".vscode", "bin", "obj", "Downloads", "Desktop"]


def _stamp(rng, style):
    y, mo, dd, h, mi = rng.randint(2019, 2026), rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 23), rng.randint(0, 59)
    if style == "us":
        return f"{mo:02d}/{dd:02d}/{y}  {h % 12 or 12:02d}:{mi:02d} {'AM' if h < 12 else 'PM'}"
    if style == "eu":
        return f"{dd:02d}.{mo:02d}.{y}  {h:02d}:{mi:02d}"
    return f"{y}-{mo:02d}-{dd:02d}  {h:02d}:{mi:02d}"


def _listing(d, rng, path, style, sizew):
    d.section(f" Directory of {path}", f"Directory of {path}")
    d.blank()
    nf = nb = nd = 0
    entries = []
    if len(path) > 3:
        entries += [(".", None), ("..", None)]
    entries += [(n, None) for n in rng.sample(DIRS, rng.randint(0, 4))]
    entries += [(n, rng.choice([rng.randint(0, 999), rng.randint(1000, 999999), rng.randint(10 ** 6, 9 * 10 ** 9)]))
                for n in rng.sample(FILES, rng.randint(0, 8))]
    if rng.random() < .5:
        entries.sort(key=lambda e: e[0].lower())
    for name, size in entries:
        st = _stamp(rng, style)
        if size is None:
            nd += 1
            mid = "<DIR>"
            d.line(f"{st}    {mid:<{sizew}} {name}", "row", [st, mid, name])
        else:
            nf += 1
            nb += size
            mid = f"{size:,}"
            d.line(f"{st}    {mid:>{sizew}} {name}", "row", [st, mid, name])
    a = f"{nf} File(s)"
    line = f"{nf:>16} File(s) {nb:>14,} bytes"
    d.line(line, "row", [a, f"{nb:,} bytes"])
    return nf, nb, nd


def generate(rng):
    d = Doc()
    style = rng.choice(["us", "us", "us", "eu", "iso"])
    drive = rng.choice("CCCDE")
    user = fake.user(rng)
    label = rng.choice(["OS", "Windows", "Data", None, "Local Disk"])
    sizew = 14
    if label:
        d.line(f" Volume in drive {drive} is {label}", "kv", [f"Volume in drive {drive} is", label])
    else:
        d.skip(f" Volume in drive {drive} has no label.")
    serial = f"{fake.hexid(rng, 4).upper()}-{fake.hexid(rng, 4).upper()}"
    d.line(f" Volume Serial Number is {serial}", "kv", ["Volume Serial Number is", serial])
    base = rng.choice([f"{drive}:\\Users\\{user}", f"{drive}:\\", f"{drive}:\\Projects\\provost",
                       f"{drive}:\\Users\\{user}\\Documents", f"{drive}:\\inetpub\\wwwroot"])
    recursive = rng.random() < .35
    tf = tb = td = 0
    paths = [base] + ([base.rstrip("\\") + "\\" + x for x in rng.sample(["src", "Photos", "bin", "Archive\\2025"], rng.randint(1, 3))] if recursive else [])
    for p in paths:
        d.blank()
        nf, nb, ndirs = _listing(d, rng, p, style, sizew)
        td += ndirs
        tf += nf
        tb += nb
    fn = rng.randint(10 ** 9, 2 * 10 ** 12)
    free = f"{fn:,} bytes free"
    nd = td
    if recursive:
        d.blank()
        d.section("     Total Files Listed:", "Total Files Listed")
        d.line(f"{tf:>16} File(s) {tb:>14,} bytes", "row", [f"{tf} File(s)", f"{tb:,} bytes"])
    d.line(f"{nd:>16} Dir(s) {fn:>15,} bytes free", "row", [f"{nd} Dir(s)", free])
    return d
