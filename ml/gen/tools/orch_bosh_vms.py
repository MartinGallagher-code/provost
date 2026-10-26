"""BOSH CLI v2 `bosh vms [--vitals]`: a `Using environment` banner, task
lines, then per deployment a `Deployment 'x'` heading, a table with
multi-word headers and values (`Process State`, `0.03, 0.05, 0.01`,
`12% (1.4 GB)`), a `N vms` count, and a final `Succeeded`."""
from lib import Doc, fake

TOOL = "bosh-vms"

JOBS = ["api", "uaa", "router", "diego-cell", "diego-api", "scheduler", "nats", "database", "blobstore",
        "doppler", "log-api", "credhub", "tcp-router", "singleton-blobstore", "control", "compute", "zookeeper",
        "prometheus", "grafana", "concourse-web", "worker"]


def generate(rng):
    d = Doc()
    env = rng.choice([fake.ip(rng), "https://" + fake.ip(rng) + ":25555", "bosh-lite", fake.word(rng) + "-director"])
    client = rng.choice(["admin", "ops_manager", "bosh_admin"])
    d.line(f"Using environment '{env}' as client '{client}'", "kv", ["Using environment", f"'{env}'", "as client", f"'{client}'"])
    d.blank()
    vitals = rng.random() < 0.3
    deps = rng.sample(["cf", "concourse", "zookeeper", "prometheus", "cf-mysql", "redis", f"service-instance_{fake.uuid(rng)}",
                       "credhub", fake.word(rng)], rng.randint(1, 3))
    tasks = [rng.randint(10, 99999) + i for i in range(len(deps))]
    for t in tasks:
        d.skip(f"Task {t}")
    if rng.random() < .3:
        d.skip(". Done")
    d.blank()
    for t in tasks:
        d.skip(f"Task {t} done")
    d.blank()
    stem = rng.choice(["bosh-warden-boshlite-ubuntu-jammy-go_agent/1.423", "bosh-aws-xen-hvm-ubuntu-jammy-go_agent/1.506",
                       "bosh-google-kvm-ubuntu-bionic-go_agent/621.94", "bosh-vsphere-esxi-ubuntu-xenial-go_agent/315.36"])
    show_stem = rng.random() < .5
    for di, dep in enumerate(deps):
        d.section(f"Deployment '{dep}'", dep)
        d.blank()
        header = ["Instance", "Process State", "AZ", "IPs", "VM CID", "VM Type", "Active"] + (["Stemcell"] if show_stem else [])
        if vitals:
            header = ["Instance", "Process State", "AZ", "IPs", "VM CID", "VM Type", "Active", "VM Created At", "Uptime",
                      "Load (1m, 5m, 15m)", "CPU Total", "CPU User", "CPU Sys", "CPU Wait", "Memory Usage", "Swap Usage",
                      "System Disk Usage", "Ephemeral Disk Usage", "Persistent Disk Usage"]
        rows = []
        jobs = rng.sample(JOBS, rng.randint(1, 7))
        for j in sorted(jobs):
            for _ in range(rng.choice([1, 1, 1, 2, 3])):
                st = rng.choice(["running", "running", "running", "running", "failing", "stopped", "unresponsive agent", "-"])
                az = rng.choice(["z1", "z2", "z3", "us-east-1a", "us-east-1b", ""])
                ip = fake.ip(rng) if st != "unresponsive agent" else ""
                cid = rng.choice([fake.uuid(rng), "i-0" + fake.hexid(rng, 16), "vm-" + fake.uuid(rng)])
                row = [f"{j}/{fake.uuid(rng)}", st, az, ip, cid, rng.choice(["small", "default", "medium.disk", "large",
                                                                                     "minimal", "m5.large"]),
                       rng.choice(["true", "true", "true", "false"])]
                if vitals:
                    up = rng.randint(0, 400)
                    row += [rng.choice(["Mon", "Tue", "Wed", "Thu", "Fri"]) + f" {rng.choice(['Jan', 'Mar', 'Jun', 'Sep'])} {rng.randint(1, 28):2d} "
                            f"{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} UTC {rng.randint(2020, 2026)}",
                            f"{up}d {rng.randint(0, 23)}h {rng.randint(0, 59)}m {rng.randint(0, 59)}s",
                            ", ".join(f"{rng.uniform(0, 4):.2f}" for _ in range(3)),
                            f"{rng.uniform(0, 100):.1f}%", f"{rng.uniform(0, 60):.1f}%", f"{rng.uniform(0, 20):.1f}%",
                            f"{rng.uniform(0, 5):.1f}%",
                            f"{rng.randint(1, 95)}% ({rng.uniform(0.1, 15):.1f} GB)", f"{rng.randint(0, 20)}% ({rng.randint(0, 999)} MB)",
                            f"{rng.randint(10, 80)}%", f"{rng.randint(0, 90)}%",
                            rng.choice(["", "", f"{rng.randint(0, 90)}%"])]
                elif show_stem:
                    row.append(stem)
                rows.append([v if v else None for v in row])
        if rng.random() < .3:
            rows.sort(key=lambda r: r[1] != "running")
        d.table(header, rows)
        d.blank()
        d.skip(f"{len(rows)} vms")
        d.blank()
    d.skip("Succeeded")
    return d
