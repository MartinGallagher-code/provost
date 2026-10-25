"""`nyc report` (istanbul text reporter): a pipe table with dashed rules,
directories indented one space and files two, right-aligned percentages, an
Uncovered Line #s column; optionally followed by the text-summary block."""
from lib import Doc

TOOL = "nyc"

DIRS = ["src", "lib", "src/routes", "src/models", "src/utils", "src/middleware", "lib/plugins", "app/services"]
FILES = ["index.js", "app.js", "server.js", "db.js", "auth.js", "user.js", "config.js", "logger.js",
         "validate.js", "cache.js", "router.js", "errors.js", "helpers.js", "session.js", "queue.js",
         "index.ts", "client.ts", "parseArgs.ts", "rateLimiter.js"]


def pct(rng, hit, n):
    if n == 0:
        return "100"
    p = 100 * hit / n
    return "100" if hit == n else ("0" if hit == 0 else f"{p:.2f}".rstrip("0").rstrip("."))


def uncovered(rng):
    if rng.random() < .3:
        return ""
    out, ln = [], rng.randint(1, 30)
    for _ in range(rng.randint(1, 9)):
        if rng.random() < .35:
            e = ln + rng.randint(1, 15)
            out.append(f"{ln}-{e}")
            ln = e
        else:
            out.append(str(ln))
        ln += rng.randint(1, 30)
    s = ",".join(out)
    if len(s) > 28 and rng.random() < .6:
        s = s[:s.rfind(",", 0, 24)] + ",..." if "," in s[:24] else s
    return s


def generate(rng):
    d = Doc()
    tree = {}
    for _ in range(rng.randint(1, 5)):
        dr = rng.choice(DIRS)
        tree.setdefault(dr, set())
        for _ in range(rng.randint(1, 5)):
            tree[dr].add(rng.choice(FILES))
    flat = rng.random() < .2  # a single directory: files directly under All files
    rows = []
    totals = [0] * 8
    body = []
    for dr in sorted(tree):
        drows, dt = [], [0] * 8
        for f in sorted(tree[dr]):
            nums = []
            for _ in range(4):
                n = rng.randint(0, 300)
                h = n if rng.random() < .3 else rng.randint(0, n)
                nums += [h, n]
            dt = [a + b for a, b in zip(dt, nums)]
            drows.append([("  " if not flat else " ") + f] +
                         [pct(rng, nums[i], nums[i + 1]) for i in (0, 2, 4, 6)] + [uncovered(rng)])
        totals = [a + b for a, b in zip(totals, dt)]
        if not flat:
            body.append([" " + dr] + [pct(rng, dt[i], dt[i + 1]) for i in (0, 2, 4, 6)] + [""])
        body += drows
        if flat:
            break
    rows.append(["All files"] + [pct(rng, totals[i], totals[i + 1]) for i in (0, 2, 4, 6)] + [""])
    rows += body
    header = ["File", "% Stmts", "% Branch", "% Funcs", "% Lines", "Uncovered Line #s"]
    w = [max(len(r[c]) for r in rows + [header]) for c in range(6)]

    def render(r, head=False):
        out = r[0].ljust(w[0]) + " |"
        for c in range(1, 5):
            out += " " + (r[c].ljust(w[c]) if head else r[c].rjust(w[c])) + " |"
        return out + " " + r[5].ljust(w[5]) + " "

    rule = "-" * (w[0] + 1) + "|" + "|".join("-" * (w[c] + 2) for c in range(1, 5)) + "|" + "-" * (w[5] + 2)
    d.skip(rule)
    d.line(render(header, True), "header", header)
    d.skip(rule)
    for r in rows:
        d.line(render(r), "row", [r[0].strip()] + r[1:5] + [r[5] or None])
    d.skip(rule)
    if rng.random() < .45:  # --reporter=text-summary as well
        d.blank()
        d.skip("=============================== Coverage summary ===============================")
        for i, k in enumerate(["Statements", "Branches", "Functions", "Lines"]):
            h, n = totals[2 * i], totals[2 * i + 1]
            p = pct(rng, h, n)
            v = f"{p}% ( {h}/{n} )"
            d.line(f"{k:<13}: {v}", "kv", [k, v])
        d.skip("=" * 80)
    return d
