"""`boltctl list`: one tree of key/value fields per Thunderbolt device."""
from lib import Doc, fake

TOOL = "boltctl-list"

DEVICES = [("Lenovo", "ThinkPad Thunderbolt 3 Dock"), ("Dell", "WD19TB Thunderbolt Dock"),
           ("CalDigit, Inc.", "TS3 Plus"), ("Apple Inc.", "Thunderbolt Display"),
           ("Other World Computing", "Thunderbolt 3 Dock"), ("Razer", "Core X Chroma"),
           ("Sonnet Technologies, Inc.", "eGFX Breakaway Box 650"), ("Belkin", "Thunderbolt 3 Express Dock HD"),
           ("Intel Corporation", "Thunderbolt 4 Hub"), ("Kensington", "SD5700T"), ("HP Inc.", "HP Thunderbolt Dock G2"),
           ("Akitio", "Node Titan"), ("LaCie", "d2 Thunderbolt 3")]
DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def stamp(rng):
    h = rng.randint(1, 12)
    return (f"{rng.choice(DAYS)} {rng.randint(1, 28):02d} {rng.choice(MONS)} {rng.randint(2019, 2026)} "
            f"{h:02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d} {rng.choice(['AM', 'PM'])} "
            f"{rng.choice(['UTC', 'CET', 'CEST', 'EDT', 'PST', 'BST'])}")


def device(rng):
    vendor, name = rng.choice(DEVICES)
    connected = rng.random() < 0.75
    authorized = connected and rng.random() < 0.8
    stored = rng.random() < 0.6 or not connected
    gen = rng.choice(["Thunderbolt 3", "Thunderbolt 3", "Thunderbolt 4", "USB4"])
    fields = [("type", rng.choice(["peripheral", "peripheral", "host"]), []),
              ("name", name, []), ("vendor", vendor, []), ("uuid", fake.uuid(rng), [])]
    if rng.random() < 0.8:
        fields.append(("generation", gen, []))
    if connected:
        status = "authorized" if authorized else rng.choice(["connected", "auth-error"])
        kids = [("domain", rng.choice([fake.uuid(rng), "domain0", "domain1"]))]
        if rng.random() < 0.8:
            lanes = rng.choice([1, 2])
            per = rng.choice([10, 20, 20])
            sp = f"{lanes * per} Gb/s = {lanes} lanes * {per} Gb/s"
            kids += [("rx speed", sp), ("tx speed", sp)]
        kids.append(("authflags", rng.choice(["none", "secure", "boot", "boot | secure", "nokey"])))
        fields.append(("status", status, kids))
        if authorized:
            fields.append(("authorized", stamp(rng), []))
        fields.append(("connected", stamp(rng), []))
    else:
        fields.append(("status", "disconnected", []))
    if stored:
        fields.append(("stored", stamp(rng), [("policy", rng.choice(["auto", "manual", "iommu"])),
                                              ("key", rng.choice(["no", "yes", "new"]))]))
    else:
        fields.append(("stored", "no", []))
    title = f"{vendor} {name}" + (f" #{rng.randint(2, 4)}" if rng.random() < 0.3 else "")
    return title, fields


def generate(rng):
    d = Doc()
    w = rng.randint(14, 16)
    for i in range(rng.randint(1, 4)):
        if i:
            d.blank()
        title, fields = device(rng)
        d.line(f" {rng.choice(['●', '○'])} {title}", "section", [title])
        for j, (k, v, kids) in enumerate(fields):
            last = j == len(fields) - 1
            d.line("   " + ("└─ " if last else "├─ ") + (k + ":").ljust(w) + v, "kv", [k, v])
            bar = "   " if last else "│  "
            for m, (k2, v2) in enumerate(kids):
                glyph = "└─ " if m == len(kids) - 1 else "├─ "
                d.line("   " + bar + glyph + (k2 + ":").ljust(w - 3) + v2, "kv", [k2, v2])
    if rng.random() < 0.5:
        d.blank()
    return d
