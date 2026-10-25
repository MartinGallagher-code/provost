"""Greenplum `gpstate` (summary): every line is a gplog record
`YYYYMMDD:HH:MM:SS:pid gpstate:host:user-[LEVEL]:-message`; the summary
block's messages are padded `key = value` pairs."""
from lib import Doc, fake

TOOL = "gpstate"


def generate(rng):
    d = Doc()
    host = rng.choice(["mdw", "cdw", "gp-master-01", "smdw", "gpcoord"])
    user = rng.choice(["gpadmin", "gpadmin", "greenplum"])
    y, mo, da = rng.randint(2021, 2026), rng.randint(1, 12), rng.randint(1, 28)
    hh, mm, ss = rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 50)
    pid = f"{rng.randint(1, 999999):06d}"
    coord = "coordinator" if rng.random() < .4 else "master"
    Coord = coord.capitalize()
    ver = rng.choice(["6.25.3", "6.26.0", "7.1.0", "6.19.4"])
    tick = [0]
    kw = rng.choice([56, 56, 58])   # pad wide enough for every key
    rlen = rng.choice([52, 60, 64])

    def prefix(level):
        tick[0] += rng.random() < .04 and tick[0] < 9
        return f"{y}{mo:02d}{da:02d}:{hh:02d}:{mm:02d}:{ss + tick[0]:02d}:{pid} gpstate:{host}:{user}-[{level}]:-"

    def msg(text, level="INFO"):
        p = prefix(level)
        ts = p.split(" ")[0]
        d.line(p + text, "row", [ts, "gpstate", host, user, level, text.strip() if text.strip() else None, None])

    def pair(key, value, level="INFO", flag=False):
        p = prefix(level)
        ts = p.split(" ")[0]
        text = p + "   " + key.ljust(kw) + "= " + value + ("   <<<<<<<<" if flag else "")
        d.line(text, "row", [ts, "gpstate", host, user, level, key, value])

    def rule():
        d.skip(prefix("INFO") + "-" * rlen)

    msg("Starting gpstate with args: " + rng.choice(["", "-s", "-b", "-Q"]))
    build = f"postgres (Greenplum Database) {ver} build commit:{fake.hexid(rng, 40)}" + (" Open Source" if rng.random() < .6 else "")
    msg(f"local Greenplum Version: '{build}'")
    msg(f"{coord} Greenplum Version: 'PostgreSQL {rng.choice(['9.4.26', '12.12'])} (Greenplum Database {ver} build commit:{fake.hexid(rng, 40)}) "
        f"on x86_64-unknown-linux-gnu, compiled by gcc (GCC) {rng.choice(['6.4.0', '8.5.0'])}, 64-bit compiled on {rng.choice(['Oct', 'Mar'])} "
        f"{rng.randint(1, 28)} {y} {fake.date(rng, 'time')}'")
    msg(f"Obtaining Segment details from {coord}...")
    msg("Gathering data from segments...")
    if rng.random() < .5:
        msg("." * rng.randint(1, 6))
    rule()
    msg("Greenplum instance status summary")
    rule()
    segs = rng.choice([2, 4, 8, 16, 32, 64])
    mirrors = rng.random() < .8
    down = rng.choice([0, 0, 0, 1, 2]) if mirrors else 0
    standby = rng.random() < .6
    pair(f"{Coord} instance", "Active")
    pair(f"{Coord} standby", rng.choice(["smdw", "scdw", "gp-standby-01"]) if standby else f"No {coord} standby configured")
    if standby:
        pair(f"Standby {coord} state", rng.choice(["Standby host passive", "Standby host passive", "Standby host DOWN"]))
    total = segs * (2 if mirrors else 1)
    pair("Total segment instance count from metadata", str(total))
    rule()
    msg("   Primary Segment Status")
    rule()
    pair("Total primary segments", str(segs))
    pair(f"Total primary segment valid (at {coord})", str(segs - down))
    pair(f"Total primary segment failures (at {coord})", str(down), "WARNING" if down else "INFO", flag=bool(down))
    pair("Total number of postmaster.pid files missing", "0")
    pair("Total number of postmaster.pid files found", str(segs))
    pair("Total number of postmaster.pid PIDs missing", "0")
    pair("Total number of postmaster.pid PIDs found", str(segs))
    pair("Total number of /tmp lock files missing", "0")
    pair("Total number of /tmp lock files found", str(segs))
    pair("Total number postmaster processes missing", "0")
    pair("Total number postmaster processes found", str(segs))
    rule()
    if mirrors:
        msg("   Mirror Segment Status")
        rule()
        pair("Total mirror segments", str(segs))
        pair(f"Total mirror segment valid (at {coord})", str(segs - down))
        pair(f"Total mirror segment failures (at {coord})", str(down), "WARNING" if down else "INFO", flag=bool(down))
        pair("Total number of postmaster.pid files missing", "0")
        pair("Total number of postmaster.pid files found", str(segs - down))
        pair("Total number postmaster processes found", str(segs - down))
        acting = rng.choice([0, 0, down])
        pair("Total number mirror segments acting as primary segments", str(acting))
        pair("Total number mirror segments acting as mirror segments", str(segs - acting))
        rule()
    else:
        msg("   Mirror Segment Status")
        rule()
        msg("   Mirrors not configured on this array")
        rule()
    return d
