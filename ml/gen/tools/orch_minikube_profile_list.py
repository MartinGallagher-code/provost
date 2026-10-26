"""`minikube profile list`: a tablewriter grid with |---| rules, a centred
header and right-aligned node counts; sometimes a trailing warning."""
from lib import Doc, fake

TOOL = "minikube-profile-list"


def generate(rng):
    d = Doc()
    wide = rng.random() < 0.5  # newer minikube adds Active Kubecontext
    header = ["Profile", "VM Driver", "Runtime", "IP", "Port", "Version", "Status", "Nodes", "Active"]
    if wide:
        header = header[:-1] + ["Active Profile", "Active Kubecontext"]
    rows = []
    n = rng.randint(1, 6)
    names = ["minikube"] + [rng.choice([fake.word(rng), fake.name(rng), "multinode-demo", "ha-test",
                                        "functional-" + fake.num(rng, 100000, 999999)]) for _ in range(n - 1)]
    active = rng.randrange(n)
    for i, name in enumerate(names):
        driver = rng.choice(["docker", "docker", "qemu2", "hyperkit", "kvm2", "virtualbox", "podman", "vfkit"])
        runtime = rng.choice(["docker", "containerd", "crio"])
        ip = f"192.168.{rng.choice([49, 58, 67, 76, 105, 39])}.{rng.randint(2, 9)}"
        port = rng.choice(["8443", "8443", "8443", "32772", "50443"])
        ver = f"v1.{rng.randint(24, 31)}.{rng.randint(0, 9)}"
        status = rng.choice(["Running", "Running", "Stopped", "Paused", "Unknown", "Starting", "Degraded"])
        nodes = str(rng.choice([1, 1, 1, 2, 3, 4]))
        star = "*" if i == active else ""
        row = [name, driver, runtime, ip if status != "Unknown" else "", port, ver, status, nodes, star]
        if wide:
            row.append("*" if (i == active and rng.random() < .8) else "")
        rows.append(row)
    ncol = len(header)
    width = [max(len(x) for x in [header[c]] + [r[c] for r in rows]) for c in range(ncol)]
    rule = "|" + "|".join("-" * (w + 2) for w in width) + "|"

    def cell(v, c, hdr):
        if hdr:
            return v.center(width[c])
        return v.rjust(width[c]) if c == 7 else v.ljust(width[c])

    def render(cells, hdr=False):
        return "| " + " | ".join(cell(cells[c], c, hdr) for c in range(ncol)) + " |"

    d.skip(rule)
    d.line(render(header, True), "header", header)
    d.skip(rule)
    for r in rows:
        d.line(render(r), "row", [v if v else None for v in r])
    d.skip(rule)
    if rng.random() < 0.25:
        d.blank()
        d.section("! Found 1 invalid profile(s) ! ", "Found 1 invalid profile(s)")
        bad = fake.word(rng) + "-old"
        d.line(f"\t {bad}", "row", [bad])
        d.skip("! You can delete them using the following command(s): ")
        d.skip(f"\t $ minikube delete -p {bad} ")
    return d
