"""`kapacitor list tasks|templates|recordings|replays`: fixed-width
Printf-style columns (no tabwriter), multi-word headers, DBRP lists like
["telegraf"."autogen"], dates as one value."""
from lib import Doc, fake

TOOL = "kapacitor-list"

DBRP = ['"telegraf"."autogen"', '"telegraf"."rp_30d"', '"mydb"."autogen"', '"metrics"."one_week"', '"_internal"."monitor"', '"iot"."raw"']
TASKS = ["cpu_alert", "mem_alert", "disk_usage", "http_5xx", "deadman_hosts", "downsample_cpu", "batch_cpu_mean",
         "load_avg", "net_errors", "k8s_pod_restarts", "swap_used_alert", "queue_depth_anomaly", "ping_latency"]


def _date(rng):
    return f"{rng.choice('Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split())} {rng.randint(1, 28):02d} {rng.randint(2021, 2026)} {fake.date(rng, 'time')}"


def generate(rng):
    d = Doc()
    what = rng.choice(["tasks", "tasks", "templates", "recordings", "replays"])
    n = rng.randint(1, 12)
    if what == "tasks":
        fmt = "{:<30}{:<10}{:<10}{:<10}{}"
        header = ["ID", "Type", "Status", "Executing", "Databases and Retention Policies"]
        rows = []
        for t in rng.sample(TASKS, min(n, len(TASKS))):
            if rng.random() < .3:
                t += rng.choice(["_v2", "_prod", "_staging"])
            status = rng.choice(["enabled", "enabled", "disabled"])
            rows.append([t, rng.choice(["stream", "stream", "batch"]), status,
                         "true" if status == "enabled" and rng.random() < .9 else "false",
                         "[" + ",".join(rng.sample(DBRP, rng.choice([1, 1, 1, 2, 3]))) + "]"])
    elif what == "templates":
        fmt = "{:<30}{:<10}{}"
        header = ["ID", "Type", "Vars"]
        rows = [[t + "_tmpl", rng.choice(["stream", "batch"]),
                 ",".join(rng.sample(["crit", "warn", "info", "field", "measurement", "where_filter", "groups",
                                      "period", "every", "message", "details"], rng.randint(1, 6)))]
                for t in rng.sample(TASKS, min(n, len(TASKS)))]
    elif what == "recordings":
        fmt = "{:<40}{:<8}{:<10}{:<10}{:<23}"
        header = ["ID", "Type", "Status", "Size", "Date"]
        rows = [[fake.uuid(rng), rng.choice(["stream", "batch"]), rng.choice(["finished", "finished", "running", "failed"]),
                 rng.choice([f"{rng.uniform(1, 999):.0f} B", f"{rng.uniform(1, 999):.1f} kB", f"{rng.uniform(1, 99):.1f} MB"]),
                 _date(rng)] for _ in range(n)]
    else:
        fmt = "{:<40}{:<30}{:<40}{:<9}{:<8}{:<23}"
        header = ["ID", "Task", "Recording", "Status", "Clock", "Date"]
        rows = [[fake.uuid(rng), rng.choice(TASKS), fake.uuid(rng), rng.choice(["finished", "running", "failed"]),
                 rng.choice(["fast", "real"]), _date(rng)] for _ in range(n)]
    d.line(fmt.format(*header).rstrip(), "header", header)
    for r in rows:
        d.line(fmt.format(*r).rstrip(), "row", r)
    return d
