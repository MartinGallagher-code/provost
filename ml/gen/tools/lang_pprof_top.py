"""`go tool pprof -top` (or `pprof -top`): profile metadata lines, then a
right-aligned flat/cum table whose last column (the function) is unnamed."""
from lib import Doc, fake

TOOL = "pprof-top"

PKGS = ["runtime", "main", "net/http", "encoding/json", "sync", "syscall", "bytes", "strings",
        "github.com/acme/api/internal/store", "google.golang.org/grpc", "compress/flate", "reflect",
        "github.com/acme/api/handlers", "crypto/tls", "bufio", "sort", "io"]
FUNCS = {"runtime": ["memmove", "mallocgc", "scanobject", "findObject", "futex", "memclrNoHeapPointers",
                     "mapaccess2_faststr", "gcDrain", "nanotime", "madvise", "(*mspan).nextFreeIndex",
                     "markBits.isMarked", "usleep", "selectgo", "procyield"]}
GENERIC = ["Read", "Write", "(*Server).Serve", "(*conn).serve", "Marshal", "Unmarshal", "(*Mutex).Lock",
           "(*decodeState).object", "Syscall", "Index", "Compare", "(*Decoder).Decode", "handleRequest",
           "(*Store).Get", "(*Store).Put", "parseQuery", "main", "(*Writer).Flush", "(*Value).Interface",
           "(*compressor).deflate", "func1", "(*Reader).ReadSlice", "Copy", "Sort"]


def _fmt(v, unit):
    if unit == "s":
        if v == 0:
            return "0"
        if v < 1:
            return f"{v * 1000:.0f}ms" if v * 1000 >= 10 else f"{v * 1000:.2f}ms"
        return f"{v:.2f}s"
    if v == 0:
        return "0"
    if v < 1024:
        return f"{v:.0f}B"
    if v < 1024 ** 2:
        return f"{v / 1024:.2f}kB"
    if v < 1024 ** 3:
        return f"{v / 1024 ** 2:.2f}MB"
    return f"{v / 1024 ** 3:.2f}GB"


def generate(rng):
    d = Doc()
    kind = rng.choice(["cpu", "cpu", "inuse_space", "alloc_space", "inuse_objects"])
    unit = "s" if kind == "cpu" else ("n" if kind == "inuse_objects" else "B")
    binary = rng.choice(["server", "api", "worker", "main", "ingest", fake.word(rng) + "d"])
    d.kv("File", binary)
    if rng.random() < .4:
        d.kv("Build ID", fake.hexid(rng, 40))
    d.kv("Type", kind)
    mon = rng.choice("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())
    h = rng.randint(1, 12)
    t = f"{mon} {rng.randint(1, 28)}, {rng.randint(2021, 2026)} at {h}:{rng.randint(0, 59):02d}{rng.choice(['am', 'pm'])} ({rng.choice(['UTC', 'CEST', 'PDT', 'EST'])})"
    d.kv("Time", t)
    if unit == "s":
        dur = rng.uniform(5, 120)
        total = dur * rng.uniform(.05, 3.5)
        ds, ts = f"{dur:.2f}s", f"{total:.2f}s" if total >= 1 else f"{total * 1000:.0f}ms"
        pc = f"({100 * total / dur:.2f}%)"
        d.line(f"Duration: {ds}, Total samples = {ts} {pc}", "row", ["Duration", ds, "Total samples", f"{ts} {pc}"])
    else:
        total = rng.uniform(2e5, 5e9) if unit == "B" else rng.randint(2000, 9000000)
    n = rng.randint(6, 30)
    weights = sorted([rng.random() ** 3 for _ in range(n)], reverse=True)
    shown = rng.uniform(.6, .99)
    flats = [total * shown * w / sum(weights) for w in weights]

    def f(v):
        if unit == "n":
            return str(int(v))
        return _fmt(v, unit)

    tot_s = f(total)
    d.skip(f"Showing nodes accounting for {f(sum(flats))}, {100 * shown:.2f}% of {tot_s} total")
    if rng.random() < .6:
        d.skip(f"Dropped {rng.randint(1, 400)} nodes (cum <= {f(total * .005)})")
    if rng.random() < .3:
        d.skip(f"Showing top {n} nodes out of {n + rng.randint(5, 200)}")
    rows = []
    s = 0.0
    for v in flats:
        s += v
        cum = min(total, v + total * rng.random() ** 2 * rng.choice([0, .1, .6]))
        pkg = rng.choice(PKGS)
        name = f"{pkg}.{rng.choice(FUNCS.get(pkg, GENERIC))}"
        if rng.random() < .1:
            name += f".func{rng.randint(1, 4)}"
        if rng.random() < .05:
            name += " (inline)"
        rows.append([f(v), f"{100 * v / total:.2f}%", f"{100 * s / total:.2f}%", f(cum), f"{100 * cum / total:.2f}%", name])
    head = ["flat", "flat%", "sum%", "cum", "cum%"]
    w = [max(len(head[i]), max(len(r[i]) for r in rows)) for i in range(5)]
    w[0] = max(w[0], 10 - 1)
    w[3] = max(w[3], 10)
    d.line(" " + " ".join(head[i].rjust(w[i]) for i in range(5)), "header", head + [None])
    for r in rows:
        d.line(" " + " ".join(r[i].rjust(w[i]) for i in range(5)) + "  " + r[5], "row", r)
    return d
