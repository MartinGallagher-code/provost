"""x264 CLI stderr: `x264 [info]: ...` log lines (input line from the
demuxer), the per-frame-type summary with a fixed `frame X:N Avg QP:q size:s`
layout, percentage lists, and the closing `encoded N frames` line."""
from lib import Doc

TOOL = "x264"

CPUS = ["MMX2 SSE2Fast SSSE3 SSE4.2 AVX FMA3 BMI2 AVX2", "MMX2 SSE2Fast SSSE3 SSE4.2 AVX FMA3 BMI2 AVX2 AVX512",
        "ARMv8 NEON", "MMX2 SSE2Fast SSSE3 SSE4.2 AVX", "MMX2 SSE2Fast SSE3 Cache64"]


def pcts(rng, n, sp=" "):
    vals = [f"{rng.uniform(0, 99.9):4.1f}%" for _ in range(n)]
    return vals, sp.join(vals)


def generate(rng):
    d = Doc()

    def log(msg, cells=None, who="x264", tag="info"):
        cells = [msg] if cells is None else cells
        d.line(f"{who} [{tag}]: {msg}", "row", [who, f"[{tag}]"] + cells)

    w, h = rng.choice([(1920, 1080), (1280, 720), (3840, 2160), (720, 480), (640, 360)])
    fps = rng.choice(["24000/1001", "25/1", "30000/1001", "50/1", "60/1"])
    dem = rng.choice(["lavf", "ffms", "y4m", "avs"])
    log(f"{w}x{h}p {rng.choice(['0:0', '1:1', '32:27'])} @ {fps} fps ({rng.choice(['cfr', 'vfr'])})", who=dem)
    if rng.random() < .4:
        log("using SAR=1/1")
    if rng.random() < .2:
        log("--tune film is not compatible with --tune grain, ignoring", tag="warning")
    log(f"using cpu capabilities: {rng.choice(CPUS)}")
    prof = rng.choice(["High", "Main", "High 10", "Constrained Baseline"])
    log(f"profile {prof}, level {rng.choice(['3.0', '3.1', '4.0', '4.1', '5.1'])}"
        + (f", 4:2:0, {10 if '10' in prof else 8}-bit" if rng.random() < .7 else ""))
    if rng.random() < .3:
        log(f"opencl=0 cabac=1 ref={rng.randint(1, 16)} deblock=1:0:0 analyse=0x3:0x113 me=hex subme=7 psy=1")
    nI, nP = rng.randint(1, 80), rng.randint(20, 4000)
    nB = rng.randint(0, 9000)
    for t, n in [("I", nI), ("P", nP)] + ([("B", nB)] if nB else []):
        qp = f"{rng.uniform(10, 35):.2f}"
        size = str(rng.randint(500, 400000))
        num = str(n)
        msg = f"frame {t}:{num.ljust(5)} Avg QP:{qp}  size:{size.rjust(6)}"
        if rng.random() < .3:
            msg += f"  PSNR Mean Y:{rng.uniform(35, 50):.2f} U:{rng.uniform(40, 52):.2f} V:{rng.uniform(40, 52):.2f}"
            log(msg, [f"frame {t}", num, "Avg QP", qp, "size", size] + ["PSNR Mean Y", msg.split("Y:")[1].split()[0],
                                                                        "U", msg.split("U:")[1].split()[0],
                                                                        "V", msg.split("V:")[1].split()[0]])
        else:
            log(msg, [f"frame {t}", num, "Avg QP", qp, "size", size])
    if nB:
        vals, txt = pcts(rng, rng.randint(2, 5))
        log(f"consecutive B-frames: {txt}", ["consecutive B-frames"] + vals)
    for label, n in [("mb I  I16..4", 3), ("mb P  I16..4", 3)] + ([("mb B  I16..4", 3)] if nB else []):
        vals, txt = pcts(rng, n)
        log(f"{label}: {txt}", [label] + vals)
    if rng.random() < .6:
        rf = f"{rng.uniform(15, 30):.2f}"
        log(f"final ratefactor: {rf}", ["final ratefactor", rf])
    a, b = f"{rng.uniform(30, 90):.1f}%", f"{rng.uniform(30, 90):.1f}%"
    log(f"8x8 transform intra:{a} inter:{b}", ["8x8 transform intra", a, "inter", b])
    if rng.random() < .7:
        v1, t1 = pcts(rng, 3)
        v2, t2 = pcts(rng, 3)
        log(f"coded y,uvDC,uvAC intra: {t1} inter: {t2}", ["coded y,uvDC,uvAC intra"] + v1 + ["inter"] + v2)
    for lab in rng.sample(["i16 v,h,dc,p", "i8 v,h,dc,ddl,ddr,vr,hd,vl,hu", "i4 v,h,dc,ddl,ddr,vr,hd,vl,hu",
                           "i8c dc,h,v,p"], rng.randint(0, 4)):
        n = len(lab.split()[1].split(","))
        vals = [f"{rng.randint(0, 60)}%" for _ in range(n)]
        txt = " ".join(v.rjust(3) for v in vals)
        log(f"{lab}: {txt}", [lab] + vals)
    if rng.random() < .6:
        vals, txt = pcts(rng, rng.randint(1, 6))
        log(f"ref P L0: {txt}", ["ref P L0"] + vals)
    if rng.random() < .3:
        ssim = f"{rng.uniform(.9, .999):.7f}"
        db = f"({rng.uniform(10, 30):.3f}db)"
        log(f"SSIM Mean Y:{ssim} {db}", ["SSIM Mean Y", ssim, db])
    kb = f"{rng.uniform(200, 30000):.2f}"
    log(f"kb/s:{kb}", ["kb/s", kb])
    total = nI + nP + nB
    if rng.random() < .3:
        d.blank()
    e1, e2, e3 = f"encoded {total} frames", f"{rng.uniform(0.5, 400):.2f} fps", f"{kb} kb/s"
    d.line(f"{e1}, {e2}, {e3}", "row", [e1, e2, e3])
    return d
