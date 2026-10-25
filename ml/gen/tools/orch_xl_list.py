"""Xen `xl list` (and `xl list -v`): a %-40s name column, right-aligned ID,
Mem and VCPUs, a six-letter state flag string and CPU seconds; the header
mixes spaces and tabs."""
from lib import Doc, fake

TOOL = "xl-list"


def generate(rng):
    d = Doc()
    verbose = rng.random() < 0.3
    if verbose:
        d.line("Name                                        ID   Mem VCPUs\tState\tTime(s)   UUID                            Reason-Code\tSecurity Label",
               "header", ["Name", "ID", "Mem", "VCPUs", "State", "Time(s)", "UUID", "Reason-Code", "Security Label"])
    else:
        d.line("Name                                        ID   Mem VCPUs\tState\tTime(s)", "header",
               ["Name", "ID", "Mem", "VCPUs", "State", "Time(s)"])
    doms = [("Domain-0", 0, rng.choice([1024, 2048, 4096, 8192, 16384]), rng.choice([1, 2, 4, 8]), "r-----")]
    did = rng.randint(1, 40)
    for _ in range(rng.randint(0, 12)):
        name = rng.choice([fake.name(rng), fake.host(rng).split(".")[0], "win" + str(rng.randint(7, 11)) + "-" + fake.word(rng),
                           "debian-" + str(rng.randint(10, 13)), "sys-net", "sys-firewall", "sys-usb",
                           "disp" + str(rng.randint(100, 9999)), fake.word(rng) + "-hvm",
                           "a-rather-long-guest-name-" + fake.name(rng)])[:40]
        state = rng.choice(["-b----", "-b----", "-b----", "r-----", "--p---", "---s--", "----c-", "--ps--"])
        mem = rng.choice([256, 400, 512, 1024, 2048, 3072, 4000, 8192, 16384, 32768])
        doms.append((name, did, mem, rng.choice([1, 1, 2, 2, 4, 8, 16]), state))
        did += rng.randint(1, 5)
    for name, i, mem, vc, st in doms:
        t = f"{rng.uniform(0.1, 999999) if rng.random() < .5 else rng.uniform(0.1, 500):.1f}"
        line = f"{name:<40} {i:>5} {mem:>5} {vc:>5}     {st} {t:>9}"
        cells = [name, str(i), str(mem), str(vc), st, t]
        if verbose:
            uuid = "00000000-0000-0000-0000-000000000000" if i == 0 else fake.uuid(rng)
            reason = "-" if st[3] != "s" else str(rng.choice([0, 1, 3]))
            label = rng.choice(["-", "-", "system_u:system_r:domU_t"]) if i else "-"
            line += f" {uuid} {reason:>11}\t{label}"
            cells += [uuid, reason, label]
        d.line(line, "row", cells)
    return d
