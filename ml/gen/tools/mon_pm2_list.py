"""`pm2 list` (pm2 ls): a box-drawn table (┌┬┐ │ ├┼┤ └┴┘) of managed
processes; optionally a Module table, daemon banners and a sync warning."""
from lib import Doc, fake

TOOL = "pm2-list"


def _box(d, header, rows):
    width = [max(len(x or "") for x in [header[c]] + [r[c] for r in rows]) + 2 for c in range(len(header))]

    def rule(l, m, r):
        return l + m.join("─" * (w + 1) for w in width) + r

    def render(cells):
        return "│" + "│".join(" " + (v or "").ljust(w) for v, w in zip(cells, width)) + "│"

    d.skip(rule("┌", "┬", "┐"))
    d.line(render(header), "header", header)
    d.skip(rule("├", "┼", "┤"))
    for r in rows:
        d.line(render(r), "row", [v if v else None for v in r])
    d.skip(rule("└", "┴", "┘"))


def _mem(rng, on):
    if not on:
        return "0b"
    return rng.choice([f"{rng.uniform(10, 999):.1f}mb", f"{rng.uniform(1, 4):.1f}gb", f"{rng.randint(100, 999)}.{rng.randint(0, 9)}kb"])


def _uptime(rng):
    return rng.choice([f"{rng.randint(0, 59)}s", f"{rng.randint(1, 59)}m", f"{rng.randint(1, 23)}h", f"{rng.randint(1, 90)}D",
                       f"{rng.randint(1, 11)}M"])


def generate(rng):
    d = Doc()
    if rng.random() < .2:
        home = rng.choice(["/root/.pm2", "/home/deploy/.pm2", "/var/www/.pm2"])
        d.skip(f"[PM2] Spawning PM2 daemon with pm2_home={home}")
        d.skip("[PM2] PM2 Successfully daemonized")
    wide = rng.random() < .7
    if wide:
        header = ["id", "name", "namespace", "version", "mode", "pid", "uptime", "↺", "status", "cpu", "mem", "user", "watching"]
    else:
        header = ["id", "name", "mode", "↺", "status", "cpu", "memory"]
    rows = []
    names = rng.sample(["api", "worker", "web", "server", "scheduler", "queue-consumer", "next-app", "socket",
                        "cron-jobs", "billing-service", "frontend-ssr", fake.name(rng)], rng.randint(1, 8))
    cluster = rng.random() < .3
    i = 0
    user = rng.choice(["root", "deploy", "node", "ubuntu", "www-data"])
    for nm in names:
        mode = "cluster" if cluster and rng.random() < .7 else "fork"
        for _ in range(rng.choice([1, 1, 2, 4]) if mode == "cluster" else 1):
            st = rng.choice(["online"] * 8 + ["stopped", "errored", "launching", "stopping"])
            on = st == "online"
            vals = {"id": str(i), "name": nm, "namespace": rng.choice(["default", "default", "prod", fake.word(rng)]),
                    "version": rng.choice(["N/A", fake.version(rng), "1.0.0"]), "mode": mode,
                    "pid": str(rng.randint(1000, 4000000)) if on else "0",
                    "uptime": _uptime(rng) if on else "0", "↺": str(rng.choice([0, 0, 1, 3, rng.randint(4, 900)])),
                    "status": st, "cpu": f"{rng.choice([0, 0, rng.uniform(0, 100)]):.0f}%" if on else "0%",
                    "mem": _mem(rng, on), "memory": _mem(rng, on), "user": user,
                    "watching": rng.choice(["disabled", "disabled", "enabled"])}
            if on and rng.random() < .3:
                vals["cpu"] = f"{rng.uniform(0, 9):.1f}%"
            rows.append([vals[h] for h in header])
            i += 1
    _box(d, header, rows)
    if rng.random() < .25:
        d.section("Module")
        mh = ["id", "module", "version", "pid", "status", "↺", "cpu", "mem", "user"]
        mods = rng.sample(["pm2-logrotate", "pm2-server-monit", "pm2-auto-pull", "pm2-slack"], rng.randint(1, 2))
        mrows = [[str(i + k), m, rng.choice(["2.7.0", "3.0.0", "2.4.0"]), str(rng.randint(1000, 99999)), "online",
                  str(rng.randint(0, 3)), f"{rng.choice([0, 0.3, 1.2])}%", _mem(rng, True), user]
                 for k, m in enumerate(mods)]
        _box(d, mh, mrows)
    if rng.random() < .3:
        d.skip("[PM2][WARN] Current process list is not synchronized with saved list. Type 'pm2 save' to synchronize.")
    return d
