"""`cdparanoia -Q`: version banner, optional drive probe lines, then the
audio TOC: header, `====` rule, one row per track (sectors with
[mm:ss.ff]), and a TOTAL line."""
from lib import Doc

TOOL = "cdparanoia"

DRIVES = ["HL-DT-ST DVDRAM GH24NSD1 LG00", "ASUS     DRW-24F1ST   b 1.00", "TSSTcorp CDDVDW SH-224DB SB01",
          "PLEXTOR  DVDR   PX-716A  1.11", "MATSHITA DVD-RAM UJ8E2 S SB01", "PIONEER  BD-RW   BDR-XD07 1.00"]


def msf(sectors):
    m, rem = divmod(sectors, 75 * 60)
    s, f = divmod(rem, 75)
    return f"[{m:02d}:{s:02d}.{f:02d}]"


def generate(rng):
    d = Doc()
    d.skip("cdparanoia III release 10.2 (September 11, 2008)")
    d.blank()
    dev = rng.choice(["/dev/cdrom", "/dev/sr0", "/dev/sr1"])
    if rng.random() < .6:
        d.skip(f"Checking {dev} for cdrom...")
        d.skip(f"\tTesting {dev} for SCSI/MMC interface")
        sg = rng.choice(["/dev/sr0", "/dev/sg1", "/dev/sr1"])
        d.line(f"\t\tSG_IO device: {sg}", "kv", ["SG_IO device", sg])
        d.blank()
        drv = rng.choice(DRIVES)
        d.line(f"CDROM model sensed sensed: {drv} ", "kv", ["CDROM model sensed sensed", drv])
        d.blank()
    d.line(" ", "blank")
    d.section("Table of contents (audio tracks only):")
    d.line("track        length               begin        copy pre ch", "header",
           ["track", "length", "begin", "copy", "pre", "ch"])
    d.skip("=" * 59)
    begin = rng.choice([0, 0, 0, 32, 150])
    ntr = rng.randint(1, 24)
    start = begin
    for t in range(1, ntr + 1):
        ln = rng.randint(75 * 20, 75 * 600)
        lc, bc = f"{ln:7d} {msf(ln)}", f"{start:8d} {msf(start)}"
        copy = rng.choice(["no", "no", "OK"])
        pre = rng.choice(["no", "no", "no", "yes"])
        ch = rng.choice([2, 2, 2, 4])
        text = f"{t:3d}.  {lc} {bc}    {copy:<3s}  {pre:<3s} {ch:1d}"
        d.line(text, "row", [f"{t}.", lc.strip(), bc.strip(), copy, pre, str(ch)])
        start += ln
    total = start - begin
    tot = f"{total:7d} {msf(total)}"
    d.line(f"TOTAL  {tot}    (audio only)", "row", ["TOTAL", tot.strip(), "(audio only)", None, None, None])
    d.line(" ", "blank")
    return d
