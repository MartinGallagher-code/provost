"""Sensu Go `sensuctl check list`: a wide table with centred column names,
a `─` rule under each column, left-aligned padded values, and many empty
cells (cron, assets, hooks, metric settings)."""
from lib import Doc, fake

TOOL = "sensuctl-check-list"

HEAD = ["Name", "Command", "Interval", "Cron", "Timeout", "TTL", "Subscriptions", "Handlers", "Assets",
        "Hooks", "Publish?", "Stdin?", "Metric Format", "Metric Handlers"]

CMDS = [("check-cpu", "check-cpu-usage -w {w} -c {c}", "sensu/check-cpu-usage"),
        ("check-memory", "check-memory-usage -w {w} -c {c}", "sensu/check-memory-usage"),
        ("check-disk", "check-disk-usage -w {w} -c {c} --exclude-fs-type tmpfs,overlay", "sensu/check-disk-usage"),
        ("check-http", "http-check --url https://{h}/healthz", "sensu/http-checks"),
        ("check-ping", "check-ping -H {h} -c 3", ""),
        ("check-nginx", "check-process -p nginx -C 1", "sensu-plugins/sensu-plugins-process-checks"),
        ("check-ntp", "check-ntp -w 50 -c 100", "sensu-plugins/sensu-plugins-ntp"),
        ("node-exporter", "sensu-prometheus-collector -exporter-url http://localhost:9100/metrics", "sensu/sensu-prometheus-collector"),
        ("check-cert", "http-check-cert --url https://{h} -w 30 -c 7", "sensu/http-checks"),
        ("keepalive-db", "check-postgres-alive -h {h} -d {w}", ""),
        ("disk-metrics", "metrics-disk-usage.rb", "sensu-plugins/sensu-plugins-disk-checks"),
        ("check-ssh", "check_ssh -H {h}", "")]


def generate(rng):
    d = Doc()
    rows = []
    for name, cmd, asset in rng.sample(CMDS, rng.randint(1, len(CMDS))):
        if rng.random() < .3:
            name = f"{name}-{rng.choice(['prod', 'staging', fake.word(rng)])}"
        cron = rng.random() < .15
        metric = "metrics" in cmd or "collector" in cmd or rng.random() < .1
        rows.append([
            name,
            cmd.format(w=rng.randint(60, 85), c=rng.randint(86, 98), h=fake.host(rng)),
            None if cron else str(rng.choice([10, 30, 60, 60, 300, 600, 3600])),
            rng.choice(["*/5 * * * *", "0 * * * *", "@hourly", "0 3 * * *"]) if cron else None,
            str(rng.choice([0, 0, 10, 30, 60])),
            str(rng.choice([0, 0, 0, 180, 900])),
            ",".join(rng.sample(["linux", "system", "web", "db", "windows", "proxy", "entity:" + fake.word(rng)],
                                rng.randint(1, 3))),
            ",".join(rng.sample(["slack", "pagerduty", "email", "influxdb", "opsgenie"], rng.randint(0, 2))) or None,
            asset if asset and rng.random() < .8 else None,
            rng.choice([None, None, None, "nginx-restart", "ps-aux"]),
            rng.choice(["true", "true", "true", "false"]),
            rng.choice(["false", "false", "true"]),
            rng.choice(["prometheus_text", "nagios_perfdata", "graphite_plaintext", "influxdb_line"]) if metric else None,
            rng.choice(["influxdb", "prometheus-remote-write", "graphite"]) if metric else None,
        ])
    width = [max([len(HEAD[c])] + [len(r[c] or "") for r in rows]) + 2 for c in range(len(HEAD))]

    def render(cells, centre=False):
        out = []
        for c, v in enumerate(cells):
            v = v or ""
            out.append(v.center(width[c]) if centre else (" " + v).ljust(width[c]))
        return (" " + " ".join(out)).rstrip()

    d.line(render(HEAD, True), "header", HEAD)
    d.skip(" " + " ".join("─" * w for w in width))
    for r in rows:
        d.line(render(r), "row", r)
    if rng.random() < .3:
        d.blank()
    return d
