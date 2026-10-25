"""cmd `robocopy`: a ruled banner, a `Started : / Source : / Dest :` header
block, the tab-separated per-file log (class, size, name) with directory
lines and progress percentages, and the closing Total/Copied/Skipped/... table
with `Dirs :` / `Files :` / `Bytes :` / `Times :` rows and Speed/Ended lines."""
from lib import Doc, fake

TOOL = "robocopy"

DAYS = "Monday Tuesday Wednesday Thursday Friday Saturday Sunday".split()
MONTHS = "January February March April May June July August September October November December".split()
FILES = ["report.docx", "budget 2026.xlsx", "notes.txt", "IMG_4021.JPG", "IMG_4022.JPG", "video.mp4",
         "setup.exe", "data.csv", "presentation final v3.pptx", "archive.zip", "README.md", "thumbs.db",
         "desktop.ini", "backup.bak", "invoice-0042.pdf", "main.py", "index.html", "photo (1).png"]
DIRS = ["Projects", "Photos", "Photos\\2026", "Archive", "Scans", "Invoices", "src", "src\\lib", "Music\\Live"]


def _stamp(day, h, m, s, ap):
    return f"{day} {h}:{m:02d}:{s:02d} {ap}"


def _sz(rng, n, scale=False):
    if n < 10 ** 6 or (not scale and rng.random() < .3):
        return str(n)
    for unit, div in (("g", 1024 ** 3), ("m", 1024 ** 2), ("k", 1024)):
        if n >= div:
            return f"{n / div:.1f} {unit}"
    return str(n)


def generate(rng):
    d = Doc()
    user = fake.user(rng)
    src = rng.choice([f"C:\\Users\\{user}\\Documents\\", "D:\\Data\\", f"\\\\fs01\\share\\{user}\\", "C:\\inetpub\\wwwroot\\"])
    dst = rng.choice(["E:\\Backup\\Documents\\", f"\\\\nas\\backup\\{user}\\", "D:\\Mirror\\", "F:\\Archive\\2026\\"])
    rule = "-" * 79
    h, m, s = rng.randint(1, 12), rng.randint(0, 59), rng.randint(0, 50)
    day, ap = f"{rng.choice(DAYS)}, {rng.choice(MONTHS)} {rng.randint(1, 28)}, 2026", rng.choice(["AM", "PM"])
    d.blank()
    d.skip(rule)
    d.skip("   ROBOCOPY     ::     Robust File Copy for Windows                              ")
    d.skip(rule)
    d.blank()
    d.line(f"  Started : {(st := _stamp(day, h, m, s, ap))}", "kv", ["Started", st])
    d.line(f"   Source : {src}", "kv", ["Source", src])
    d.line(f"     Dest : {dst}", "kv", ["Dest", dst])
    d.blank()
    files = rng.choice(["*.*", "*.docx *.xlsx", "*.jpg"])
    d.line(f"    Files : {files}", "kv", ["Files", files])
    d.line("\t    ", "blank")
    if rng.random() < .3:
        ex = rng.choice(["*.tmp", "~$*", "thumbs.db"])
        d.line(f"Exc Files : {ex}", "kv", ["Exc Files", ex])
        d.blank()
    opts = rng.choice(["*.* /S /E /DCOPY:DA /COPY:DAT /R:1000000 /W:30",
                       "*.* /S /E /DCOPY:DA /COPY:DAT /PURGE /MIR /MT:8 /R:3 /W:5",
                       "*.* /S /E /COPY:DAT /NP /R:2 /W:10", "*.* /DCOPY:DA /COPY:DAT /R:1000000 /W:30"])
    d.line(f"  Options : {opts} ", "kv", ["Options", opts])
    d.blank()
    d.skip(rule[:-1])
    d.blank()
    show_pct = "/NP" not in opts and rng.random() < .6
    tot = {"d": 0, "f": 0, "b": 0}
    cop = {"d": 0, "f": 0, "b": 0}
    dirs = [""] + rng.sample(DIRS, rng.randint(0, 3))
    for dd in dirs:
        names = rng.sample(FILES, rng.randint(0, 6))
        path = src + (dd + "\\" if dd else "")
        tot["d"] += 1
        new_dir = dd and rng.random() < .4
        if new_dir:
            cop["d"] += 1
            d.line(f"\t  New Dir {len(names):>10}\t{path}", "row", ["New Dir", str(len(names)), path])
        else:
            d.line(f"\t{len(names):>20}\t{path}", "row", [str(len(names)), path])
        for name in names:
            n = rng.choice([rng.randint(0, 9999), rng.randint(10 ** 4, 10 ** 6), rng.randint(10 ** 6, 5 * 10 ** 9)])
            tot["f"] += 1
            tot["b"] += n
            cls = "New File" if new_dir else rng.choice(["New File", "Newer", "Older", "*EXTRA File", "Changed", None])
            if cls is None:
                continue
            cop["f"] += cls != "*EXTRA File"
            cop["b"] += n if cls != "*EXTRA File" else 0
            sz = _sz(rng, n)
            lead = f"\t{cls} " if cls.startswith("*") else f"\t    {cls:<10}"
            d.line(f"{lead}\t\t{sz:>8}\t{name}", "row", [cls, sz, name])
            if show_pct and cls != "*EXTRA File":
                if n > 10 ** 7 and rng.random() < .5:
                    for p in sorted(rng.sample(range(1, 100), 3)):
                        d.skip(f"{p:.1f}%")
                d.skip("100%  ")
        if rng.random() < .12:
            ts = f"2026/10/{rng.randint(10, 25)} {h:02d}:{m:02d}:{s + 3:02d}"
            msg = f"Copying File {path}locked.pst"
            d.line(f"{ts} ERROR 32 (0x00000020) {msg}", "row", [ts, "ERROR", "32", "(0x00000020)", msg])
            d.skip("The process cannot access the file because it is being used by another process.")
            d.skip("Waiting 30 seconds...")
    d.blank()
    d.skip(rule[:-1])
    d.blank()
    hdr = [None, "Total", "Copied", "Skipped", "Mismatch", "FAILED", "Extras"]
    d.line(" " * 10 + "".join(f"{x:>10}" for x in hdr[1:]), "header", hdr)

    def row(label, vals):
        text = f"{label:>8} :" + "".join(f"{v or '':>10}" for v in vals)
        d.line(text.rstrip(), "row", [label] + [v if v else None for v in vals])

    fails = "0" if rng.random() < .85 else str(rng.randint(1, 3))
    row("Dirs", [str(tot["d"]), str(cop["d"]), str(tot["d"] - cop["d"]), "0", "0", "0"])
    row("Files", [str(tot["f"]), str(cop["f"]), str(tot["f"] - cop["f"]), "0", fails, "0"])
    row("Bytes", [_sz(rng, tot["b"], True), _sz(rng, cop["b"], True), _sz(rng, tot["b"] - cop["b"], True), "0", "0", "0"])
    dur = rng.randint(0, 400)
    t = f"{dur // 3600}:{dur // 60 % 60:02d}:{dur % 60:02d}"
    row("Times", [t, t if rng.random() < .5 else "0:00:00", None, None, "0:00:00", "0:00:00"])
    if cop["b"] and rng.random() < .8:
        bps = rng.randint(10 ** 5, 10 ** 9)
        d.line(f"   Speed :{bps:>20} Bytes/sec.", "kv", ["Speed", f"{bps} Bytes/sec."])
        mbm = f"{bps * 60 / 1048576:.3f}"
        d.line(f"   Speed :{mbm:>20} MegaBytes/min.", "kv", ["Speed", f"{mbm} MegaBytes/min."])
    s2 = min(59, s + dur % 60)
    d.line(f"   Ended : {(en := _stamp(day, h, m, s2, ap))}", "kv", ["Ended", en])
    d.blank()
    return d
