"""MySQL NDB Cluster `ndb_mgm -e show`: the connection line, a `Cluster
Configuration` heading, then per node type a `[ndbd(NDB)]\\tN node(s)`
heading and `id=N\\t@addr  (version, Nodegroup: G, *)` lines."""
from lib import Doc, fake

TOOL = "ndb_mgm-show"


def generate(rng):
    d = Doc()
    mgm = rng.choice(["localhost", fake.ip(rng), "mgmd01.internal", "ndb-mgm"])
    port = rng.choice(["1186", "1186", "1187"])
    if rng.random() < .3:
        d.skip("-- NDB Cluster -- Management Client --")
    d.kv("Connected to Management Server at", f"{mgm}:{port}")
    d.section("Cluster Configuration")
    d.skip("---------------------")
    mv = rng.choice(["8.0.35", "8.0.39", "8.4.2", "7.6.29", "9.0.1"])
    ver = f"mysql-{mv} ndb-{mv}"
    nid = [1]
    subnet = f"{rng.choice([10, 192])}.{rng.randint(0, 255)}.{rng.randint(0, 255)}."

    def addr():
        return "@" + subnet + str(rng.randint(2, 250))

    ndbd = rng.choice([2, 2, 4, 4, 6, 8])
    replicas = 2 if ndbd % 2 == 0 else 1
    groups = []
    master = rng.randrange(ndbd)
    for i in range(ndbd):
        state = rng.choice([None] * 10 + ["starting", "not started", "not connected"])
        groups.append((state, str(i // replicas)))
    nmgm = rng.choice([1, 1, 2])
    napi = rng.randint(1, 8)
    blocks = [("ndbd(NDB)", ndbd), ("ndb_mgmd(MGM)", nmgm), ("mysqld(API)", napi)]
    first_id = {"ndbd(NDB)": rng.choice([1, 2, 3]), "ndb_mgmd(MGM)": None, "mysqld(API)": None}
    ids, cur = {}, 1
    order = ["ndb_mgmd(MGM)", "ndbd(NDB)", "mysqld(API)"] if first_id["ndbd(NDB)"] > 1 else ["ndbd(NDB)", "ndb_mgmd(MGM)", "mysqld(API)"]
    for name in order:
        cnt = dict(blocks)[name]
        ids[name] = list(range(cur, cur + cnt))
        cur += cnt
    if rng.random() < .3:
        ids["mysqld(API)"] = [i + rng.choice([0, 100, 140]) for i in ids["mysqld(API)"]]
    for k, (name, cnt) in enumerate(blocks):
        if k:
            d.blank()
        tab = "\t"
        d.line(f"[{name}]{tab}{cnt} node(s)", "section", [name])
        for j, node in enumerate(ids[name]):
            key, num = "id", str(node)
            if name == "ndbd(NDB)":
                state, ng = groups[j]
                if state == "not connected":
                    text = f"id={num} (not connected, accepting connect from {addr()[1:]})"
                    d.line(text, "row", [key, num, None, text[text.index("(") + 1:-1], None, None, None, None])
                    continue
                a = addr()
                inner = [ver] + ([state] if state else [])
                tail = f"Nodegroup: {ng}" + (", *" if j == master and not state else "")
                text = f"id={num}\t{a}  ({', '.join(inner)}, {tail})"
                d.line(text, "row", [key, num, a, ver, state, "Nodegroup", ng, "*" if j == master and not state else None])
            else:
                if name == "mysqld(API)" and rng.random() < .35:
                    any_host = rng.random() < .6
                    where = "any host" if any_host else addr()[1:]
                    text = f"id={num} (not connected, accepting connect from {where})"
                    d.line(text, "row", [key, num, None, f"not connected, accepting connect from {where}", None, None, None, None])
                    continue
                a = addr()
                text = f"id={num}\t{a}  ({ver})"
                d.line(text, "row", [key, num, a, ver, None, None, None, None])
    d.blank()
    return d
