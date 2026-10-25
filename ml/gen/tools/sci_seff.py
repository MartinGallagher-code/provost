"""Slurm `seff JOBID`: a short `Key: value` efficiency report for one job."""
from lib import Doc, fake

TOOL = "seff"


def _dhms(secs):
    d, r = divmod(int(secs), 86400)
    h, r = divmod(r, 3600)
    m, s = divmod(r, 60)
    return (f"{d}-" if d else "") + f"{h:02d}:{m:02d}:{s:02d}"


def _mem(mb):
    if mb >= 1024:
        return f"{mb / 1024:.2f} GB"
    return f"{mb:.2f} MB"


def generate(rng):
    d = Doc()
    jid = rng.randint(100000, 99999999)
    pairs = []
    if rng.random() < 0.25:
        task = rng.randint(0, 999)
        pairs.append(("Job ID", str(jid + task + 1)))
        pairs.append(("Array Job ID", f"{jid}_{task}"))
    else:
        pairs.append(("Job ID", str(jid)))
    pairs.append(("Cluster", rng.choice(["hpc", "cluster", "perlmutter", "greene", "sherlock", "discovery", "frontera", "talapas", "bridges2"])))
    user = rng.choice(fake.USERS[1:8] + ["jsmith", "mkhan", "lwei", "a.rossi"])
    pairs.append(("User/Group", f"{user}/{rng.choice([user, 'physics', 'users', 'chem', 'bio-lab', 'pi_smith'])}"))
    state = rng.choice(["COMPLETED", "COMPLETED", "COMPLETED", "FAILED", "TIMEOUT", "CANCELLED", "OUT_OF_MEMORY", "RUNNING"])
    code = {"COMPLETED": 0, "FAILED": rng.randint(1, 255), "TIMEOUT": 0, "OUT_OF_MEMORY": 0,
            "CANCELLED": 0, "RUNNING": None}[state]
    if state == "CANCELLED" and rng.random() < 0.6:
        state = f"CANCELLED by {rng.randint(1000, 60000)}"
    pairs.append(("State", state if code is None else f"{state} (exit code {code})"))
    nodes = rng.choice([1, 1, 1, 2, 4, 8, 16])
    cpn = rng.choice([1, 1, 4, 8, 16, 24, 32, 48, 64, 128])
    if nodes == 1 and cpn == 1:
        pairs.append(("Cores", "1"))
    elif nodes == 1:
        pairs.append(("Cores", str(cpn)))
    else:
        pairs.append(("Nodes", str(nodes)))
        pairs.append(("Cores per node", str(cpn)))
    wall = rng.randint(5, 86400 * 3)
    cores = nodes * cpn
    eff = rng.uniform(0.01, 0.995) if state != "RUNNING" else 0.0
    if state.startswith("CANCELLED") and rng.random() < 0.3:
        eff = 0.0
    pairs.append(("CPU Utilized", _dhms(wall * cores * eff)))
    pairs.append(("CPU Efficiency", f"{eff * 100:.2f}% of {_dhms(wall * cores)} core-walltime"))
    pairs.append(("Job Wall-clock time", _dhms(wall)))
    req_per = rng.choice([1024, 2048, 4000, 4096, 8192, 16384, 32000, 64000, 128000, 256000])
    per_node = rng.random() < 0.6
    req = req_per * (nodes if per_node else cores)
    used = req * rng.uniform(0.0, 1.0) if state != "OUT_OF_MEMORY" else req * rng.uniform(0.98, 1.0)
    if state == "RUNNING":
        used = 0.0
    pairs.append(("Memory Utilized", _mem(used) + rng.choice([" (estimated maximum)", "", ""])))
    scope = f"({_mem(req_per)}/node)" if per_node else f"({_mem(req_per)}/core)"
    pairs.append(("Memory Efficiency", f"{used / req * 100:.2f}% of {_mem(req)} {scope}"))
    for k, v in pairs:
        d.kv(k, v)
    if state == "RUNNING":
        d.skip("WARNING: Efficiency statistics may be misleading for RUNNING jobs.")
    return d
