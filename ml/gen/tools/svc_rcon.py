"""Source-engine server `status` over rcon (TF2/CS:S/L4D style): a key/value
banner, then a `#`-prefixed player table with bots leaving columns empty."""
from lib import Doc, fake

TOOL = "rcon"

HOSTS = ["Valve Matchmaking Server (Virginia srcds1003-iad1 #42)", "{w} 24/7 2Fort | FastDL",
         "[EU] {w} Community #1", "My Server", "Uncletopia | Seattle | 2 | All Maps",
         "skial.com | {w} | NOCRITS", "LAN party", "{w}'s dedicated server"]
MAPS = ["cp_badlands", "ctf_2fort", "pl_badwater", "koth_viaduct", "cp_process_final", "de_dust2", "cs_office",
        "de_inferno", "c2m1_highway", "pl_upward", "plr_hightower", "mvm_mannworks", "cp_granary_pro_rc8"]
PLAYERS = ["Skeeter", "xX_Sn1per_Xx", "medic!", "{w}", "Heavy Weapons Guy", "[TAG] Ghost", "pootis",
           "a very long nickname indeed", "ScoutMain", "Mr. Spy", "unnamed", "kritz", "dave"]
BOTS = ["Chucklenuts", "CreditToTeam", "Archimedes", "Numnutz", "BOT Bob", "BOT Zach", "Botler 2000"]


def mmss(rng):
    s = rng.randint(5, 20000)
    return f"{s // 3600}:{s // 60 % 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60:02d}:{s % 60:02d}"


def generate(rng):
    d = Doc()
    w = fake.word(rng).capitalize()
    host = rng.choice(HOSTS).format(w=w)
    ip = fake.ip(rng)
    port = str(rng.choice([27015, 27015, 27016, 27025, 27045]))
    nh = rng.randint(0, 14)
    nb = rng.choice([0, 0, 1, 2, 6])
    mx = rng.choice([12, 16, 24, 32, 100])
    pairs = [("hostname", [host]),
             ("version", [f"{rng.randint(1000000, 9999999)}/{rng.randint(20, 24)} {rng.randint(1000000, 9999999)} "
                          + rng.choice(["secure", "secure", "insecure"])]),
             ("udp/ip", [f"{ip}:{port}"] + ([f" (public ip: {fake.ip(rng)})"] if rng.random() < .5 else [])),
             ("steamid", [f"[G:1:{rng.randint(100000, 9999999)}] ({rng.randint(85568392920000000, 85568392929999999)})"]),
             ("account", [rng.choice(["not logged in  (No account specified)", "logged in"])]),
             ("map", [f"{rng.choice(MAPS)} at: 0 x, 0 y, 0 z"]),
             ("tags", [",".join(rng.sample(["cp", "ctf", "increased_maxplayers", "nocrits", "alltalk",
                                             "payload", "valve", "norespawntime", "hidden"], rng.randint(1, 5)))]),
             ("sourcetv", [f"{ip}:{int(port) + 5}, delay {rng.choice(['0.0', '30.0', '90.0'])}s"]),
             ("players", [f"{nh} humans, {nb} bots ({mx} max)"]),
             ("edicts", [f"{rng.randint(300, 1900)} used of 2048 max"])]
    pairs = [p for p in pairs if p[0] in ("hostname", "version", "udp/ip", "map", "players") or rng.random() < .6]
    for k, vals in pairs:
        if k == "udp/ip" and len(vals) == 2:
            text = f"{k:<8}: {vals[0]}{vals[1]}"
            d.line(text, "kv", [k, vals[0], vals[1].strip()])
        else:
            d.line(f"{k:<8}: {vals[0]}", "kv", [k, vals[0]])
    if nh + nb == 0:
        if rng.random() < .5:
            d.blank()
        d.skip("# userid name                uniqueid            connected ping loss state")
        return d
    d.blank()
    rows = []
    uid = rng.randint(2, 900)
    for i in range(nh + nb):
        uid += rng.randint(1, 5)
        bot = i >= nh
        nm = '"' + rng.choice(BOTS if bot else PLAYERS).format(w=w) + '"'
        if bot:
            rows.append([str(uid), nm, "BOT", None, None, None, "active", None])
        else:
            rows.append([str(uid), nm, f"[U:1:{rng.randint(1000, 1999999999)}]", mmss(rng),
                         str(rng.randint(5, 250)), str(rng.choice([0, 0, 0, 1, 5])),
                         rng.choice(["active", "active", "active", "spawning", "connecting"]),
                         f"{fake.ip(rng)}:{rng.randint(1024, 65535)}"])
    hdr = ["userid", "name", "uniqueid", "connected", "ping", "loss", "state", "adr"]
    wd = [max(len(hdr[c]), *(len(r[c] or "") for r in rows)) for c in range(8)]
    wd[1] = max(wd[1], 19)
    wd[2] = max(wd[2], 19)
    right = {0, 3, 4, 5}

    def render(cells):
        out = "#"
        for c, v in enumerate(cells):
            v = v or ""
            out += " " + (v.rjust(wd[c]) if c in right else v.ljust(wd[c]))
        return out.rstrip()

    d.line(render(hdr), "header", hdr)
    for r in rows:
        d.line(render(r), "row", r)
    if rng.random() < 0.3:
        d.skip("#end")
    return d
