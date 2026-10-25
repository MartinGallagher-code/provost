"""Lima `limactl list`: a tabwriter table (four-space gutters) of VM
instances with SSH endpoint, VM type, arch, CPUs, memory, disk and dir;
older releases lack VMTYPE, an empty list prints a logrus warning."""
from lib import Doc, fake

TOOL = "limactl-list"


def generate(rng):
    d = Doc()
    if rng.random() < 0.08:
        msg = "No instance found. Run `limactl create` to create an instance."
        d.line(f"WARN[0000] {msg} ", "row", ["WARN", "[0000]", msg])
        return d.line("NAME    STATUS    SSH    ARCH    CPUS    MEMORY    DISK    DIR", "header",
                      "NAME STATUS SSH ARCH CPUS MEMORY DISK DIR".split())
    old = rng.random() < 0.3
    home = rng.random() < 0.7
    user = rng.choice(["alice", "bob", "dev", "jsmith", "runner"])
    header = ["NAME", "STATUS", "SSH"] + ([] if old else ["VMTYPE"]) + ["ARCH", "CPUS", "MEMORY", "DISK", "DIR"]
    rows = []
    names = rng.sample(["default", "docker", "k8s", "k3s", "podman", "ubuntu-lts", "fedora", "archlinux",
                        "colima", "colima-" + fake.word(rng), "rancher", fake.name(rng), "almalinux-9",
                        "experimental-" + fake.word(rng)], rng.randint(1, 6))
    for name in names:
        st = rng.choice(["Running", "Running", "Stopped", "Stopped", "Broken"])
        port = rng.randint(49152, 65535) if st == "Running" else 0
        ssh = f"127.0.0.1:{port}"
        vm = rng.choice(["qemu", "vz", "vz", "wsl2"])
        arch = rng.choice(["aarch64", "aarch64", "x86_64", "riscv64", "armv7l"])
        cpus = str(rng.choice([1, 2, 4, 4, 6, 8]))
        mem = rng.choice(["2GiB", "4GiB", "4GiB", "8GiB", "16GiB", "3.5GiB"])
        disk = rng.choice(["100GiB", "100GiB", "60GiB", "20GiB", "256GiB"])
        dr = f"~/.lima/{name}" if home else f"/Users/{user}/.lima/{name}"
        rows.append([name, st, ssh] + ([] if old else [vm]) + [arch, cpus, mem, disk, dr])
    d.table(header, rows, gap=4)
    return d
