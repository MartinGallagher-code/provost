"""HandBrakeCLI stderr/stdout: `[HH:MM:SS] subsystem: message` log lines,
`Encoding: task 1 of 1, 12.34 % (fps, avg fps, ETA)` progress lines, mux
track summaries, and the closing banner."""
from lib import Doc

TOOL = "HandBrakeCLI"

TITLES = ["The_Wire_S01E01.mkv", "holiday-2019.mp4", "VIDEO_TS", "lecture recording 03.mov", "BDMV", "input.ts"]


def generate(rng):
    d = Doc()
    t = [rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)]

    def stamp(adv=0):
        s = t[0] * 3600 + t[1] * 60 + t[2] + adv
        t[0], t[1], t[2] = s // 3600 % 24, s // 60 % 60, s % 60
        return f"[{t[0]:02d}:{t[1]:02d}:{t[2]:02d}]"

    def log(msg, cells=None, adv=0):
        st = stamp(adv)
        d.line(f"{st} {msg}", "row", [st] + (cells or [msg]))

    def sub(name, msg, adv=0):
        log(f"{name}: {msg}", [name, msg], adv)

    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    mons = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    date_tail = f"{rng.choice(mons)} {rng.randint(1, 28)} {{}} {rng.randint(2019, 2026)}"
    hbv = f"1.{rng.randint(3, 9)}.{rng.randint(0, 3)}"
    if rng.random() < .6:
        log(f"Compile-time hardening features are enabled")
        sub("hb_init", "starting libhb thread")
        sub("thread", f"{fake_hex(rng)} started (\"libhb\")")
        log(f"HandBrake {hbv} (20{rng.randint(20, 25)}{rng.randint(1, 12):02d}{rng.randint(1, 28):02d}00) - Linux x86_64 - https://handbrake.fr")
        log(f"{rng.choice([4, 8, 12, 16, 32])} CPUs detected")
    src = rng.choice(TITLES)
    sub("hb_scan", f"path={src}, title_index=1")
    if rng.random() < .5:
        sub("scan", f"decoding previews for title {rng.randint(1, 5)}")
        sub("scan", f"{rng.randint(5, 10)} previews, {rng.choice(['1920x1080', '1280x720', '720x576'])}, "
                    f"{rng.choice(['23.976', '25.000', '29.970'])} fps, autocrop = 0/0/0/0, aspect 16:9, PAR 1:1")
    ts = stamp(1)
    wd = rng.choice(days)
    msg = f"{wd} {date_tail.format(ts[1:-1])}"
    d.line(f"{ts} Starting work at: {msg}", "row", [ts, "Starting work at", msg])
    log("1 job(s) to process")
    if rng.random() < .5:
        log(f"starting job")
        sub("work", f"using x264 preset {rng.choice(['fast', 'medium', 'slow', 'veryfast'])}")
    d.line("Encoding: task 1 of 1, 0.00 %", "row", ["Encoding", "task 1 of 1", "0.00 %"])
    pct = 0.0
    for _ in range(rng.randint(2, 12)):
        pct = min(100.0, pct + rng.uniform(1, 25))
        p = f"{pct:.2f} %"
        if pct < 1 and rng.random() < .5:
            d.line(f"Encoding: task 1 of 1, {p}", "row", ["Encoding", "task 1 of 1", p])
            continue
        fps, avg = f"{rng.uniform(5, 400):.2f} fps", f"avg {rng.uniform(5, 400):.2f} fps"
        left = rng.randint(0, 20000)
        eta = f"ETA {left // 3600:02d}h{left // 60 % 60:02d}m{left % 60:02d}s"
        d.line(f"Encoding: task 1 of 1, {p} ({fps}, {avg}, {eta})", "row",
               ["Encoding", "task 1 of 1", p, fps, avg, eta])
    adv = rng.randint(30, 4000)
    nfr = rng.randint(1000, 200000)
    sub("work", f"average encoding speed for job is {rng.uniform(5, 400):.6f} fps", adv)
    if rng.random() < .7:
        sub("vfr", f"{nfr} frames output, {rng.randint(0, 40)} dropped and {rng.randint(0, 40)} duped for CFR/PFR")
    if rng.random() < .5:
        sub("vfr", f"lost time: {rng.randint(0, 900000)} ({rng.randint(0, 40)} frames)")
    for trk in range(rng.randint(1, 4)):
        cells = ["mux", f"track {trk}", f"{nfr if trk == 0 else rng.randint(1000, 300000)} frames",
                 f"{rng.randint(10**5, 10**10)} bytes", f"{rng.uniform(64, 20000):.2f} kbps",
                 f"fifo {rng.choice([32, 64, 512, 1024, 2048, 4096])}"]
        log("mux: " + ", ".join(cells[1:]), cells)
    if rng.random() < .5:
        sub("sync", f"got {rng.randint(1000, 300000)} frames, {nfr} expected")
    ts = stamp(1)
    msg = f"{wd} {date_tail.format(ts[1:-1])}"
    d.line(f"{ts} Finished work at: {msg}", "row", [ts, "Finished work at", msg])
    if rng.random() < .5:
        sub("libhb", "work result = 0")
    d.blank()
    d.skip("Encode done!" if rng.random() < .9 else "Encode failed (error 3).")
    if rng.random() < .7:
        d.skip("HandBrake has exited.")
    return d


def fake_hex(rng):
    return "0x" + "".join(rng.choice("0123456789abcdef") for _ in range(12))
