"""radon `radon cc [-s] [-a] PATH`: a file path, then one indented line per
block (type, line:col, name, rank, optional score), and an average summary."""
from lib import Doc, fake

TOOL = "radon-cc"

NAMES = ["handle_request", "main", "parse", "Config", "Config.load", "Server", "Server.start",
         "Server._accept_loop", "_helper", "validate_payload", "Cache.get", "Cache", "render_template",
         "migrate_legacy_records_in_batches", "Worker.run", "__init__"]


def rank(c):
    return "A" if c <= 5 else "B" if c <= 10 else "C" if c <= 20 else "D" if c <= 30 else "E" if c <= 40 else "F"


def generate(rng):
    d = Doc()
    show = rng.random() < .7
    avg = rng.random() < .6
    blocks = []
    for _ in range(rng.randint(1, 5)):
        p = rng.choice(["", "src/", "app/", f"{fake.word(rng)}/"]) + fake.word(rng) + rng.choice(["", "_utils", "s"]) + ".py"
        d.line(p, "section", [p])
        for _ in range(rng.randint(1, 7)):
            kind = rng.choice("FFMMC")
            name = rng.choice(NAMES)
            lc = f"{rng.randint(1, 900)}:{rng.choice([0, 0, 4, 8])}"
            c = rng.choice([1, 1, 2, 3, 4, 6, 9, 12, 25, 41])
            blocks.append(c)
            text = f"    {kind} {lc} {name} - {rank(c)}"
            cells = [kind, lc, name, rank(c)]
            if show:
                text += f" ({c})"
                cells.append(f"({c})")
            d.line(text, "row", cells)
    if avg:
        d.blank()
        d.skip(f"{len(blocks)} blocks (classes, functions, methods) analyzed.")
        a = sum(blocks) / len(blocks)
        r, sc = rank(round(a)), f"({a:.{rng.choice([2, 15])}f})"
        d.line(f"Average complexity: {r} {sc}", "kv", ["Average complexity", r, sc])
    return d
