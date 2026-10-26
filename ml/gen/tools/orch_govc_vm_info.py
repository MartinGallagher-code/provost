"""vSphere `govc vm.info [-r]`: one block per VM, `Name:` flush left and its
details indented two spaces, all padded by one tabwriter so the values line
up across every block."""
from lib import Doc, fake

TOOL = "govc-vm.info"

GUESTS = ["Ubuntu Linux (64-bit)", "Microsoft Windows Server 2019 (64-bit)", "Red Hat Enterprise Linux 8 (64-bit)",
          "Other 3.x or later Linux (64-bit)", "VMware Photon OS (64-bit)", "CentOS 7 (64-bit)",
          "Microsoft Windows 10 (64-bit)", "Debian GNU/Linux 12 (64-bit)", "FreeBSD 13 (64-bit)"]


def generate(rng):
    d = Doc()
    resources = rng.random() < 0.4
    dc = rng.choice(["DC0", "Datacenter", "dc-" + fake.word(rng), "HQ"])
    blocks = []
    for _ in range(rng.randint(1, 4)):
        name = rng.choice([fake.name(rng), "vm-" + fake.num(rng, 1, 999), fake.word(rng) + "-template",
                           "DC0_H0_VM" + str(rng.randint(0, 3)), "k8s-worker-" + fake.token(rng, 5)])
        on = rng.random() < .75
        mem = rng.choice([512, 1024, 2048, 4096, 8192, 16384, 32768])
        cpu = rng.choice([1, 2, 4, 8, 16])
        pairs = [("Path", f"/{dc}/vm/" + (rng.choice(["", "prod/", "templates/", fake.word(rng) + "/"])) + name),
                 ("UUID", fake.uuid(rng)),
                 ("Guest name", rng.choice(GUESTS)),
                 ("Memory", f"{mem}MB"),
                 ("CPU", f"{cpu} vCPU(s)"),
                 ("Power state", "poweredOn" if on else rng.choice(["poweredOff", "suspended"]))]
        if on:
            pairs.append(("Boot time", f"{fake.date(rng, 'datetime')}.{rng.randint(0, 999999):06d} +0000 UTC"))
        ip = fake.ip(rng) if on and rng.random() < .8 else ""
        pairs.append(("IP address", ip))
        pairs.append(("Host", rng.choice([fake.host(rng), f"esxi-{rng.randint(1, 20):02d}.lab.local", f"DC0_H{rng.randint(0, 3)}"])))
        if resources:
            used = rng.randint(0, cpu * 2400) if on else 0
            pairs += [("CPU usage", f"{used}MHz ({100 * used / (cpu * 2400):.1f}%)"),
                      ("Memory usage", f"{rng.randint(0, mem) if on else 0}MB ({rng.uniform(0, 100) if on else 0:.1f}%)"),
                      ("Storage committed", f"{rng.uniform(0.1, 400):.1f}GB"),
                      ("Storage uncommitted", f"{rng.uniform(0, 100):.1f}GB"),
                      ("Storage unshared", f"{rng.uniform(0.1, 400):.1f}GB"),
                      ("Storage", rng.choice(["datastore1", "LocalDS_0", "vsanDatastore", "nfs-" + fake.word(rng)]))]
            if rng.random() < .5:
                pairs.append(("Network", rng.choice(["VM Network", "DVPG-" + fake.word(rng), "VM Network, " + fake.word(rng) + "-net"])))
        blocks.append((name, pairs))
    w = max([len("Name:")] + [2 + len(k) + 1 for _, ps in blocks for k, _ in ps]) + 2
    for name, pairs in blocks:
        d.line("Name:".ljust(w) + name, "kv", ["Name", name])
        for k, v in pairs:
            text = ("  " + k + ":").ljust(w) + v
            if v:
                d.line(text, "kv", [k, v])
            else:
                d.line(text.rstrip() + " " * (w - len(k) - 3), "kv", [k])
    return d
