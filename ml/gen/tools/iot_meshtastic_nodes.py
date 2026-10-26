"""Meshtastic CLI `meshtastic --nodes`: a tabulate fancy_grid box table
(unicode rules between every row, right-aligned N, N/A for missing values)."""
from lib import Doc, fake

TOOL = "meshtastic-nodes"

HW = ["TBEAM", "HELTEC_V3", "RAK4631", "TLORA_V2_1_1P6", "T_ECHO", "STATION_G2", "HELTEC_WSL_V3", "TRACKER_T1000_E",
      "PORTDUINO", "NANO_G2_ULTRA"]
NAMES = ["Base Station", "Hilltop Relay", "Kayak", "Van", "Home", "Repeater North", "Bike", "Shed solar node",
         "Ridge router (12dBi)", "Pocket", "Car", "Attic"]
COLS = ["N", "User", "ID", "AKA", "Hardware", "Pubkey", "Role", "Latitude", "Longitude", "Altitude", "Battery",
        "Channel util.", "Tx air util.", "SNR", "Hops", "Channel", "LastHeard", "Since"]
OPTIONAL = {"Pubkey", "Role", "Channel", "Hops", "Altitude", "Channel util.", "Tx air util."}


def row_values(rng, i, me):
    nid = fake.hexid(rng, 8)
    short = nid[-4:]
    named = rng.random() < .7
    na = "N/A"
    has_pos = rng.random() < .55
    lat = f"{rng.uniform(-60, 65):.4f}°" if has_pos else na
    lon = f"{rng.uniform(-170, 170):.4f}°" if has_pos else na
    mins = rng.randint(0, 5000)
    since = (rng.choice(["just now", "now"]) if mins == 0 else
             f"{mins} min ago" if mins < 60 else f"{mins // 60} hours ago" if mins < 1440 else f"{mins // 1440} days ago")
    last = fake.date(rng, "datetime") if not me else na
    return {
        "N": str(i), "User": rng.choice(NAMES) if named else f"Meshtastic {short}", "ID": f"!{nid}",
        "AKA": short.upper()[:4] if not named else rng.choice(["BASE", "HILL", "KYK", "VAN", "HOME", short]),
        "Hardware": rng.choice(HW), "Pubkey": (fake.token(rng, 43) + "=") if rng.random() < .6 else na,
        "Role": rng.choice(["CLIENT", "CLIENT", "ROUTER", "CLIENT_MUTE", "ROUTER_LATE", "TRACKER"]),
        "Latitude": lat, "Longitude": lon,
        "Altitude": f"{rng.randint(-5, 1800)} m" if has_pos and rng.random() < .8 else na,
        "Battery": rng.choice([f"{rng.randint(1, 100)}%", "Powered", na]),
        "Channel util.": f"{rng.uniform(0, 40):.2f}%" if rng.random() < .8 else na,
        "Tx air util.": f"{rng.uniform(0, 10):.2f}%" if rng.random() < .8 else na,
        "SNR": f"{rng.uniform(-20, 12):.2f} dB" if not me else na,
        "Hops": str(rng.choice([0, 0, 1, 2, 3])) if not me else "0",
        "Channel": str(rng.choice([0, 0, 0, 1])),
        "LastHeard": last, "Since": since if not me else na,
    }


def generate(rng):
    d = Doc()
    cols = [c for c in COLS if c not in OPTIONAL or rng.random() < .5]
    if rng.random() < .5:
        d.skip("Connected to radio")
        if rng.random() < .3:
            d.blank()
    n = rng.randint(1, 10)
    rows = [row_values(rng, i + 1, i == 0) for i in range(n)]
    data = [[r[c] for c in cols] for r in rows]
    w = [max(len(c), *(len(x[j]) for x in data)) for j, c in enumerate(cols)]

    def render(cells):
        out = []
        for j, v in enumerate(cells):
            out.append(v.rjust(w[j]) if cols[j] == "N" else v.ljust(w[j]))
        return "│ " + " │ ".join(out) + " │"

    def rule(l, m, r, ch):
        return l + m.join(ch * (x + 2) for x in w) + r

    d.skip(rule("╒", "╤", "╕", "═"))
    d.line(render(cols), "header", cols)
    d.skip(rule("╞", "╪", "╡", "═"))
    for k, x in enumerate(data):
        d.line(render(x), "row", x)
        if k < len(data) - 1:
            d.skip(rule("├", "┼", "┤", "─"))
    d.skip(rule("╘", "╧", "╛", "═"))
    return d
