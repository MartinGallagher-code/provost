"""`juju status`: a model summary table followed by App, Unit and Machine
tables (and sometimes Relations), each with its own header, blank-separated;
Scale/Rev right-aligned, empty cells where a field is unset."""
from lib import Doc, fake

TOOL = "juju-status"

CHARMS = [("mysql", "8.0.34", "8.0/stable", "3306/tcp"), ("postgresql", "14.9", "14/stable", "5432/tcp"),
          ("wordpress", "", "latest/stable", "80/tcp"), ("haproxy", "2.4.22", "latest/stable", "80/tcp,443/tcp"),
          ("nginx-ingress-integrator", "", "latest/edge", ""), ("redis-k8s", "7.0.4", "latest/edge", "6379/tcp"),
          ("grafana-k8s", "9.5.3", "latest/stable", "3000/tcp"), ("prometheus-k8s", "2.47.2", "1/stable", "9090/tcp"),
          ("ubuntu", "22.04", "latest/stable", ""), ("kafka", "3.6.0", "3/stable", "9092/tcp"),
          ("zookeeper", "3.8.2", "3/stable", "2181/tcp"), ("traefik-k8s", "2.10.4", "latest/stable", "")]


def generate(rng):
    d = Doc()
    k8s = rng.random() < 0.35
    old = rng.random() < 0.3
    model = rng.choice(["default", fake.word(rng), fake.name(rng), "cos", "prod"])
    ctrl = rng.choice(["localhost", "lxd", "microk8s-localhost", "aws-" + fake.word(rng), "overlord"])
    cloud = rng.choice(["localhost/localhost", "microk8s/localhost", "aws/us-east-1", "maas/default", "openstack/RegionOne"])
    ver = rng.choice(["2.9.45", "3.1.6", "3.3.1", "3.4.2", "3.5.0"])
    ts = f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}Z"
    mh = ["Model", "Controller", "Cloud/Region", "Version"] + (["SLA"] if old else []) + ["Timestamp"]
    mr = [model, ctrl, cloud, ver] + (["unsupported"] if old else []) + [ts]
    if rng.random() < 0.2:
        mh.append("Notes")
        mr.append("upgrade available: " + "3.5.4")
    d.table(mh, [mr])
    d.blank()

    apps = rng.sample(CHARMS, rng.randint(1, 5))
    arows, units, rels = [], [], []
    machine = 0
    for name, v, chan, ports in apps:
        scale = rng.choice([1, 1, 1, 2, 3])
        status = rng.choice(["active", "active", "active", "waiting", "blocked", "maintenance", "unknown"])
        msg = {"active": rng.choice(["", "", "Primary", "Ready", "Unit is ready"]), "waiting": "waiting for database",
               "blocked": rng.choice(["Missing relation: database", "need certificates"]),
               "maintenance": "installing charm software", "unknown": ""}[status]
        rev = str(rng.randint(1, 260))
        row = [name, v, status, str(scale), name, chan, rev]
        if k8s:
            row.append(fake.ip(rng) if rng.random() < .7 else "")
        row += [rng.choice(["no", "no", "yes"]), msg]
        arows.append(row)
        for u in range(scale):
            ws = status if rng.random() < .8 else "active"
            agent = rng.choice(["idle", "idle", "idle", "executing", "allocating"])
            unit = f"{name}/{u}" + ("*" if u == 0 else "")
            addr = fake.ip(rng)
            if k8s:
                units.append([unit, ws, agent, addr, ports, msg if u == 0 else ""])
            else:
                units.append([unit, ws, agent, str(machine), addr, ports, msg if u == 0 else ""])
                machine += 1
    for i in range(len(apps) - 1):
        if rng.random() < .6:
            rels.append([f"{apps[i][0]}:database", f"{apps[i + 1][0]}:db", rng.choice(["mysql", "pgsql", "juju-info", "http"]),
                         rng.choice(["regular", "regular", "peer", "subordinate"]), ""])
    ah = ["App", "Version", "Status", "Scale", "Charm", "Channel", "Rev"] + (["Address"] if k8s else []) + ["Exposed", "Message"]
    d.table(ah, arows, gap=2, right=(3, 6))
    d.blank()
    if k8s:
        d.table(["Unit", "Workload", "Agent", "Address", "Ports", "Message"], units)
    else:
        d.table(["Unit", "Workload", "Agent", "Machine", "Public address", "Ports", "Message"], units)
        d.blank()
        mrows = []
        base = rng.choice(["ubuntu@22.04", "ubuntu@20.04", "ubuntu@24.04"]) if not old else rng.choice(["jammy", "focal"])
        tag = fake.hexid(rng, 6)
        for m in range(machine):
            st = rng.choice(["started", "started", "started", "pending", "down"])
            mrows.append([str(m), st, fake.ip(rng) if st != "pending" else "", f"juju-{tag}-{m}", base,
                          rng.choice(["", "", "us-east-1a", "zone1"]) if "aws" in cloud or "maas" in cloud else "",
                          {"started": "Running", "pending": "Creating container", "down": "agent lost"}[st]])
        d.table(["Machine", "State", "Address", "Inst id", "Series" if old else "Base", "AZ", "Message"], mrows)
    if rels and rng.random() < 0.5:
        d.blank()
        d.table(["Relation provider", "Requirer", "Interface", "Type", "Message"], rels)
    return d
