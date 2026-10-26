"""Torque/PBS `tracejob JOBID`: log-access complaints, a `Job:` line, then
fixed-layout event lines (timestamp, source letter, message). Accounting (A)
messages are key=value pairs; long messages wrap under the message column."""
from lib import Doc, fake

TOOL = "tracejob"

INDENT = 26


def _wrap(words, width):
    lines, cur = [], []
    for w in words:
        if cur and len(" ".join(cur + [w])) > width:
            lines.append(cur)
            cur = []
        cur.append(w)
    if cur:
        lines.append(cur)
    return lines


def generate(rng):
    d = Doc()
    jid = rng.randint(1000, 9999999)
    server = rng.choice(["pbs-server", "torque01", "head", "mgmt1", "pbs"]) + rng.choice(["", ".cluster.local", ".hpc.example.edu"])
    day = f"{rng.randint(2018, 2026)}{rng.randint(1, 12):02d}{rng.randint(1, 28):02d}"
    root = rng.choice(["/var/spool/torque", "/var/spool/pbs", "/var/lib/torque"])
    for sub in rng.sample(["server_priv/accounting", "server_logs", "mom_logs", "sched_logs"], rng.randint(0, 3)):
        d.skip(f"{root}/{sub}/{day}: " + rng.choice(["No such file or directory", "Permission denied"]))
    if d.lines:
        d.blank()
    full = f"{jid}.{server}"
    d.kv("Job", full)
    d.blank()
    mm, dd, yy = day[4:6], day[6:8], day[:4]
    t = rng.randint(0, 20 * 3600)
    ms = rng.random() < 0.4
    user = rng.choice(fake.USERS[1:8] + ["jsmith", "mkhan", "lwei"])
    group = rng.choice([user, "users", "physics", "chem", "bio"])
    login = rng.choice(["login1", "login2", "submit", "hpc-login"]) + rng.choice(["", ".cluster.local"])
    queue = rng.choice(["batch", "short", "long", "gpu", "default", "workq"])
    jobname = rng.choice(["run.sh", "job.pbs", "sim_01", "vasp_relax", "STDIN", "array_task", "md_prod.pbs"])
    nodes = rng.randint(1, 8)
    ppn = rng.choice([1, 4, 8, 12, 16, 20, 28, 32])
    exec_host = "+".join(f"n{rng.randint(1, 200):03d}/0-{ppn - 1}" for _ in range(min(nodes, 3)))
    wall = f"{rng.randint(0, 72):02d}:00:00"
    status = rng.choice([0, 0, 0, 1, 271, -11, 265])

    def stamp():
        nonlocal t
        t += rng.choice([0, 0, 1, 2, 5, 30, 600, 3600])
        h, m, s = (t // 3600) % 24, (t // 60) % 60, t % 60
        base = f"{mm}/{dd}/{yy} {h:02d}:{m:02d}:{s:02d}"
        return base + (f".{rng.randint(0, 999):03d}" if ms else "")

    def event(src, msg, pairs=None):
        ts = stamp()
        width = rng.randint(48, 56)
        if pairs is None:
            chunks = _wrap(msg.split(" "), width)
            first = " ".join(chunks[0])
            d.line(f"{ts}  {src}    {first}", "row", [ts, src, first])
            for c in chunks[1:]:
                text = " ".join(c)
                d.line(" " * INDENT + text, "cont", [text])
            return
        toks = [f"{k}={v}" for k, v in pairs]
        chunks = _wrap(toks, width)
        cells = [x for tok in chunks[0] for x in tok.split("=", 1)]
        d.line(f"{ts}  {src}    {' '.join(chunks[0])}", "row", [ts, src] + cells)
        for c in chunks[1:]:
            d.line(" " * INDENT + " ".join(c), "cont", [x for tok in c for x in tok.split("=", 1)])

    ctime = rng.randint(1_500_000_000, 1_780_000_000)
    event("S", "enqueuing into " + queue + ", state 1 hop 1")
    event("S", f"Job Queued at request of {user}@{login}, owner = {user}@{login}, job name = {jobname}, queue = {queue}")
    event("A", None, [("queue", queue)])
    if rng.random() < 0.5:
        event("S", f"Job Modified at request of root@{server}")
    if rng.random() < 0.6:
        event("L", rng.choice(["Job Run", "Considering job to run", "Job Run on node(s)"]))
    event("S", f"Job Run at request of root@{server}")
    start = ctime + rng.randint(1, 9000)
    base = [("user", user), ("group", group), ("jobname", jobname), ("queue", queue), ("ctime", str(ctime)),
            ("qtime", str(ctime)), ("etime", str(ctime)), ("start", str(start)), ("owner", f"{user}@{login}"),
            ("exec_host", exec_host), ("Resource_List.neednodes", f"{nodes}:ppn={ppn}"),
            ("Resource_List.nodect", str(nodes)), ("Resource_List.nodes", f"{nodes}:ppn={ppn}"),
            ("Resource_List.walltime", wall)]
    event("A", None, base)
    t += rng.randint(60, 200000)   # the job runs
    r = rng.random()
    if r < 0.2:
        event("M", None, [("Exit_status", str(status))])
    elif r < 0.5:
        event("M", rng.choice(["job was terminated", "scan_for_terminated: job " + full + " task 1 terminated"]))
    used = [("resources_used.cput", f"{rng.randint(0, 900):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"),
            ("resources_used.energy_used", "0"),
            ("resources_used.mem", f"{rng.randint(1000, 90000000)}kb"),
            ("resources_used.vmem", f"{rng.randint(1000, 90000000)}kb"),
            ("resources_used.walltime", f"{rng.randint(0, 71):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}")]
    if rng.random() < 0.5:
        used = [u for u in used if u[0] != "resources_used.energy_used"]
    event("S", None, [("Exit_status", str(status))] + used)
    if rng.random() < 0.7:
        event("S", rng.choice(["on_job_exit valid pbs_server", "dequeuing from " + queue + ", state COMPLETE",
                               "Post job file processing error"]))
    end = start + rng.randint(10, 90000)
    event("A", None, base + [("session", str(rng.randint(1000, 99999))), ("total_execution_slots", str(nodes * ppn)),
                             ("unique_node_count", str(nodes)), ("end", str(end)), ("Exit_status", str(status))] + used)
    return d
