"""`python -m cProfile -s cumtime script.py` (pstats print_stats): a calls
summary, `Ordered by:`, then the ncalls/tottime/percall/cumtime table whose
last column is `filename:lineno(function)`."""
from lib import Doc, fake

TOOL = "cProfile"

BUILTIN = ["{built-in method builtins.exec}", "{built-in method time.sleep}", "{method 'append' of 'list' objects}",
           "{built-in method builtins.len}", "{method 'join' of 'str' objects}", "{built-in method _io.open}",
           "{method 'read' of '_io.TextIOWrapper' objects}", "{built-in method marshal.loads}",
           "{method 'disable' of '_lsprof.Profiler' objects}", "{built-in method builtins.isinstance}",
           "{method 'get' of 'dict' objects}", "{built-in method posix.stat}", "{method 'sort' of 'list' objects}",
           "{built-in method _imp.create_dynamic}", "{method 'recv_into' of '_socket.socket' objects}"]
FUNCS = ["<module>", "main", "compute", "load", "parse", "_find_and_load", "_call_with_frames_removed", "decode",
         "raw_decode", "loads", "__init__", "run", "process_row", "fetch", "_get_spec", "get_data", "read",
         "wrapper", "request", "_send_output", "transform", "<listcomp>", "<genexpr>"]
FILES = ["app.py", "worker.py", "<frozen importlib._bootstrap>", "<frozen importlib._bootstrap_external>",
         "<string>", "/usr/lib/python3.{m}/json/decoder.py", "/usr/lib/python3.{m}/json/__init__.py",
         "/usr/lib/python3.{m}/http/client.py", "/usr/lib/python3.{m}/socket.py",
         "/home/{u}/.venv/lib/python3.{m}/site-packages/requests/sessions.py", "utils.py", "models/{w}.py"]


def generate(rng):
    d = Doc()
    minor = rng.randint(7, 13)
    if rng.random() < .3:
        d.skip(f"{rng.randint(1, 99999)} rows processed")
    n = rng.randint(5, 30)
    total = rng.uniform(.001, 120)
    prim = rng.randint(n, 5000000)
    calls = prim + rng.choice([0, 0, rng.randint(1, 50000)])
    pc = f" ({prim} primitive calls)" if calls != prim else ""
    head = f"{calls} function calls{pc} in {total:.3f} seconds"
    cells = [f"{calls} function calls"] + ([f"({prim} primitive calls)"] if pc else []) + [f"in {total:.3f} seconds"]
    d.line(" " * 9 + head, "row", cells)
    d.blank()
    order = rng.choice(["cumulative time", "internal time", "call count", "standard name", "file name"])
    d.line(f"   Ordered by: {order}", "kv", ["Ordered by", order])
    if rng.random() < .35:
        d.line(f"   List reduced from {n + rng.randint(10, 900)} to {n} due to restriction <{n}>", "skip")
    d.blank()
    hc = ["ncalls", "tottime", "percall", "cumtime", "percall", "filename:lineno(function)"]
    d.line("   ncalls  tottime  percall  cumtime  percall filename:lineno(function)", "header", hc)
    cum = total
    for i in range(n):
        if rng.random() < .35:
            fn = rng.choice(BUILTIN)
        else:
            fl = rng.choice(FILES).format(m=minor, u=fake.user(rng), w=fake.word(rng))
            fn = f"{fl}:{rng.randint(0, 1500)}({rng.choice(FUNCS)})"
        nc = rng.choice([1, 1, rng.randint(2, 100), rng.randint(100, 2000000)])
        ncs = str(nc)
        if rng.random() < .12:
            ncs = f"{nc * rng.randint(2, 40)}/{nc}"
        cum = cum * rng.uniform(.4, 1.0) if i else total
        tot = cum * rng.uniform(0, 1) ** 2
        vals = [ncs, f"{tot:.3f}", f"{tot / nc:.3f}", f"{cum:.3f}", f"{cum / nc:.3f}", fn]
        d.line("%9s %8s %8s %8s %8s %s" % tuple(vals), "row", vals)
    d.blank()
    d.blank()
    return d
