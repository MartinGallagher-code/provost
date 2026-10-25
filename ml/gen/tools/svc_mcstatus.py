"""`mcstatus HOST status` / `query`: Minecraft server status as key/value
lines, with online players listed one per line under `players:`."""
from lib import Doc, fake

TOOL = "mcstatus"

NAMES = ["Notch", "jeb_", "Dinnerbone", "Grumm", "xXCreeperXx", "Steve", "Alex", "DiamondMiner42",
         "redstone_wiz", "BlockBuilder", "Pickaxe_Pete", "EnderQueen", "TNT_Tom", "llama_lover",
         "Sk1pper", "NetherNinja", "c0bblestone", "Herobrine"]
MOTDS = ["A Minecraft Server", "Welcome to the server!", "§aSurvival §7| §b1.20 §7| §eJoin now", "Hypixel Network",
         "My Friends Server", "SMP Season 4 - whitelist only", "Creative Plots | /plot auto", "Bedrock Realm"]


def generate(rng):
    d = Doc()
    mode = rng.choice(["status", "status", "query", "bedrock", "legacy"])
    ver = f"1.{rng.randint(8, 21)}" + (f".{rng.randint(1, 6)}" if rng.random() < .7 else "")
    proto = str(rng.randint(47, 770))
    mx = rng.choice([8, 10, 20, 50, 100, 500])
    online = rng.sample(NAMES, rng.randint(0, min(mx, 9)))
    if mode == "query":
        host = f"{fake.ip(rng)}:{rng.choice([25565, 25565, 25566, 19132])}"
        d.kv("host", host)
        soft = f"Java {ver} {rng.choice(['vanilla', 'Paper', 'Spigot', 'Purpur'])}"
        d.kv("software", soft)
        d.kv("motd", rng.choice(MOTDS))
        plugins = rng.choice(["[]", "['EssentialsX', 'WorldEdit', 'LuckPerms']", "['Vault', 'CoreProtect']"])
        d.kv("plugins", plugins)
        lst = "[" + ", ".join(f"'{n}'" for n in online) + "]"
        d.line(f"players: {len(online)}/{mx} {lst}", "kv", ["players", f"{len(online)}/{mx}", lst])
        return d
    if mode == "legacy":
        lst = "[" + ", ".join(f"'{n} ({fake.uuid(rng)})'" for n in online[:3]) + "]" if online else "No players online"
        d.line(f"version: v{ver} (protocol {proto})", "kv", ["version", f"v{ver}", f"(protocol {proto})"])
        d.kv("motd", rng.choice(MOTDS))
        d.line(f"players: {len(online)}/{mx} {lst}", "kv", ["players", f"{len(online)}/{mx}", lst])
        d.kv("ping", f"{rng.uniform(1, 300):.2f} ms")
        return d
    kind = "Bedrock" if mode == "bedrock" else "Java"
    if kind == "Bedrock":
        ver = f"1.{rng.randint(16, 21)}.{rng.randint(0, 99)}"
    d.line(f"version: {kind} {ver} (protocol {proto})", "kv", ["version", f"{kind} {ver}", f"(protocol {proto})"])
    d.kv("motd", rng.choice(MOTDS))
    d.kv("players", f"{len(online)}/{mx}")
    if kind == "Java":
        for n in online:
            u = f"({fake.uuid(rng)})"
            d.line(f"  ⮑ {n} {u}", "row", [n, u])
    else:
        if rng.random() < .5:
            d.kv("map", rng.choice(["Bedrock level", "world", "Survival"]))
            d.kv("gamemode", rng.choice(["Survival", "Creative", "Adventure"]))
    d.kv("ping", f"{rng.uniform(1, 300):.2f} ms")
    return d
