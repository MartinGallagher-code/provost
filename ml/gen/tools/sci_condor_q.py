"""HTCondor `condor_q` (batch view, or `-nobatch` per-job view): a `-- Schedd:`
banner, an aligned job table, then `Total for ...` summary lines."""
from lib import Doc, fake

TOOL = "condor_q"

CMDS = ["run.sh", "analyze.py", "blast_chunk.sh", "sim", "mcmc.R", "wrapper.sh", "train.py", "process_reads.sh",
        "gen_events", "run_madgraph.sh", "condor_exec.exe"]


def generate(rng):
    d = Doc()
    host = rng.choice(["submit-1.chtc.wisc.edu", "ap40.uw.osg-htc.org", "login04.osgconnect.net", "schedd01.cluster.local",
                       "condor-submit", "lxplus7123.cern.ch", "htc-ap2.example.edu"])
    ip = f"{fake.ip(rng)}:{rng.choice([9618, 9618, 9615, rng.randint(9600, 9700)])}"
    sinful = f"<{ip}?addrs={ip}&alias={host.split('.')[0]}&noUDP&sock=schedd_{rng.randint(1000, 99999)}_{fake.hexid(rng, 4)}>" \
        if rng.random() < 0.5 else f"<{ip}?...>"
    yy, mo, dd = rng.randint(18, 26), rng.randint(1, 12), rng.randint(1, 28)
    when = f"{mo:02d}/{dd:02d}/{yy:02d} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
    d.blank()
    d.line(f"-- Schedd: {host} : {sinful} @ {when}", "kv", ["Schedd", host, sinful, when])
    owners = rng.sample(["alice", "bob", "carol", "jsmith", "mkhan", "lwei", "tnguyen", "osg01", "cmsprod", "ligo"], rng.randint(1, 5))
    tot = {"idle": 0, "running": 0, "held": 0, "completed": 0, "removed": 0, "suspended": 0}
    per_owner = {}
    nobatch = rng.random() < 0.4
    cluster = rng.randint(100, 9_999_999)
    rows = []

    def sub_time():
        return f"{rng.randint(1, 12)}/{rng.randint(1, 28)} {rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}"

    if nobatch:
        for o in owners:
            per_owner[o] = dict.fromkeys(tot, 0)
            for _ in range(rng.randint(1, 3)):
                cluster += rng.randint(1, 500)
                st_time = sub_time()
                cmd = rng.choice(CMDS) + rng.choice(["", "", f" {rng.randint(0, 999)}", f" --seed {rng.randint(1, 99)}",
                                                     f" input_{rng.randint(0, 99):03d}.dat"])
                for p in range(rng.randint(1, 4)):
                    st = rng.choice(["I", "R", "R", "H", "I", "X", "C", "S"] if rng.random() < 0.3 else ["I", "R"])
                    key = {"I": "idle", "R": "running", "H": "held", "X": "removed", "C": "completed", "S": "suspended"}[st]
                    tot[key] += 1
                    per_owner[o][key] += 1
                    rt = "0+00:00:00" if st == "I" else \
                        f"{rng.randint(0, 9)}+{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
                    size = f"{rng.choice([0.0, rng.uniform(0, 9999)]):.1f}"
                    rows.append([f"{cluster}.{p}", o, st_time, rt, st, str(rng.choice([0, 0, 0, 5, 10, -5])), size, cmd])
        def render(r):
            return f"{r[0]:>10} {r[1]:<14} {r[2]:>11} {r[3]:>12} {r[4]:<2} {r[5]:<3} {r[6]:<5} {r[7]}"
        head = ["ID", "OWNER", "SUBMITTED", "RUN_TIME", "ST", "PRI", "SIZE", "CMD"]
        d.line(f"{'ID':>6}{'':4} {'OWNER':<14} {'SUBMITTED':>11} {'RUN_TIME':>12} {'ST':<2} {'PRI':<3} {'SIZE':<5} CMD",
               "header", head)
        for r in rows:
            d.line(render(r), "row", r)
    else:
        any_hold = False
        for o in owners:
            per_owner[o] = dict.fromkeys(tot, 0)
            for _ in range(rng.randint(1, 3)):
                cluster += rng.randint(1, 500)
                n = rng.choice([1, 1, rng.randint(2, 20), rng.randint(20, 1000)])
                parts = {"done": 0, "run": 0, "idle": 0, "hold": 0}
                for _ in range(n):
                    parts[rng.choice(["done", "run", "idle", "idle"] + (["hold"] if rng.random() < 0.2 else []))] += 1
                any_hold |= parts["hold"] > 0
                tot["idle"] += parts["idle"]; tot["running"] += parts["run"]; tot["held"] += parts["hold"]
                per_owner[o]["idle"] += parts["idle"]; per_owner[o]["running"] += parts["run"]
                per_owner[o]["held"] += parts["hold"]
                batch = rng.choice([f"ID: {cluster}", f"CMD: {rng.choice(CMDS)}", f"{rng.choice(['dag', 'run', 'sweep'])}_{fake.word(rng)}+{cluster - rng.randint(1, 50)}"])
                if n == 1:
                    ids = f"{cluster}.0"
                elif parts["done"] and rng.random() < 0.5:
                    ids = f"{cluster}.{parts['done']} ... {cluster}.{n - 1}"
                else:
                    ids = f"{cluster}.0-{n - 1}"
                z = lambda x: str(x) if x else "_"
                rows.append([o, batch, sub_time(), z(parts["done"]), z(parts["run"]), z(parts["idle"]), z(parts["hold"]),
                             str(n - parts["done"]), ids])
        head = ["OWNER", "BATCH_NAME", "SUBMITTED", "DONE", "RUN", "IDLE", "HOLD", "TOTAL", "JOB_IDS"]
        if not any_hold:
            head.pop(6)
            rows = [r[:6] + r[7:] for r in rows]
        ow = max(6, max(len(r[0]) for r in rows) + 1)
        bw = max(13, max(len(r[1]) for r in rows) + 1)
        nnum = len(head) - 4

        def render(r):
            s = f"{r[0]:<{ow}} {r[1]:<{bw}} {r[2]:>11}"
            for v in r[3:3 + nnum]:
                s += f" {v:>6}"
            return s + " " + r[-1]
        d.line(render(head), "header", head)
        for r in rows:
            d.line(render(r), "row", r)
    d.blank()

    def total(label, t):
        vals = [f"{sum(t.values())} jobs", f"{t['completed']} completed", f"{t['removed']} removed",
                f"{t['idle']} idle", f"{t['running']} running", f"{t['held']} held", f"{t['suspended']} suspended"]
        d.line(f"Total for {label}: {vals[0]}; " + ", ".join(vals[1:]) + " ", "kv", [f"Total for {label}"] + vals)
    total("query", tot)
    if len(owners) == 1 or rng.random() < 0.5:
        o = owners[0]
        total(o, per_owner[o])
    allu = {k: v + rng.choice([0, 0, rng.randint(0, 5000)]) for k, v in tot.items()}
    total("all users", allu)
    return d
