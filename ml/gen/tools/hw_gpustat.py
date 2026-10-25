"""`gpustat`: a host/time/driver line, then one pipe-separated line per GPU
(index, name, temperature, utilisation, memory, processes)."""
from lib import Doc, fake

TOOL = "gpustat"

GPUS = [("NVIDIA GeForce RTX 3090", 24576), ("NVIDIA A100-SXM4-40GB", 40960), ("NVIDIA A100-SXM4-80GB", 81920),
        ("NVIDIA H100 80GB HBM3", 81559), ("Tesla V100-SXM2-32GB", 32510), ("NVIDIA GeForce RTX 4090", 24564),
        ("Tesla T4", 15360), ("NVIDIA RTX A6000", 49140), ("NVIDIA L4", 23034), ("NVIDIA GeForce GTX 1080 Ti", 11264),
        ("Quadro RTX 8000", 48601), ("NVIDIA L40S", 46068)]
CMDS = ["python", "python3", "torchrun", "java", "Xorg", "gnome-shell", "ollama", "vllm", "jupyter", "tritonserver"]


def generate(rng):
    d = Doc()
    host = rng.choice([fake.host(rng).split(".")[0], f"gpu-node-{rng.randint(1, 64):02d}", "dgx-a100-07", "workstation"])
    days, mons = "Mon Tue Wed Thu Fri Sat Sun".split(), "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    when = (f"{rng.choice(days)} {rng.choice(mons)} {rng.randint(1, 28):2d} "
            f"{fake.date(rng, 'time')} {rng.randint(2021, 2026)}")
    drv = rng.choice(["535.104.05", "470.182.03", "550.54.15", "525.85.12", "560.35.03", "418.67"])
    hw = rng.randint(len(host), len(host) + 12)
    d.line(f"{host.ljust(hw)}  {when}  {drv}", "row", [host, when, drv])
    name, mem = rng.choice(GPUS)
    if rng.random() < 0.2:
        others = [rng.choice(GPUS) for _ in range(8)]
    else:
        others = None
    n = rng.choice([1, 2, 4, 4, 8])
    flags = dict(fan=rng.random() < 0.3, power=rng.random() < 0.4, cmd=rng.random() < 0.5,
                 user=rng.random() < 0.8, pid=rng.random() < 0.4)
    gpus = [others[i] if others else (name, mem) for i in range(n)]
    cap = rng.choice([250, 300, 350, 400, 700, 70])
    nw = max(len(g[0]) for g in gpus)
    mw = len(str(max(g[1] for g in gpus)))
    for i, (gname, gmem) in enumerate(gpus):
        idx = f"[{i}]"
        busy = rng.random() < 0.6
        temp = f"{rng.randint(55, 84) if busy else rng.randint(26, 45)}°C"
        util = f"{rng.randint(20, 100) if busy else 0:3d} %"
        parts = [temp]
        cells = [idx, gname, temp]
        if flags["fan"]:
            fan = f"{rng.randint(30, 90) if busy else rng.randint(0, 30):3d} %"
            parts.append(fan)
            cells.append(fan.strip())
        parts.append(util)
        cells.append(util.strip())
        if flags["power"]:
            pw = f"{rng.randint(cap // 3, cap) if busy else rng.randint(9, 60):4d} / {cap:3d} W"
            parts.append(pw)
            cells.append(pw.strip())
        procs = []
        used = rng.randint(1, 20)
        if busy:
            for _ in range(rng.randint(1, 4)):
                m = rng.randint(200, max(201, gmem // 3))
                used += m
                s = ""
                if flags["user"]:
                    s += fake.user(rng)
                if flags["cmd"]:
                    s += (":" if s else "") + rng.choice(CMDS)
                if flags["pid"]:
                    s += ("/" if s else "") + str(rng.randint(1000, 4000000))
                procs.append(f"{s or '?'}({m}M)")
        used = min(used, gmem)
        memtxt = f"{str(used).rjust(mw)} / {str(gmem).rjust(mw)} MB"
        cells.append(memtxt.strip())
        stat = parts[0] + ", " + ", ".join(parts[1:])
        line = f"{idx} {gname.ljust(nw)} | {stat} | {memtxt} |"
        if procs:
            ptxt = " ".join(procs)
            line += " " + ptxt
            cells.append(ptxt)
        d.line(line, "row", cells)
    return d
