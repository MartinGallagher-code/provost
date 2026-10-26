"""ghz (gRPC load tester) summary: `Summary:` kv block (tab after the key), a
response-time histogram with bars, latency distribution, status/error counts."""
from lib import Doc, fake

TOOL = "ghz"


def _ms(x):
    return f"{x:.2f} ms" if x < 1000 else f"{x / 1000:.2f} s"


def generate(rng):
    d = Doc()
    n = rng.choice([200, 1000, 2000, 5000, 10000, 50000, 100000])
    fast = rng.uniform(0.2, 20)
    slow = fast + rng.uniform(5, rng.choice([50, 400, 4000]))
    avg = fast + (slow - fast) * rng.uniform(.1, .4)
    conc = rng.choice([1, 10, 50, 100, 200])
    total_s = n * avg / 1000 / conc
    d.blank()
    d.section("Summary:")
    pairs = []
    if rng.random() < .3:
        pairs.append(("Name", f"'{rng.choice(['Greeter', 'Search', 'Checkout'])} {rng.choice(['smoke', 'load', 'soak'])} test'"))
    pairs += [("Count", str(n)), ("Total", f"{total_s:.2f} s" if total_s < 60 else f"{total_s / 60:.2f} m"),
              ("Slowest", _ms(slow)), ("Fastest", _ms(fast)), ("Average", _ms(avg)), ("Requests/sec", f"{n / total_s:.2f}")]
    for k, v in pairs:
        d.line(f"  {k}:\t{v}", "kv", [k, v])
    d.blank()
    d.section("Response time histogram:")
    buckets = 11
    counts = [int(n * rng.random() ** 3) for _ in range(buckets)]
    counts[rng.randint(0, 3)] = max(counts) + rng.randint(1, n // 3 + 1)
    tot = sum(counts) or 1
    counts = [c * n // tot for c in counts]
    counts[counts.index(max(counts))] += n - sum(counts)
    mx = max(counts) or 1
    for i in range(buckets):
        mark = fast + (slow - fast) * i / (buckets - 1)
        bar = "∎" * int(40 * counts[i] / mx)
        d.line(f"  {mark:.3f} [{counts[i]}]\t|{bar}", "row", [f"{mark:.3f}", f"[{counts[i]}]"])
    d.blank()
    d.section("Latency distribution:")
    v = fast
    for p in [10, 25, 50, 75, 90, 95, 99]:
        v += (slow - v) * rng.uniform(.05, .35)
        d.line(f"  {p} % in {_ms(v)} ", "row", [f"{p} %", f"in {_ms(v)}"])
    d.blank()
    d.section("Status code distribution:")
    errs = 0 if rng.random() < .6 else rng.randint(1, n // 5)
    codes = [("OK", n - errs)]
    if errs:
        kinds = rng.sample(["Unavailable", "DeadlineExceeded", "Internal", "ResourceExhausted", "Canceled", "Unknown"], rng.randint(1, 3))
        left = errs
        for i, k in enumerate(kinds):
            c = left if i == len(kinds) - 1 else rng.randint(1, max(1, left - (len(kinds) - i - 1)))
            left -= c
            if c > 0:
                codes.append((k, c))
    for k, c in codes:
        d.line(f"  [{k}]   {c} responses   ", "row", [f"[{k}]", f"{c} responses"])
    if errs:
        d.blank()
        d.section("Error distribution:")
        msgs = {"Unavailable": "rpc error: code = Unavailable desc = connection error: desc = \"transport: Error while dialing: dial tcp 10.0.0.12:50051: connect: connection refused\"",
                "DeadlineExceeded": "rpc error: code = DeadlineExceeded desc = context deadline exceeded",
                "Internal": "rpc error: code = Internal desc = stream terminated by RST_STREAM with error code: INTERNAL_ERROR",
                "ResourceExhausted": "rpc error: code = ResourceExhausted desc = grpc: received message larger than max (5242880 vs. 4194304)",
                "Canceled": "rpc error: code = Canceled desc = grpc: the client connection is closing",
                "Unknown": "rpc error: code = Unknown desc = " + rng.choice(["boom", "upstream timeout", "unexpected EOF"])}
        for k, c in codes[1:]:
            d.line(f"  [{c}]   {msgs[k]}   ", "row", [f"[{c}]", msgs[k]])
    d.blank()
    return d
