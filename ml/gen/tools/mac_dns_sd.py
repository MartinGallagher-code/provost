"""macOS `dns-sd -B <type>`: a banner, a `DATE:` line, a STARTING event, then
a fixed-layout event log with a header (multi-word column names)."""
from lib import Doc, fake

TOOL = "dns-sd-B"

NAMES = ["Living Room", "Kitchen", "Brother HL-L2350DW series", "HP LaserJet M404", "alice's MacBook Pro",
         "Office Printer", "nas", "Synology DS920+", "homebridge 4F2A", "Apple TV", "Bedroom HomePod",
         "raspberrypi", "EPSON ET-2850 Series", "Bob’s iPad", "octopi", "Plex Media Server"]
TYPES = ["_http._tcp", "_ipp._tcp", "_airplay._tcp", "_smb._tcp", "_ssh._tcp", "_raop._tcp",
         "_googlecast._tcp", "_hap._tcp", "_companion-link._tcp", "_printer._tcp"]


def ts(rng, t):
    return f"{t // 3600 % 24:02d}:{t // 60 % 60:02d}:{t % 60:02d}.{rng.randint(0, 999):03d}"


def generate(rng):
    d = Doc()
    st = rng.choice(TYPES)
    dom = rng.choice(["", "", "local", "local."])
    d.line(f"Browsing for {st}" + (f".{dom}" if dom else ""), "kv", ["Browsing for", st + (f".{dom}" if dom else "")])
    date = fake.date(rng, "rfc")[:16].replace(",", "")
    d.line(f"DATE: ---{date}---", "kv", ["DATE", date])
    t = rng.randint(0, 86000)
    start = ts(rng, t)
    d.line(f"{start}  ...STARTING...", "row", [start, "...STARTING..."])
    d.line("Timestamp     A/R    Flags  if Domain               Service Type         Instance Name", "header",
           ["Timestamp", "A/R", "Flags", "if", "Domain", "Service Type", "Instance Name"])
    names = rng.sample(NAMES, rng.randint(1, 9))
    events = []
    for i, n in enumerate(names):
        for ifi in rng.sample([4, 6, 14, 15, 1], rng.choice([1, 1, 1, 2])):
            events.append(["Add", n, ifi])
    for e in list(events):
        if rng.random() < .15:
            events.append(["Rmv", e[1], e[2]])
    for j, (ar, n, ifi) in enumerate(events):
        if rng.random() < .3:
            t += rng.randint(0, 40)
        flags = "2" if j == len(events) - 1 else rng.choice(["3", "3", "2"])
        stamp = ts(rng, t)
        typ = st + "."
        text = f"{stamp}  {ar:<6} {flags:>5} {ifi:>3} {'local.':<20} {typ:<20} {n}"
        d.line(text, "row", [stamp, ar, flags, str(ifi), "local.", typ, n])
    return d
