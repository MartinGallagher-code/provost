"""IONOS Cloud `ionosctl server list`: a tabwriter table with CamelCase headers
(ServerId, AvailabilityZone, VmState), optionally --no-headers or a --cols subset."""
from lib import Doc, fake

TOOL = "ionosctl-server-list"

ALL = ["ServerId", "Name", "Type", "AvailabilityZone", "Cores", "RAM", "CpuFamily", "VmState", "State"]


def generate(rng):
    d = Doc()
    cols = ALL
    if rng.random() < .25:
        cols = ["ServerId", "Name"] + sorted(rng.sample(ALL[2:], rng.randint(1, 4)), key=ALL.index)
    rows = []
    for _ in range(rng.randint(1, 10)):
        typ = rng.choice(["ENTERPRISE", "ENTERPRISE", "CUBE", "VCPU"])
        state = rng.choice(["AVAILABLE", "AVAILABLE", "AVAILABLE", "BUSY", "INACTIVE"])
        vm = {"AVAILABLE": rng.choice(["RUNNING", "RUNNING", "SHUTOFF"]), "BUSY": "SHUTOFF", "INACTIVE": "SHUTOFF"}[state]
        v = {"ServerId": fake.uuid(rng),
             "Name": rng.choice([fake.name(rng), fake.word(rng) + "0" + str(rng.randint(1, 9)), "Unnamed Server"]),
             "Type": typ, "AvailabilityZone": rng.choice(["AUTO", "AUTO", "ZONE_1", "ZONE_2"]),
             "Cores": str(rng.choice([1, 2, 4, 8, 16])),
             "RAM": rng.choice(["1GB", "2GB", "4GB", "8GB", "16GB", "32GB", "512MB"]),
             "CpuFamily": rng.choice(["INTEL_SKYLAKE", "INTEL_ICELAKE", "AMD_OPTERON", "INTEL_XEON"]) if typ != "CUBE" else "",
             "VmState": vm, "State": state}
        rows.append([v[c] or None for c in cols])
    gap = rng.choice([3, 3, 2])
    d.table(None if rng.random() < .2 else cols, rows, gap=gap)
    return d
