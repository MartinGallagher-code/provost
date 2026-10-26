"""AWS Copilot `copilot svc status`: Task Summary bars (decoration) with their
captions, then Tasks and Alarms tables whose headers are underlined by dash rules."""
from lib import Doc, fake

TOOL = "copilot-svc-status"


def _bar(rng, k, n):
    full = round(10 * k / n) if n else 0
    return "█" * full + "░" * (10 - full)


def _dashed(d, hdr, rows, indent="  "):
    w = [max(len(x[c] or "") for x in [hdr] + rows) for c in range(len(hdr))]

    def render(cells):
        return (indent + "   ".join((c or "").ljust(w[i]) for i, c in enumerate(cells))).rstrip()

    d.line(render(hdr), "header", hdr)
    d.skip(render(["-" * len(h) for h in hdr]))
    for r in rows:
        d.line(render(r), "row", [c or None for c in r])


def generate(rng):
    d = Doc()
    desired = rng.randint(1, 6)
    running = desired if rng.random() < .7 else rng.randint(0, desired)
    show_dep = rng.random() < .6
    kw = (13 if show_dep else 10) + rng.choice([0, 1, 2])
    d.section("Task Summary")
    d.blank()
    cap = f"{running}/{desired} desired tasks are running"
    d.line(f"  {'Running'.ljust(kw)}{_bar(rng, running, desired)}  {cap}", "kv", ["Running", cap])
    if show_dep:
        dep = rng.randint(0, desired)
        cap = f"{dep}/{desired} running tasks for primary deployment"
        d.line(f"  {'Deployments'.ljust(kw)}{_bar(rng, dep, desired)}  {cap}", "kv", ["Deployments", cap])
    hc = rng.choice(["HTTP", "container"])
    ok = rng.randint(0, running)
    cap = f"{ok}/{running} passes {hc} health checks"
    d.line(f"  {'Health'.ljust(kw)}{_bar(rng, ok, running or 1)}  {cap}", "kv", ["Health", cap])
    d.blank()
    d.section("Tasks")
    d.blank()
    rows = []
    for _ in range(max(running, 1) if rng.random() < .9 else 0):
        rows.append([fake.hexid(rng, 8), rng.choice(["RUNNING", "RUNNING", "RUNNING", "PROVISIONING", "STOPPED"]),
                     str(rng.randint(1, 40)), rng.choice([f"{rng.randint(2, 50)} minutes ago", f"{rng.randint(2, 20)} hours ago", f"{rng.randint(2, 9)} days ago", "1 minute ago"]),
                     rng.choice(["HEALTHY", "HEALTHY", "UNHEALTHY", "UNKNOWN", ""]),
                     rng.choice(["HEALTHY", "HEALTHY", "UNHEALTHY", "-"]) if hc == "HTTP" else None])
    hdr = ["ID", "Status", "Revision", "Started At", "Cont. Health"] + (["HTTP Health"] if hc == "HTTP" else [])
    if hc != "HTTP":
        rows = [r[:5] for r in rows]
    if rows:
        _dashed(d, hdr, rows)
    else:
        d.skip("  No tasks are running.")
    if rng.random() < .65:
        d.blank()
        d.section("Alarms")
        d.blank()
        al = []
        for nm in rng.sample(["CPU-Utilization", "Memory-Utilization", "Requests", "Latency", "HTTP-5xx"], rng.randint(1, 4)):
            cond = rng.choice([f"{nm.split('-')[0]}Utilization > {rng.randint(50, 90)}.00 for 3...",
                               f"TargetResponseTime > {rng.randint(1, 5)}.00 for 1 da...",
                               f"RequestCountPerTarget > {rng.randint(100, 1000)}.00 f..."])
            al.append([nm, rng.choice(["Auto Scaling", "Metric", "Rollback"]), cond,
                       rng.choice([f"{rng.randint(1, 11)} months ago", f"{rng.randint(1, 28)} days ago", "1 year ago"]),
                       rng.choice(["OK", "OK", "ALARM", "INSUFFICIENT_DATA"])])
        _dashed(d, ["Name", "Type", "Condition", "Last Updated", "Health"], al)
    return d
