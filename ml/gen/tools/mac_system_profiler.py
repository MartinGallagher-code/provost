"""macOS `system_profiler SPHardwareDataType SPSoftwareDataType ...`: data type
headings, indented sub-headings and `Key: value` lines nested by indentation."""
from lib import Doc, fake

TOOL = "system_profiler"

MODELS = [("MacBook Pro", "MacBookPro18,3", "Apple M1 Pro"), ("MacBook Air", "Mac14,2", "Apple M2"),
          ("Mac mini", "Macmini9,1", "Apple M1"), ("Mac Studio", "Mac13,2", "Apple M1 Ultra"),
          ("iMac", "iMac21,1", "Apple M1"), ("MacBook Pro", "Mac15,8", "Apple M3 Max")]


def serial(rng):
    return "".join(rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789") for _ in range(rng.choice([10, 12])))


def kvblock(d, pairs, indent):
    for k, v in pairs:
        d.kv(k, v, indent=indent)


def hardware(d, rng):
    d.section("Hardware:")
    d.blank()
    d.section("    Hardware Overview:")
    d.blank()
    name, ident, chip = rng.choice(MODELS)
    perf = rng.choice([4, 6, 8, 10, 12, 16])
    eff = rng.choice([2, 4])
    pairs = [("Model Name", name), ("Model Identifier", ident)]
    if rng.random() < .5:
        pairs.append(("Model Number", f"{fake.token(rng, 5).upper()}LL/A"))
    pairs += [("Chip", chip),
              ("Total Number of Cores", f"{perf + eff} ({perf} performance and {eff} efficiency)"),
              ("Memory", f"{rng.choice([8, 16, 24, 32, 64, 96, 128])} GB"),
              ("System Firmware Version", f"{rng.randint(7000, 11000)}.{rng.randint(1, 200)}.{rng.randint(1, 9)}"),
              ("OS Loader Version", f"{rng.randint(7000, 11000)}.{rng.randint(1, 200)}.{rng.randint(1, 9)}"),
              ("Serial Number (system)", serial(rng)),
              ("Hardware UUID", fake.uuid(rng).upper()),
              ("Provisioning UDID", f"0000{rng.randint(6000, 8200)}-{fake.hexid(rng, 16).upper()}"),
              ("Activation Lock Status", rng.choice(["Enabled", "Disabled"]))]
    kvblock(d, pairs, " " * 6)


def software(d, rng):
    d.section("Software:")
    d.blank()
    d.section("    System Software Overview:")
    d.blank()
    major = rng.choice([("Ventura", 13, 22), ("Sonoma", 14, 23), ("Sequoia", 15, 24), ("Monterey", 12, 21)])
    minor = rng.randint(0, 7)
    build = f"{major[2]}{rng.choice('ABCDEFG')}{rng.randint(10, 999)}"
    user = rng.choice(["Alice Smith (alice)", "Bob (bob)", "Carol Ng (carol)", "admin (admin)", "Dave O'Brien (dave)"])
    pairs = [("System Version", f"macOS {major[1]}.{minor} ({build})"),
             ("Kernel Version", f"Darwin {major[2]}.{minor}.0"),
             ("Boot Volume", "Macintosh HD"),
             ("Boot Mode", rng.choice(["Normal", "Normal", "Safe"])),
             ("Computer Name", rng.choice([user.split()[0] + "'s MacBook Pro", "studio-" + str(rng.randint(1, 9)), "build-mini"])),
             ("User Name", user),
             ("Secure Virtual Memory", "Enabled")]
    if rng.random() < .7:
        pairs.append(("System Integrity Protection", rng.choice(["Enabled", "Disabled"])))
    days, hrs, mins = rng.randint(0, 60), rng.randint(0, 23), rng.randint(0, 59)
    pairs.append(("Time since boot", (f"{days} days, " if days else "") + f"{hrs} hours, {mins} minutes"))
    kvblock(d, pairs, " " * 6)


def storage(d, rng):
    d.section("Storage:")
    d.blank()
    vols = ["Data", "Macintosh HD - Data"] + rng.sample(["Backup", "External", "Work", "Media SSD"], rng.randint(0, 2))
    for i, v in enumerate(vols):
        if i:
            d.blank()
        d.section(f"    {v}:")
        d.blank()
        cap = rng.randint(100, 4000) * 10 ** 9 + rng.randint(0, 10 ** 9)
        free = rng.randint(1, cap)
        pairs = [("Free", f"{free / 1e9:.2f} GB ({free:,} bytes)"),
                 ("Capacity", f"{cap / 1e9:.2f} GB ({cap:,} bytes)"),
                 ("Mount Point", "/System/Volumes/Data" if "Data" in v else f"/Volumes/{v}"),
                 ("File System", rng.choice(["APFS", "APFS", "ExFAT", "Journaled HFS+"])),
                 ("Writable", rng.choice(["Yes", "No"])),
                 ("Ignore Ownership", rng.choice(["Yes", "No"])),
                 ("BSD Name", f"disk{rng.randint(1, 9)}s{rng.randint(1, 6)}"),
                 ("Volume UUID", fake.uuid(rng).upper())]
        kvblock(d, pairs, " " * 6)
        d.section("      Physical Drive:")
        internal = rng.random() < .6
        pairs = [("Device Name", rng.choice(["APPLE SSD AP0512R", "APPLE SSD AP1024Z", "Samsung SSD T7", "WD Elements 25A2"])),
                 ("Media Name", rng.choice(["AppleAPFSMedia", "Samsung PSSD T7 Media"])),
                 ("Medium Type", "SSD"),
                 ("Protocol", "Apple Fabric" if internal else rng.choice(["USB", "Thunderbolt"])),
                 ("Internal", "Yes" if internal else "No"),
                 ("Partition Map Type", rng.choice(["GPT (GUID Partition Table)", "Unknown"]))]
        if internal:
            pairs.append(("S.M.A.R.T. Status", "Verified"))
        kvblock(d, pairs, " " * 10)


def power(d, rng):
    d.section("Power:")
    d.blank()
    d.section("    Battery Information:")
    d.blank()
    d.section("      Model Information:")
    kvblock(d, [("Serial Number", serial(rng)), ("Device Name", rng.choice(["bq40z651", "bq20z451"])),
                ("Firmware Version", f"{rng.randint(1000, 9999):x}"), ("Hardware Revision", f"{rng.randint(1, 9):x}"),
                ("Cell Revision", str(rng.randint(1000, 3000)))], " " * 10)
    d.section("      Charge Information:")
    kvblock(d, [("The battery's charge is below the warning level", rng.choice(["No", "No", "Yes"])),
                ("Fully Charged", rng.choice(["Yes", "No"])), ("Charging", rng.choice(["Yes", "No"])),
                ("State of Charge (%)", str(rng.randint(3, 100)))], " " * 10)
    d.section("      Health Information:")
    kvblock(d, [("Cycle Count", str(rng.randint(1, 1200))), ("Condition", rng.choice(["Normal", "Service Recommended"])),
                ("Maximum Capacity", f"{rng.randint(70, 100)}%")], " " * 10)


def generate(rng):
    d = Doc()
    parts = [hardware, software, storage, power]
    chosen = sorted(rng.sample(range(4), rng.randint(1, 3)))
    for i, p in enumerate(chosen):
        parts[p](d, rng)
        d.blank()
    return d
