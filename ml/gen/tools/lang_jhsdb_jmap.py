"""`jhsdb jmap --heap --pid N` (JDK 9+): attach banner, then `key = value`
blocks under heap-configuration and per-generation section headings."""
from lib import Doc

TOOL = "jhsdb-jmap"

MB = 1024 * 1024


def _bytes(n, rng):
    v = n / MB
    s = repr(v) if rng.random() < .35 else f"{v:.1f}"
    return f"{n} ({s}MB)"


def _usage(d, rng, name, cap, g1):
    d.section(f"{name}:")
    used = rng.randint(0, cap)
    pairs = []
    if g1:
        pairs.append(("regions", str(rng.randint(0, 4000))))
    pairs += [("capacity", _bytes(cap, rng)), ("used", _bytes(used, rng)), ("free", _bytes(cap - used, rng))]
    w = max(len(k) for k, _ in pairs)
    for k, v in pairs:
        d.line(f"   {k.ljust(w)} = {v}", "kv", [k, v])
    pct = 100.0 * used / cap if cap else 0.0
    p = f"{pct}% used" if rng.random() < .7 else f"{pct:.1f}% used"
    d.line(f"   {p}", "row", [p])


def generate(rng):
    d = Doc()
    pid = rng.randint(300, 99999)
    d.skip(f"Attaching to process ID {pid}, please wait...")
    d.skip("Debugger attached successfully.")
    d.skip(rng.choice(["Server compiler detected.", "Client compiler detected."]))
    ver = rng.choice(["11.0.20+8-post-Ubuntu-1ubuntu122.04", "17.0.8+7-LTS", "21.0.1+12-29",
                      f"17.0.{rng.randint(1, 12)}+{rng.randint(1, 9)}", f"11.0.{rng.randint(1, 22)}+{rng.randint(1, 9)}-LTS"])
    d.line(f"JVM version is {ver}", "kv", ["JVM version is", ver])
    d.blank()
    gc = rng.choice(["g1", "parallel", "serial"])
    threads = rng.choice([1, 2, 4, 8, 13, 16])
    d.skip("using thread-local object allocation.")
    d.skip({"g1": f"Garbage-First (G1) GC with {threads} thread(s)",
            "parallel": f"Parallel GC with {threads} thread(s)",
            "serial": "Mark Sweep Compact GC"}[gc])
    d.blank()
    d.section("Heap Configuration:")
    maxheap = rng.choice([256, 512, 1024, 2048, 3978, 4096, 7953, 16384]) * MB
    region = rng.choice([1, 2, 4, 8]) * MB
    conf = [("MinHeapFreeRatio", str(rng.choice([0, 10, 40]))),
            ("MaxHeapFreeRatio", str(rng.choice([70, 100]))),
            ("MaxHeapSize", _bytes(maxheap, rng)),
            ("NewSize", _bytes(rng.choice([1363144, 44564480, 89128960]), rng)),
            ("MaxNewSize", _bytes(maxheap // rng.choice([2, 3]), rng)),
            ("OldSize", _bytes(rng.choice([5452592, 89653248, 179306496]), rng)),
            ("NewRatio", str(rng.choice([2, 3]))),
            ("SurvivorRatio", str(rng.choice([8, 6]))),
            ("MetaspaceSize", _bytes(rng.choice([21, 22]) * MB + rng.choice([0, 20096]), rng)),
            ("CompressedClassSpaceSize", _bytes(1024 * MB, rng)),
            ("MaxMetaspaceSize", "17592186044415 MB")]
    if gc == "g1":
        conf.append(("G1HeapRegionSize", _bytes(region, rng)))
    w = max(len(k) for k, _ in conf)
    for k, v in conf:
        d.line(f"   {k.ljust(w)} = {v}", "kv", [k, v])
    d.blank()
    d.section("Heap Usage:")
    if gc == "g1":
        _usage(d, rng, "G1 Heap", maxheap, True)
        d.section("G1 Young Generation:")
        for sp in ("Eden Space", "Survivor Space"):
            _usage(d, rng, sp, rng.randint(1, 400) * region, True)
        _usage(d, rng, "G1 Old Generation", rng.randint(1, 900) * region, True)
    else:
        young = "PS Young Generation" if gc == "parallel" else "New Generation (Eden + 1 Survivor Space)"
        if gc == "parallel":
            d.section(young + ":")
            for sp in ("Eden Space", "From Space", "To Space"):
                _usage(d, rng, sp, rng.randint(1, 600) * MB, False)
            _usage(d, rng, "PS Old Generation", rng.randint(50, 3000) * MB, False)
        else:
            _usage(d, rng, young, rng.randint(5, 300) * MB, False)
            for sp in ("Eden Space", "From Space", "To Space"):
                _usage(d, rng, sp, rng.randint(1, 200) * MB, False)
            _usage(d, rng, "tenured generation", rng.randint(20, 900) * MB, False)
    if rng.random() < .4:
        d.blank()
        d.skip(f"{rng.randint(2000, 90000)} interned Strings occupying {rng.randint(100000, 9000000)} bytes.")
    return d
