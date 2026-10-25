"""TSDuck `tsanalyze` (or `tsp -P analyze`): boxed report sections framed
by `|`, two-column dot-leader key/value lines, a bitrate mini-table, and
service / PID tables inside the box."""
from lib import Doc

TOOL = "tsanalyze"

W = 79
PROVIDERS = ["CANAL+", "TF1", "France Televisions", "BBC", "ZDFvision", "ARD", "SES ASTRA", "Sky", "RAI", "M6"]
SERVICES = ["BBC One HD", "CANAL+ SPORT", "TF1 HD", "ZDF", "Das Erste HD", "france 2", "ARTE", "Radio 4",
            "RAI 1", "M6", "W9", "Sky News", "BBC Radio 1", "3sat", "KiKA"]


def box(text):
    return "|" + text.ljust(W - 2)[:W - 2] + "|"


def lead(key, value, width):
    s = f"{key}: "
    return s + "." * max(2, width - len(s) - len(value) - 1) + " " + value


def num(n):
    return f"{n:,}"


def generate(rng):
    d = Doc()
    d.skip("=" * W)
    d.line(box("  TRANSPORT STREAM ANALYSIS REPORT"), "section", ["TRANSPORT STREAM ANALYSIS REPORT"])
    d.skip("|" + "=" * (W - 2) + "|")
    tsid = rng.randint(1, 65535)
    pkts = rng.randint(10000, 9999999)
    npid = rng.randint(4, 60)
    nsrv = rng.randint(1, 9)
    scr = rng.randint(0, npid // 2)
    left = [("Transport Stream Id", f"{tsid} (0x{tsid:04X})"), ("Bytes", num(pkts * 188)), ("TS packets", num(pkts)),
            ("   With invalid sync", str(rng.choice([0, 0, rng.randint(1, 50)]))),
            ("   With transport error", str(rng.choice([0, 0, rng.randint(1, 900)]))),
            ("   Suspect and ignored", str(rng.choice([0, rng.randint(1, 20)])))]
    right = [("Services", str(nsrv)), ("PID's", str(npid)), ("Clear PID's", str(npid - scr)),
             ("Scrambled PID's", str(scr)), ("With PCR's", str(rng.randint(1, nsrv))),
             ("Unreferenced", str(rng.randint(0, 5)))]
    for (lk, lv), (rk, rv) in zip(left, right):
        ind = len(lk) - len(lk.lstrip())
        text = "  " + " " * ind + lead(lk.strip(), lv, 39 - ind) + "  |  " + lead(rk, rv, 29)
        d.line(box(text), "row", [lk.strip(), lv, rk, rv])
    d.skip("|" + "-" * (W - 2) + "|")
    br = rng.randint(1_000_000, 60_000_000)
    hdr = ["Transport stream bitrate, based on", "188 bytes/pkt", "204 bytes/pkt"]
    d.line(box(f"  {hdr[0]} {'.' * 5} {hdr[1]:>15}  {hdr[2]:>15}"), "header", hdr)
    us = rng.random() < .2
    u1, u2 = (num(br) + " b/s", num(br * 204 // 188) + " b/s") if us else ("None", "None")
    d.line(box(f"  {lead('User-specified', '', 41)[:-1]} {u1:>15}  {u2:>15}"), "row", ["User-specified", u1, u2])
    e1, e2 = num(br) + " b/s", num(br * 204 // 188) + " b/s"
    est = lead("Estimated based on PCR's", "", 41)[:-1]
    d.line(box(f"  {est} {e1:>15}  {e2:>15}"), "row",
           ["Estimated based on PCR's", e1, e2])
    d.skip("|" + "-" * (W - 2) + "|")
    secs = pkts * 188 * 8 // br
    d.line(box("  " + lead("Broadcast time", f"{secs} sec ({secs // 60} min {secs % 60} sec)", 73)), "kv",
           ["Broadcast time", f"{secs} sec ({secs // 60} min {secs % 60} sec)"])
    if rng.random() < .7:
        y, mo, dd, h = rng.randint(2010, 2026), rng.randint(1, 12), rng.randint(1, 28), rng.randint(0, 22)
        m = rng.randint(0, 50)
        for k, hh in [("First TDT UTC time stamp", h), ("Last TDT UTC time stamp", h)]:
            v = f"{y}/{mo:02d}/{dd:02d} {hh:02d}:{m + (k.startswith('Last') and 1):02d}:{rng.randint(0, 59):02d}"
            d.line(box("  " + lead(k, v, 73)), "kv", [k, v])
        if rng.random() < .6:
            cc = rng.choice(["FRA", "GBR", "DEU", "ITA", "ESP"])
            d.line(box("  " + lead("TOT country code", cc, 73)), "kv", ["TOT country code", cc])
    d.skip("|" + "-" * (W - 2) + "|")
    hdr = ["Srv Id", "Provider", "Name", "TS Bitrate", "Access"]
    rows = []
    for _ in range(nsrv):
        sid = rng.randint(1, 65535)
        rows.append([f"0x{sid:04X}", rng.choice(PROVIDERS) if rng.random() < .9 else "",
                     rng.choice(SERVICES), num(rng.randint(10000, br // 2)) + " b/s", rng.choice(["C", "C", "S"])])
    wid = [max(len(r[i]) for r in rows + [hdr]) for i in range(5)]

    def render(cells):
        out = "  " + "  ".join(cells[i].ljust(wid[i]) if i not in (3,) else cells[i].rjust(wid[i]) for i in range(4))
        return box(out + "  " + cells[4])
    d.line(render(hdr), "header", hdr)
    for r in rows:
        d.line(render(r), "row", [c if c else None for c in r])
    d.line(box("  Note 1: C=Clear, S=Scrambled"), "skip")
    d.skip("=" * W)
    if rng.random() < .7:
        d.blank()
        d.skip("=" * W)
        d.line(box("  PIDs SUMMARY"), "section", ["PIDs SUMMARY"])
        d.skip("|" + "=" * (W - 2) + "|")
        hdr = ["PID", "Description", "Access", "Bitrate"]
        rows = [["0x0000", "PAT", "C", num(rng.randint(3000, 20000)) + " b/s"],
                ["0x0001", "CAT", "C", num(rng.randint(1000, 5000)) + " b/s"] if rng.random() < .5 else None,
                ["0x0011", "SDT/BAT", "C", num(rng.randint(3000, 30000)) + " b/s"],
                ["0x0012", "EIT", "C", num(rng.randint(10000, 900000)) + " b/s"],
                ["0x0014", "TDT/TOT", "C", num(rng.randint(10, 500)) + " b/s"]]
        rows = [r for r in rows if r]
        for _ in range(rng.randint(1, 10)):
            pid = rng.randint(0x20, 0x1FFE)
            desc = rng.choice(["MPEG-2 Video", "AVC Video", "HEVC Video", "MPEG-1 Audio (fre)", "AC-3 Audio (eng)",
                               "E-AC-3 Audio (deu)", "DVB Subtitles (fra)", "Teletext", "PMT", "ECM (Viaccess)"])
            rows.append([f"0x{pid:04X}", desc, rng.choice(["C", "S", "C"]), num(rng.randint(1000, br // 3)) + " b/s"])
        wid = [max(len(r[i]) for r in rows + [hdr]) for i in range(4)]
        wid[1] = max(wid[1], 40)

        def render2(c):
            return box("  " + c[0].rjust(wid[0]) + "  " + c[1].ljust(wid[1]) + "  " + c[2].ljust(6) + "  " + c[3].rjust(wid[3]))
        d.line(render2(hdr), "header", hdr)
        for r in rows:
            d.line(render2(r), "row", r)
        d.skip("=" * W)
    return d
