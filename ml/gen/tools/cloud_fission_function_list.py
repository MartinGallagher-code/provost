"""Fission `fission function list`: a tabwriter table padded by single spaces, many
numeric scale/limit columns and usually-empty SECRETS / CONFIGMAPS cells."""
from lib import Doc, fake

TOOL = "fission-function-list"


def generate(rng):
    d = Doc()
    hdr = ["NAME", "ENV", "EXECUTORTYPE", "MINSCALE", "MAXSCALE", "MINCPU", "MAXCPU", "MINMEMORY",
           "MAXMEMORY", "SECRETS", "CONFIGMAPS", "NAMESPACE"]
    ns = rng.choice(["default", "default", "fission-function", fake.word(rng)])
    rows = []
    for _ in range(rng.randint(1, 10)):
        ex = rng.choice(["poolmgr", "poolmgr", "newdeploy", "container"])
        mn = "0" if ex == "poolmgr" else str(rng.randint(0, 3))
        mx = "0" if ex == "poolmgr" else str(rng.randint(1, 10))
        lim = rng.random() < .4
        rows.append([rng.choice([fake.word(rng), fake.name(rng), "hello", "hello-py", "fn-" + fake.token(rng, 5)]),
                     rng.choice(["nodejs", "python", "go", "jvm", "binary", "python-39", "node-18", ""]) if ex != "container" else "",
                     ex, mn, mx,
                     str(rng.choice([100, 200, 500])) + "m" if lim else "0",
                     str(rng.choice([500, 1000, 2000])) + "m" if lim else "0",
                     str(rng.choice([64, 128, 256])) + "Mi" if lim else "0",
                     str(rng.choice([256, 512, 1024])) + "Mi" if lim else "0",
                     ",".join(fake.word(rng) + "-secret" for _ in range(rng.choice([0, 0, 0, 1, 2]))),
                     ",".join(fake.word(rng) + "-cm" for _ in range(rng.choice([0, 0, 0, 1]))),
                     ns])
    d.table(hdr, rows, gap=1)
    return d
