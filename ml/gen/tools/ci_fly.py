"""Concourse `fly -t TARGET builds | workers | pipelines`: aligned tables with a
lower-case header (multi-word `created by`, `last updated`), Concourse's
`2006-01-02@15:04:05-0700` timestamps, n/a for unset cells and `1m3s+` for a
running duration."""
from lib import Doc, fake

TOOL = "fly"

PIPES = ["web-app", "api", "infra", "release", "docs", "mobile", "data-platform", "concourse-ci", "terraform-prod"]
JOBS = ["unit", "integration", "build-image", "deploy-staging", "deploy-prod", "lint", "bump-version",
        "publish", "e2e", "terraform-plan", "terraform-apply", "smoke-test"]
TEAMS = ["main", "main", "main", "platform", "mobile", "data"]


def ts(rng, base):
    t = base + rng.randint(0, 600)
    h, rem = divmod(t, 3600)
    m, s = divmod(rem, 60)
    return t, f"2024-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d}@{h % 24:02d}:{m:02d}:{s:02d}{rng.choice(['-0700', '+0000', '+0100', '-0400'])}"


def dur(sec):
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return (f"{h}h" if h else "") + (f"{m}m" if m or h else "") + f"{s}s"


def builds(rng, d):
    split = rng.random() < .6  # newer fly: pipeline/job and build columns
    head = ["id"] + (["pipeline/job", "build"] if split else ["name"]) + \
           ["status", "start", "end", "duration", "team", "created by"]
    rows = []
    bid = rng.randint(100, 900000)
    for _ in range(rng.randint(3, 50 if rng.random() < .2 else 12)):
        bid -= rng.randint(1, 40)
        status = rng.choice(["succeeded"] * 6 + ["failed", "failed", "errored", "aborted", "started", "pending"])
        one_off = rng.random() < .08
        job = "one-off" if one_off else f"{rng.choice(PIPES)}/{rng.choice(JOBS)}"
        num = "n/a" if one_off else str(rng.randint(1, 3000))
        if status == "pending":
            start = end = "n/a"
            du = "n/a"
        else:
            base = rng.randint(0, 80000)
            t0, start = ts(rng, base)
            secs = rng.randint(3, 5400)
            if status == "started":
                end, du = "n/a", dur(secs) + "+"
            else:
                end = start[:11] + ts(rng, t0 + secs)[1][11:] if rng.random() < .9 else ts(rng, t0 + secs)[1]
                du = dur(secs)
        who = rng.choice(["system"] * 4 + [fake.user(rng), "admin", "github:octocat", None])
        team = rng.choice(TEAMS)
        rows.append([str(bid)] + ([job, num] if split else [job if one_off else f"{job}/{num}"]) +
                    [status, start, end, du, team, who])
    d.table(head, rows)


def workers(rng, d):
    head = ["name", "containers", "platform", "tags", "team", "state", "version", "age"]
    rows = []
    for _ in range(rng.randint(1, 14)):
        name = rng.choice([fake.hexid(rng, 12), f"worker-{rng.randint(0, 20)}", f"concourse-worker-{rng.randint(0, 9)}",
                           f"ip-10-{rng.randint(0, 255)}-{rng.randint(0, 255)}-{rng.randint(1, 254)}"])
        plat = rng.choice(["linux"] * 5 + ["darwin", "windows"])
        tags = rng.choice(["none", "none", "none", "gpu", "arm64", "ssd,large", "mac"])
        team = rng.choice(["none", "none", "none", rng.choice(TEAMS)])
        state = rng.choice(["running"] * 6 + ["stalled", "landing", "retiring", "landed"])
        ver = f"2.{rng.randint(3, 5)}"
        age = rng.choice([f"{rng.randint(1, 59)}m", f"{rng.randint(1, 23)}h{rng.randint(0, 59)}m", f"{rng.randint(1, 90)}d"])
        rows.append([name, str(rng.randint(0, 250)), plat, tags, team, state, ver, age])
    d.table(head, rows, right=(1,) if rng.random() < .3 else ())
    if rng.random() < .2:
        d.blank()
        d.blank()
        d.skip("the following workers have not checked in recently:")
        d.blank()
        d.table(head, [[f"worker-{rng.randint(20, 40)}", "0", "linux", "none", "none", "stalled", "2.4", "3d"]])


def pipelines(rng, d):
    newer = rng.random() < .6
    head = ["id", "name", "paused", "public", "last updated"] if newer else ["name", "paused", "public"]
    if newer and rng.random() < .4:
        head = ["id", "team", "name", "paused", "public", "last updated"]
    rows = []
    for i, p in enumerate(rng.sample(PIPES, rng.randint(1, len(PIPES)))):
        r = {"id": str(rng.randint(1, 400)), "team": rng.choice(TEAMS), "name": p,
             "paused": rng.choice(["no", "no", "no", "yes"]), "public": rng.choice(["no", "no", "yes"]),
             "last updated": ts(rng, rng.randint(0, 80000))[1]}
        rows.append([r[h] for h in head])
    d.table(head, rows)


def generate(rng):
    d = Doc()
    rng.choice([builds, builds, workers, pipelines])(rng, d)
    return d
