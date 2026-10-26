"""Cluster API `clusterctl describe cluster`: a tree of objects drawn with
├─ └─ │ glyphs in the NAME column, then READY, SEVERITY, REASON, SINCE and
MESSAGE columns, many of them empty."""
from lib import Doc, fake

TOOL = "clusterctl-describe-cluster"


def since(rng):
    return rng.choice([f"{rng.randint(1, 59)}s", f"{rng.randint(1, 59)}m", f"{rng.randint(1, 59)}m{rng.randint(0, 59)}s",
                       f"{rng.randint(1, 23)}h", f"{rng.randint(1, 90)}d"])


def generate(rng):
    d = Doc()
    name = rng.choice(["capi-quickstart", "my-cluster", fake.name(rng), "workload-" + fake.word(rng), "mgmt"])
    infra = rng.choice(["DockerCluster", "AWSCluster", "AzureCluster", "VSphereCluster", "OpenStackCluster", "Metal3Cluster"])
    minfra = infra.replace("Cluster", "Machine")
    sfx = lambda: fake.token(rng, 5)  # noqa: E731
    nodes = []  # (prefix, label, ready, sev, reason, since, msg)

    def status(ok_bias=.75):
        if rng.random() < ok_bias:
            return ["True", "", "", since(rng), ""]
        sev = rng.choice(["Warning", "Info", "Error"])
        reason, msg = rng.choice([
            ("WaitingForAvailableMachines", "Minimum availability requires 3 replicas, current 1 available"),
            ("WaitingForControlPlane", ""), ("ScalingUp", "Scaling up control plane to 3 replicas (actual 1)"),
            ("Bootstrapping", "1 of 2 completed"), ("WaitingForInfrastructure", "0 of 2 completed"),
            ("InstanceProvisionFailed", "failed to create instance: quota exceeded"), ("Deleting", "")])
        return ["False", sev, reason, since(rng), msg]

    nodes.append(("", f"Cluster/{name}", *status(.6)))
    nodes.append(("├─", f"ClusterInfrastructure - {infra}/{name}-{sfx()}", *status(.9)))
    cp = rng.choice([1, 1, 3])
    last_workers = rng.random() < .85
    cpbar = "│ " if last_workers else "  "
    nodes.append(("├─" if last_workers else "└─", f"ControlPlane - KubeadmControlPlane/{name}-{sfx()}", *status()))
    if cp > 1 and rng.random() < .5:
        nodes.append((cpbar + "└─", f"{cp} Machines...", "True", "", "", since(rng),
                      f"See {name}-{sfx()}-{sfx()}, {name}-{sfx()}-{sfx()}, ..."))
    else:
        for i in range(cp):
            nodes.append((cpbar + ("└─" if i == cp - 1 else "├─"), f"Machine/{name}-{sfx()}-{sfx()}", *status(.85)))
            if rng.random() < .25:
                bar = "  " if i == cp - 1 else "│ "
                nodes.append((cpbar + bar + "└─", f"MachineInfrastructure - {minfra}/{name}-control-plane-{sfx()}",
                              *status(.9)))
    if last_workers:
        nodes.append(("└─", "Workers", "", "", "", "", ""))
        mds = rng.randint(1, 2)
        for j in range(mds):
            lastmd = j == mds - 1
            nodes.append(("  " + ("└─" if lastmd else "├─"), f"MachineDeployment/{name}-md-{j}-{sfx()}", *status(.7)))
            bar = "  " if lastmd else "│ "
            nm = rng.randint(1, 4)
            if nm > 2 and rng.random() < .6:
                nodes.append(("  " + bar + "└─", f"{nm} Machines...", "True", "", "", since(rng),
                              f"See {name}-md-{j}-{sfx()}-{sfx()}, {name}-md-{j}-{sfx()}-{sfx()}, ..."))
            else:
                for k in range(nm):
                    nodes.append(("  " + bar + ("└─" if k == nm - 1 else "├─"), f"Machine/{name}-md-{j}-{sfx()}-{sfx()}",
                                  *status(.8)))
    header = ["NAME", "READY", "SEVERITY", "REASON", "SINCE", "MESSAGE"]
    cols = [[header[c]] + [(n[0] + n[1]) if c == 0 else n[c + 1] for n in nodes] for c in range(6)]
    w = [max(len(x) for x in col) for col in cols]

    def render(vals):
        return "  ".join(v.ljust(w[c]) if c < 5 else v for c, v in enumerate(vals)).rstrip()

    d.line(render(header), "header", header)
    for n in nodes:
        vals = [n[0] + n[1]] + list(n[2:])
        d.line(render(vals), "row", [n[1]] + [v if v else None for v in n[2:]])
    return d
