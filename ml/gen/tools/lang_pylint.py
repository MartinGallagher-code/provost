"""`pylint [--reports=y] pkg`: per-module message lines
`path:line:col: CODE: message (symbol)`, optional report sections with
`+---+` / `+===+` bordered tables, and the score line."""
from lib import Doc, fake

TOOL = "pylint"

MSGS = [("C0114", "Missing module docstring", "missing-module-docstring"),
        ("C0115", "Missing class docstring", "missing-class-docstring"),
        ("C0116", "Missing function or method docstring", "missing-function-docstring"),
        ("C0103", "Variable name \"{v}\" doesn't conform to snake_case naming style", "invalid-name"),
        ("C0301", "Line too long ({n}/100)", "line-too-long"),
        ("C0411", "standard import \"os\" should be placed before third party import \"requests\"", "wrong-import-order"),
        ("W0612", "Unused variable '{v}'", "unused-variable"),
        ("W0611", "Unused import {v}", "unused-import"),
        ("W0613", "Unused argument '{v}'", "unused-argument"),
        ("W0703", "Catching too general exception Exception", "broad-except"),
        ("W1203", "Use lazy % formatting in logging functions", "logging-fstring-interpolation"),
        ("W0201", "Attribute '{v}' defined outside __init__", "attribute-defined-outside-init"),
        ("R0913", "Too many arguments ({n}/5)", "too-many-arguments"),
        ("R0914", "Too many local variables ({n}/15)", "too-many-locals"),
        ("R1705", "Unnecessary \"else\" after \"return\", remove the \"else\" and de-indent the code inside it", "no-else-return"),
        ("R0903", "Too few public methods (1/2)", "too-few-public-methods"),
        ("E1101", "Instance of '{c}' has no '{v}' member", "no-member"),
        ("E0401", "Unable to import '{v}'", "import-error"),
        ("E0602", "Undefined variable '{v}'", "undefined-variable"),
        ("F0010", "error while code parsing: Unable to load file", "parse-error")]
VARS = ["x", "df", "conn", "result", "tmp", "MAX", "cfg", "session", "yaml", "numpy", "requests", "item_id", "args"]


def _bordered(d, header, rows):
    w = [max(len(str(x)) for x in [header[c]] + [r[c] for r in rows]) + 1 for c in range(len(header))]
    rule = "+" + "+".join("-" * x for x in w) + "+"
    d.skip(rule)
    d.line("|" + "|".join(header[c].ljust(w[c]) for c in range(len(header))) + "|", "header", header)
    d.skip("+" + "+".join("=" * x for x in w) + "+")
    for r in rows:
        d.line("|" + "|".join(r[c].ljust(w[c]) for c in range(len(header))) + "|", "row", r)
        d.skip(rule)


def _diff(rng, a, b):
    return "=" if a == b else (f"{a - b:+d}" if isinstance(a, int) else f"{a - b:+.2f}")


def generate(rng):
    d = Doc()
    pkg = rng.choice(["app", "src/service", "mypkg", fake.word(rng)])
    counts = {"convention": 0, "refactor": 0, "warning": 0, "error": 0}
    byid = {}
    for _ in range(rng.randint(1, 5)):
        mod = rng.choice(["utils", "main", "models", "views", "api.client", "db", "tasks", "cli", "__init__"])
        path = pkg + "/" + mod.replace(".", "/") + ".py"
        d.section(f"************* Module {pkg.replace('/', '.')}.{mod}")
        for _ in range(rng.randint(1, 8)):
            code, msg, sym = rng.choice(MSGS)
            msg = msg.format(v=rng.choice(VARS), n=rng.randint(6, 180), c=rng.choice(["Session", "Foo", "Response"]))
            ln, col = str(rng.randint(1, 900)), str(rng.choice([0, 0, 4, 8, rng.randint(1, 60)]))
            sym_s = f"({sym})"
            d.line(f"{path}:{ln}:{col}: {code}: {msg} {sym_s}", "row", [path, ln, col, code, msg, sym_s])
            counts[{"C": "convention", "R": "refactor", "W": "warning", "E": "error", "F": "error"}[code[0]]] += 1
            byid[sym] = byid.get(sym, 0) + 1
    if rng.random() < .45:
        d.blank()
        d.blank()
        d.section("Report")
        d.skip("======")
        stm = rng.randint(30, 4000)
        d.skip(f"{stm} statements analysed.")
        d.blank()
        d.section("Statistics by type")
        d.skip("------------------")
        d.blank()
        rows = []
        for t in ("module", "class", "method", "function"):
            n = rng.randint(0, 60)
            old = n if rng.random() < .6 else max(0, n + rng.randint(-3, 3))
            doc = "NC" if rng.random() < .2 else f"{rng.uniform(0, 100):.2f}"
            rows.append([t, str(n), "NC" if rng.random() < .15 else str(old), _diff(rng, n, old), doc, f"{rng.choice([0, 0, rng.uniform(0, 30)]):.2f}"])
        _bordered(d, ["type", "number", "old number", "difference", "%documented", "%badname"], rows)
        d.blank()
        d.blank()
        if rng.random() < .7:
            d.section("Raw metrics")
            d.skip("-----------")
            d.blank()
            rows = []
            for t in ("code", "docstring", "comment", "empty"):
                n = rng.randint(0, 5000)
                old = n if rng.random() < .5 else max(0, n + rng.randint(-40, 40))
                rows.append([t, str(n), f"{rng.uniform(0, 80):.2f}", str(old), _diff(rng, n, old)])
            _bordered(d, ["type", "number", "%", "previous", "difference"], rows)
            d.blank()
            d.blank()
        d.section("Messages by category")
        d.skip("--------------------")
        d.blank()
        rows = []
        for t in ("convention", "refactor", "warning", "error"):
            n = counts[t]
            old = n if rng.random() < .5 else max(0, n + rng.randint(-5, 5))
            rows.append([t, str(n), str(old), _diff(rng, n, old)])
        _bordered(d, ["type", "number", "previous", "difference"], rows)
        d.blank()
        d.blank()
        d.section("Messages")
        d.skip("--------")
        d.blank()
        rows = [[k, str(v)] for k, v in sorted(byid.items(), key=lambda kv: -kv[1])]
        _bordered(d, ["message id", "occurrences"], rows)
        d.blank()
        d.blank()
    d.blank()
    d.skip("-" * rng.choice([66, 68, 70, 72]))
    score = rng.uniform(-2, 10)
    s = f"{score:.2f}/10"
    if rng.random() < .7:
        prev = rng.uniform(0, 10)
        tail = f"(previous run: {prev:.2f}/10, {score - prev:+.2f})"
        d.line(f"Your code has been rated at {s} {tail}", "kv", ["Your code has been rated at", s, tail])
    else:
        d.line(f"Your code has been rated at {s}", "kv", ["Your code has been rated at", s])
    d.blank()
    return d
