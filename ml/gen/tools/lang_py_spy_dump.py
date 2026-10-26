"""`py-spy dump --pid N [--locals]`: process/interpreter header, then one
heading per thread followed by indented stack frames `func (file:line)`."""
from lib import Doc, fake

TOOL = "py-spy-dump"

FUNCS = ["compute", "process", "<module>", "run", "handle", "_bootstrap_inner", "_bootstrap", "wait",
         "get", "select", "serve_forever", "_worker", "main", "__call__", "dispatch_request", "full_dispatch_request",
         "wsgi_app", "_run_once", "run_forever", "run_until_complete", "recv_into", "readinto", "execute",
         "fetchall", "loads", "decode", "raw_decode", "sleep", "acquire", "_wait_for_tstate_lock", "join"]
FILES = ["app.py", "worker.py", "threading.py", "queue.py", "selectors.py", "socketserver.py",
         "flask/app.py", "asyncio/base_events.py", "socket.py", "json/decoder.py", "site-packages/psycopg2/extras.py",
         "concurrent/futures/thread.py", "tasks.py", "/srv/api/handlers/orders.py", "gunicorn/workers/sync.py"]


def generate(rng):
    d = Doc()
    pid = rng.randint(100, 99999)
    cmd = rng.choice(["python app.py", "/usr/bin/python3 -m celery worker -A tasks",
                      "python3 manage.py runserver 0.0.0.0:8000", "/opt/venv/bin/python /opt/venv/bin/gunicorn api:app -w 4",
                      f"python {fake.word(rng)}.py --port {fake.port(rng)}"])
    d.line(f"Process {pid}: {cmd}", "kv", [f"Process {pid}", cmd])
    minor = rng.randint(6, 13)
    ver = f"v3.{minor}.{rng.randint(0, 18)}"
    exe = rng.choice([f"/usr/bin/python3.{minor}", f"/usr/local/bin/python3.{minor}",
                      f"/home/{fake.user(rng)}/.pyenv/versions/3.{minor}.1/bin/python3.{minor}"])
    d.line(f"Python {ver} ({exe})", "kv", ["Python", ver, f"({exe})"])
    d.blank()
    locals_ = rng.random() < .35
    threads = rng.randint(1, 5)
    tid = pid
    for t in range(threads):
        state = rng.choice(["active", "idle", "gil", "active+gil"]) if t == 0 else rng.choice(["idle", "idle", "active"])
        name = "MainThread" if t == 0 else rng.choice([f"Thread-{t}", f"ThreadPoolExecutor-0_{t - 1}",
                                                       "asyncio_0", f"Dummy-{t}", "pydevd.Reader"])
        if rng.random() < .3:
            tid = f"0x{rng.randint(0x7f0000000000, 0x7fffffffffff):X}"
        text = f"Thread {tid} ({state}): \"{name}\""
        d.section(text, text)
        tid = rng.randint(100, 99999)
        for _ in range(rng.randint(1, 9)):
            fn, fl = rng.choice(FUNCS), rng.choice(FILES)
            loc = f"({fl}:{rng.randint(1, 1400)})"
            d.line(f"    {fn} {loc}", "row", [fn, loc])
            if locals_ and rng.random() < .4:
                for title, keys in (("Arguments", ["self", "n", "timeout", "block", "item"]),
                                    ("Locals", ["total", "i", "result", "conn", "rows", "waiter"])):
                    ks = rng.sample(keys, rng.randint(0, 3))
                    if not ks:
                        continue
                    d.section(f"        {title}:", title)
                    for k in ks:
                        v = rng.choice([str(rng.randint(0, 99999)), "None", "True", f"\"{fake.word(rng)}\"",
                                        f"<Connection at 0x{fake.hexid(rng, 12)}>", f"[{rng.randint(0, 9)}, {rng.randint(0, 9)}]",
                                        f"{rng.uniform(0, 10):.3f}"])
                        d.line(f"            {k}: {v}", "kv", [k, v])
    if rng.random() < .3:
        d.blank()
    return d
