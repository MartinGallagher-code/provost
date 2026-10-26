"""Phusion Passenger `passenger-status`: header kv lines, dashed section banners,
an application-group block per app, and two-line `* PID: ...` process records."""
from lib import Doc, fake

TOOL = "passenger-status"


def _pairs(d, indent, pairs, widths):
    text, cells = indent, []
    for i, (k, v) in enumerate(pairs):
        piece = f"{k}: {v}"
        if i < len(pairs) - 1:
            piece = piece.ljust(widths[i])
        text += piece
        cells += [k.rstrip(), v]
    d.line(text.rstrip(), "row", cells)


def _uptime(rng):
    s = rng.randint(1, 900000)
    parts = []
    if s >= 86400:
        parts.append(f"{s // 86400}d")
    if s >= 3600:
        parts.append(f"{s // 3600 % 24}h")
    if s >= 60:
        parts.append(f"{s // 60 % 60}m")
    parts.append(f"{s % 60}s")
    return " ".join(parts)


def generate(rng):
    d = Doc()
    ver = rng.choice(["5.3.7", "6.0.12", "6.0.17", "6.0.18", "6.0.19", "6.0.20"])
    integ = rng.choice(["nginx/1.24.0 Phusion_Passenger/" + ver, "Apache/2.4.57 (Debian) Phusion_Passenger/" + ver,
                        "Phusion_Passenger/" + ver])
    for k, v in [("Version", ver), ("Date", fake.date(rng, "datetime") + rng.choice([" +0000", " +0100", " -0400", ""])),
                 ("Instance", f"{fake.token(rng, 8)} ({integ})")]:
        d.kv(k, v, sep=": ", key_width=8)
    d.blank()
    apps = []
    for _ in range(rng.randint(1, 3)):
        root = rng.choice(["/var/www/", "/srv/", "/home/deploy/apps/"]) + fake.name(rng, "_") + rng.choice(["", "/current"])
        apps.append((root, rng.choice(["production", "production", "staging", "development"]), rng.randint(1, 6)))
    total = sum(a[2] for a in apps)
    d.section("----------- General information -----------")
    gen = [("Max pool size", str(max(total, rng.choice([6, 8, 12, 16, 24])))), ("App groups", str(len(apps))),
           ("Processes", str(total)), ("Requests in top-level queue", str(rng.choice([0, 0, 0, rng.randint(1, 50)])))]
    for i, (k, v) in enumerate(gen):
        d.kv(k, v, sep=" : ", key_width=13 if i < 3 else None)
    d.blank()
    d.section("----------- Application groups -----------")
    for root, env, nproc in apps:
        d.section(f"{root} ({env}):")
        d.kv("App root", root, indent="  ")
        d.kv("Requests in queue", str(rng.choice([0, 0, rng.randint(1, 100)])), indent="  ")
        for _ in range(nproc):
            pid = str(rng.randint(1000, 4_000_000))
            row1 = [("PID", pid), ("Sessions", str(rng.choice([0, 0, 1, rng.randint(1, 8)]))),
                    ("Processed", str(rng.randint(0, 5_000_000))), ("Uptime", _uptime(rng))]
            mem = f"{rng.randint(30, 1800)}M"
            last = rng.choice([f"{rng.randint(0, 59)}s ago", f"{rng.randint(1, 59)}m {rng.randint(0, 59)}s ago",
                               f"{rng.randint(1, 23)}h {rng.randint(0, 59)}m ago"])
            row2 = [("CPU", f"{rng.randint(0, 100)}%"), ("Memory  ", mem), ("Last used", last)]
            _pairs(d, "  * ", row1, [15, 18, 20])
            _pairs(d, "    ", row2, [13, 18])
        d.blank()
    return d
