"""`gpustat`: a host / timestamp / driver line, then one line per GPU with
`|`-separated groups: index and name, temperature and utilisation (plus fan
and power when asked), memory used / total, and the processes on it."""
from lib import Doc, fake

TOOL = "gpustat"

GPUS = [("NVIDIA GeForce RTX 3090", 24576, 350), ("NVIDIA GeForce RTX 4090", 24564, 450),
        ("NVIDIA A100-SXM4-40GB", 40960, 400), ("NVIDIA A100-SXM4-80GB", 81920, 400),
        ("NVIDIA H100 80GB HBM3", 81559, 700), ("Tesla V100-SXM2-16GB", 16160, 300),
        ("Tesla T4", 15360, 70), ("NVIDIA RTX A6000", 49140, 300), ("NVIDIA L4", 23034, 72),
        ("NVIDIA GeForce GTX 1080 Ti", 11264, 250), ("Quadro RTX 8000", 48601, 260)]
DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def generate(rng):
    d = Doc()
    host = rng.choice([f"gpu-{rng.randint(1, 40):02d}", fake.host(rng), f"dgx{rng.randint(1, 9)}", "workstation"])
    stamp = (f"{rng.choice(DAYS)} {rng.choice(MONS)} {rng.randint(1, 28):02d} "
             f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} 2026")
    drv = rng.choice(["535.104.05", "550.54.15", "470.182.03", "525.85.12", "560.35.03", "545.23.08"])
    hw = rng.choice([len(host), 25, 27])
    d.line(f"{host.ljust(hw)}  {stamp}  {drv}", "row", [host, stamp, drv])
    name, mem_total, pmax = rng.choice(GPUS)
    mixed = rng.random() < .15
    n = rng.choice([1, 2, 2, 4, 4, 8, 8])
    fan = rng.random() < .3 and "Tesla" not in name and "A100" not in name and "H100" not in name
    power = rng.random() < .4
    pmode = rng.choice(["user", "user", "cmd", "full", "pid"])
    gpus = []
    for i in range(n):
        nm, mt, pm = rng.choice(GPUS) if mixed else (name, mem_total, pmax)
        gpus.append((nm, mt, pm))
    nw = max(len(g[0]) for g in gpus)
    for i, (nm, mt, pm) in enumerate(gpus):
        busy = rng.random() < .6
        temp = f"{rng.randint(55, 86) if busy else rng.randint(25, 45)}'C" if rng.random() < .1 else \
            f"{rng.randint(55, 86) if busy else rng.randint(25, 45)}°C"
        util = f"{rng.randint(20, 100) if busy else rng.randint(0, 3):>3} %"
        procs = []
        if busy or rng.random() < .2:
            for _ in range(rng.randint(1, 4)):
                user, pid = fake.user(rng), rng.randint(1000, 999999)
                cmd = rng.choice(["python", "python3", "torchrun", "Xorg", "java", "ollama", "tritonserver"])
                used = f"{rng.randint(4, mt // 2)}M"
                procs.append({"user": f"{user}({used})", "cmd": f"{cmd}/{pid}({used})",
                              "full": f"{user}:{cmd}/{pid}({used})", "pid": f"{user}/{pid}({used})"}[pmode])
        mused = rng.randint(1000, mt) if procs else rng.randint(0, 600)
        idx = f"[{i}]"
        text = f"{idx} {nm.ljust(nw)} | {temp},"
        cells = [idx, nm, temp]
        if fan:
            f = f"{rng.randint(0, 100):>3} %"
            text += f" {f},"
            cells.append(f)
        text += f" {util}"
        cells.append(util)
        if power:
            pu, pl = f"{rng.randint(20, pm):>3}", f"{pm:>3} W"
            text += f", {pu} / {pl}"
            cells += [pu, pl]
        mu, mtot = f"{mused:>5}", f"{mt:>5} MB"
        text += f" | {mu} / {mtot} |"
        cells += [mu, mtot]
        pr = " ".join(procs) if procs else None
        if pr:
            text += " " + pr
        cells.append(pr)
        d.line(text, "row", [c.strip() if c else None for c in cells])
    return d
