"""`mytop -b` (batch mode): a status header (server, load, uptime, then
`Key: value` counters packed several to a line), a blank, and the
processlist with right-aligned, truncated columns under a `--` rule."""
from lib import Doc, fake

TOOL = "mytop"

QUERIES = ["show full processlist", "SELECT * FROM orders WHERE customer_id = 4412 ORDER BY created_at DESC LIMIT 20",
           "UPDATE sessions SET last_seen = NOW() WHERE id = 'a8f3'", "INSERT INTO audit_log (actor, action, ts) VALUES (?, ?, ?)",
           "SELECT COUNT(*) FROM users", "COMMIT", "DELETE FROM cart_items WHERE cart_id = 99812",
           "SELECT p.id, p.name, SUM(oi.qty) FROM products p JOIN order_items oi ON oi.product_id = p.id GROUP BY p.id",
           "ALTER TABLE events ADD COLUMN tenant_id INT", "SELECT SLEEP(5)"]


def _k(n):
    return f"{n / 1e6:.1f}M" if n >= 1e6 else f"{n / 1e3:.1f}k" if n >= 1e3 else str(n)


def generate(rng):
    d = Doc()
    host = rng.choice(["localhost", "db01", "mysql-primary.internal", "10.0.4.17"])
    ver = rng.choice(["8.0.35", "5.7.44-log", "8.0.33-0ubuntu0.22.04.2", "10.6.16-MariaDB-0ubuntu0.22.04.1", "8.4.2"])
    up = f"{rng.randint(0, 400)}+{rng.randint(0, 23):02d}:{rng.randint(0, 59):02d}:{rng.randint(0, 59):02d}"
    now = f"[{fake.date(rng, 'time')}]"
    server = f"MySQL on {host} ({ver})"
    load = rng.random() < .7
    cells = [server]
    text = server
    if load:
        lv = f"{rng.uniform(0, 8):.2f} {rng.uniform(0, 8):.2f} {rng.uniform(0, 8):.2f} {rng.randint(1, 12)}/{rng.randint(200, 900)} {rng.randint(1000, 99999)}"
        text = text.ljust(max(rng.choice([40, 50]), len(text) + 2)) + f"load {lv}"
        cells += ["load", lv]
    text += f"  up {up} {now}"
    cells += ["up", up, now]
    d.line(text, "row", cells)

    q = rng.randint(1000, 900000000)
    se, ins, upd, de = (rng.randint(0, 99) for _ in range(4))
    mix = f"{se:02d}/{ins:02d}/{upd:02d}/{de:02d}"
    qps, slow = str(rng.randint(0, 9000)), f"{rng.uniform(0, 9999):.1f}"
    d.line(f" Queries: {_k(q):>5}  qps: {qps:>4} Slow: {slow:>7}         Se/In/Up/De(%):    {mix}", "row",
           ["Queries", _k(q), "qps", qps, "Slow", slow, "Se/In/Up/De(%)", mix])
    sorts, qn, sq = str(rng.randint(0, 999)), str(rng.randint(0, 9000)), f"{rng.uniform(0, 5):.1f}"
    th = str(rng.randint(1, 500))
    run, cached = rng.randint(1, 40), rng.randint(0, 40)
    thd = f"{th} ({run:4d}/{cached:4d})"
    mix2 = f"{rng.randint(0, 99):02d}/{rng.randint(0, 99):02d}/{rng.randint(0, 99):02d}/{rng.randint(0, 99):02d}"
    d.line(f" Sorts: {sorts:>5} qps now: {qn:>4} Slow qps: {sq}  Threads: {th:>4} ({run:4d}/{cached:4d}) {mix2}", "row",
           ["Sorts", sorts, "qps now", qn, "Slow qps", sq, "Threads", f"{th:>4} ({run:4d}/{cached:4d})".strip(), mix2])
    if rng.random() < .8:
        ke = f"{rng.uniform(80, 100):.1f}%"
        bps = f"{_k(rng.randint(10, 9000000)):>5}/{_k(rng.randint(10, 9000000)):>5}"
        nowio = f"{_k(rng.randint(10, 9000000)):>5}/{_k(rng.randint(10, 9000000)):>5}"
        d.line(f" Key Efficiency: {ke}  Bps in/out: {bps}   Now in/out: {nowio}", "row",
               ["Key Efficiency", ke, "Bps in/out", bps.strip(), "Now in/out", nowio.strip()])
    if rng.random() < .3:
        io, sql = rng.choice(["Yes", "Yes", "No"]), rng.choice(["Yes", "Yes", "No"])
        d.line(f" Replication IO:{io} SQL:{sql}", "row", ["Replication IO", io, "SQL", sql])
    d.blank()
    widths = [8, 8, 15, 9, 6, 7, 5]
    head = ["Id", "User", "Host/IP", "DB", "Time", "Cmd", "State", "Query"]

    def fmt(vals):
        return " ".join((v or "")[:widths[c]].rjust(widths[c]) for c, v in enumerate(vals[:7])) + " " + (vals[7] or "")

    d.line(fmt(head), "header", head)
    d.skip(fmt(["--", "----", "-------", "--", "----", "---", "-----", "----------"]))
    for _ in range(rng.randint(1, 18)):
        cmd = rng.choice(["Query", "Sleep", "Sleep", "Sleep", "Binlog", "Connect"])
        user = rng.choice(["root", "app", "webapp", "repl", "reporting", "event_scheduler", "debian-sys-maint"])[:8]
        hostip = rng.choice(["localhost", fake.ip(rng), "web-03.internal", "10.0.12.188"])[:15]
        db = rng.choice(["", "shop", "mysql", "analytics", "information_schema", "app_production"])[:9]
        state = "" if cmd == "Sleep" else rng.choice(["init", "Sending data", "starting", "statistics", "update", "Waiting"])[:5]
        query = "" if cmd == "Sleep" else rng.choice(QUERIES)
        vals = [str(rng.randint(1, 999999)), user, hostip, db, str(rng.randint(0, 99999)), cmd, state, query]
        d.line(fmt(vals).rstrip(), "row", [v if v else None for v in vals])
    return d
