"""`sonobuoy status [--show-all]`: a fully right-aligned plugin table
(three-space gutters) with an optional per-node column and a progress
column, followed by a prose verdict line."""
from lib import Doc, fake

TOOL = "sonobuoy-status"


def generate(rng):
    d = Doc()
    show_all = rng.random() < 0.3
    phase = rng.choice(["running", "running", "complete", "failed"])
    plugins = ["e2e", "systemd-logs"] + rng.sample(["kube-bench-master", "kube-bench-node", "cis-benchmark",
                                                     "custom-" + fake.word(rng), "conformance-image"], rng.randint(0, 2))
    style = rng.choice(["kind", "node", "ec2"])
    n_nodes = rng.randint(1, 5)
    if style == "kind":
        nodes = ["kind-control-plane"] + [f"kind-worker{i if i > 1 else ''}" for i in range(1, n_nodes)]
    elif style == "node":
        nodes = [f"{fake.word(rng)}-node-{i}" for i in range(1, n_nodes + 1)]
    else:
        nodes = [f"ip-10-0-{rng.randint(0, 255)}-{rng.randint(1, 254)}.ec2.internal" for _ in range(n_nodes)]
    rows = []
    total = rng.choice([388, 402, 7066, 5771, 1])
    for p in plugins:
        daemon = p in ("systemd-logs", "kube-bench-node")
        st = phase if p == "e2e" else rng.choice(["complete", "complete", "running", "failed"])
        res = "" if st == "running" else rng.choice(["passed", "passed", "failed"]) if st == "complete" else "failed"
        if p == "e2e" and st == "running":
            done = rng.randint(0, total)
            failed = min(done, rng.randint(0, 3)) if rng.random() < .3 else 0
            prog = f"Passed:{done - failed:>3}, Failed:{failed:>3}, Remaining:{total - done}"
        else:
            prog = ""
        if show_all and daemon:
            for n in nodes:
                nst = st if rng.random() < .7 else rng.choice(["complete", "running"])
                nres = "" if nst == "running" else (res or "passed")
                rows.append([p, n, nst, nres, prog])
        elif show_all:
            rows.append([p, "global", st, res, prog])
        else:
            rows.append([p, st, res, str(len(nodes) if daemon else 1), prog])
    header = ["PLUGIN", "NODE", "STATUS", "RESULT", "PROGRESS"] if show_all else ["PLUGIN", "STATUS", "RESULT", "COUNT", "PROGRESS"]
    d.table(header, rows, gap=3, right=range(len(header)), indent="   ")
    d.blank()
    if phase == "running":
        d.skip("Sonobuoy is still running. Runs can take 60 minutes or more depending on cluster and plugin configuration.")
    elif phase == "complete":
        d.skip("Sonobuoy has completed. Use `sonobuoy retrieve` to get results.")
    else:
        d.skip("Sonobuoy has failed. You can see what happened with `sonobuoy logs`.")
    return d
