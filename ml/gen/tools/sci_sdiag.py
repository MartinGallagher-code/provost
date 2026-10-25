"""Slurm `sdiag`: a starred banner, key: value counters in blank-separated
blocks, tab-indented scheduler sections, and RPC statistics rows made of
key:value pairs."""
from lib import Doc, fake

TOOL = "sdiag"

DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
RPCS = [("REQUEST_PARTITION_INFO", 2009), ("REQUEST_NODE_INFO_SINGLE", 2040), ("REQUEST_JOB_INFO", 2003),
        ("MESSAGE_NODE_REGISTRATION_STATUS", 1002), ("REQUEST_COMPLETE_BATCH_SCRIPT", 5018),
        ("REQUEST_SUBMIT_BATCH_JOB", 4003), ("MESSAGE_EPILOG_COMPLETE", 6012), ("REQUEST_FED_INFO", 2049),
        ("REQUEST_JOB_USER_INFO", 2039), ("REQUEST_STEP_COMPLETE", 5016), ("REQUEST_JOB_INFO_SINGLE", 2021),
        ("REQUEST_COMPLETE_PROLOG", 5019), ("REQUEST_NODE_INFO", 2007), ("REQUEST_STATS_INFO", 2035),
        ("REQUEST_KILL_JOB", 5032), ("REQUEST_UPDATE_NODE", 3002), ("REQUEST_JOB_STEP_CREATE", 5001),
        ("REQUEST_PING", 1008), ("REQUEST_SHARE_INFO", 2022), ("REQUEST_RESOURCE_ALLOCATION", 4001)]


def _when(rng, epoch):
    import time
    t = time.gmtime(epoch)
    return (f"{DAYS[t.tm_wday]} {MONS[t.tm_mon - 1]} {t.tm_mday:2d} {t.tm_hour:02d}:{t.tm_min:02d}:"
            f"{t.tm_sec:02d} {t.tm_year}"), f"({epoch})"


def _kvblock(d, pairs, indent="", align=True):
    w = max(len(k) for k, _ in pairs) + 1 if align else 0
    for k, v in pairs:
        if isinstance(v, tuple):
            text = indent + (k + ":").ljust(w) + " " + " ".join(v) if align else indent + k + ": " + " ".join(v)
            d.line(text, "kv", [k, *v])
        else:
            text = (indent + (k + ":").ljust(w) + " " + v) if align else (indent + k + ": " + v)
            d.line(text, "kv", [k, v])


def generate(rng):
    d = Doc()
    now = rng.randint(1_600_000_000, 1_790_000_000)
    since = now - rng.randint(600, 86400 * 3)
    star = "*" * 55
    d.skip(star)
    w, e = _when(rng, now)
    d.line(f"sdiag output at {w} {e}", "kv", ["sdiag output at", w, e])
    w, e = _when(rng, since)
    d.line(f"Data since      {w} {e}", "kv", ["Data since", w, e])
    d.skip(star)
    pairs = [("Server thread count", str(rng.randint(1, 256))), ("Agent queue size", str(rng.randint(0, 40))),
             ("Agent count", str(rng.randint(0, 8))), ("Agent thread count", str(rng.randint(0, 64))),
             ("DBD Agent queue size", str(rng.randint(0, 900)))]
    _kvblock(d, pairs, align=rng.random() < 0.6)
    d.blank()
    sub = rng.randint(100, 900000)
    started = int(sub * rng.uniform(0.85, 1.0))
    pairs = [("Jobs submitted", str(sub)), ("Jobs started", str(started)),
             ("Jobs completed", str(int(started * rng.uniform(0.8, 1.0)))),
             ("Jobs canceled", str(rng.randint(0, sub // 20))), ("Jobs failed", str(rng.randint(0, sub // 50)))]
    _kvblock(d, pairs)
    d.blank()
    w, e = _when(rng, now - rng.randint(1, 60))
    _kvblock(d, [("Job states ts", (w, e)), ("Jobs pending", str(rng.randint(0, 50000))),
                 ("Jobs running", str(rng.randint(0, 20000)))])
    d.blank()
    d.section("Main schedule statistics (microseconds):")
    main = [("Last cycle", str(rng.randint(100, 900000))), ("Max cycle", str(rng.randint(10 ** 5, 10 ** 8))),
            ("Total cycles", str(rng.randint(10, 99999))), ("Mean cycle", str(rng.randint(100, 900000))),
            ("Mean depth cycle", str(rng.randint(1, 3000))), ("Cycles per minute", str(rng.randint(0, 60))),
            ("Last queue length", str(rng.randint(0, 50000)))]
    for k, v in main:
        d.kv(k, v, sep=": ", indent="\t")
    d.blank()
    if rng.random() < 0.85:
        d.section("Backfilling stats" + rng.choice(["", " (WARNING: data obtained in the middle of backfilling execution.)"]),
                  "Backfilling stats")
        bf = [("Total backfilled jobs (since last slurm start)", str(rng.randint(0, 900000))),
              ("Total backfilled jobs (since last stats cycle start)", str(rng.randint(0, 9000))),
              ("Total backfilled heterogeneous job components", str(rng.randint(0, 50))),
              ("Total cycles", str(rng.randint(1, 9999)))]
        for k, v in bf:
            d.kv(k, v, indent="\t")
        w, e = _when(rng, now - rng.randint(1, 300))
        d.line(f"\tLast cycle when: {w} {e}", "kv", ["Last cycle when", w, e])
        for k, v in [("Last cycle", str(rng.randint(1000, 9 * 10 ** 7))), ("Max cycle", str(rng.randint(10 ** 6, 10 ** 9))),
                     ("Mean cycle", str(rng.randint(1000, 10 ** 7))), ("Last depth cycle", str(rng.randint(0, 9000))),
                     ("Last depth cycle (try sched)", str(rng.randint(0, 900))), ("Depth Mean", str(rng.randint(0, 9000))),
                     ("Depth Mean (try depth)", str(rng.randint(0, 900))), ("Last queue length", str(rng.randint(0, 50000))),
                     ("Queue length mean", str(rng.randint(0, 50000))), ("Last table size", str(rng.randint(1, 400))),
                     ("Mean table size", str(rng.randint(1, 400)))]:
            if rng.random() < 0.9:
                d.kv(k, v, indent="\t")
        d.blank()
    lat = rng.randint(10, 400)
    d.line(f"Latency for 1000 calls to gettimeofday(): {lat} microseconds", "kv",
           ["Latency for 1000 calls to gettimeofday()", f"{lat} microseconds"])
    d.blank()
    d.section("Remote Procedure Call statistics by message type")
    stats = [(name, code, rng.randint(1, 9_000_000) // rng.choice([1, 10, 1000]), rng.randint(20, 90000))
             for name, code in rng.sample(RPCS, rng.randint(3, len(RPCS)))]
    for name, code, cnt, ave in sorted(stats, key=lambda x: -x[2]):   # sdiag sorts by count
        tot = cnt * ave
        text = f"\t{name:<40}({code:5d}) count:{cnt:<6d} ave_time:{ave:<6d} total_time:{tot}"
        d.line(text, "row", [name, str(code), "count", str(cnt), "ave_time", str(ave), "total_time", str(tot)])
    d.blank()
    d.section("Remote Procedure Call statistics by user")
    users = [("root", 0), ("slurm", rng.choice([64030, 450, 992]))] + [
        (u, rng.randint(1000, 60000)) for u in rng.sample(["alice", "bob", "carol", "jsmith", "mkhan", "lwei", "a.rossi",
                                                             "tnguyen", "svc_jupyter", "ood"], rng.randint(1, 7))]
    ustats = [(u, uid, rng.randint(1, 9_000_000) // rng.choice([1, 10, 1000]), rng.randint(20, 90000)) for u, uid in users]
    for u, uid, cnt, ave in sorted(ustats, key=lambda x: -x[2]):
        text = f"\t{u:<16}({uid:8d}) count:{cnt:<6d} ave_time:{ave:<6d} total_time:{cnt * ave}"
        d.line(text, "row", [u, str(uid), "count", str(cnt), "ave_time", str(ave), "total_time", str(cnt * ave)])
    if rng.random() < 0.7:
        d.blank()
        d.section("Pending RPC statistics")
        if rng.random() < 0.7:
            d.skip("\tNo pending RPCs")
        else:
            for name, code in rng.sample(RPCS[:8], rng.randint(1, 3)):
                n = rng.randint(1, 40)
                d.line(f"\t{name:<40}({code:5d}) count:{n}", "row", [name, str(code), "count", str(n)])
    return d
