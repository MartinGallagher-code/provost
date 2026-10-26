"""`gotestsum` (pkgname or testname format): one line per package with a status
glyph, elapsed time / (cached) and optional coverage, then === Skipped /
=== Failed detail blocks and the `DONE N tests, ... in 4.5s` summary."""
from lib import Doc, fake

TOOL = "gotestsum"

MODS = ["github.com/acme/shop", "example.com/svc/api", "gitlab.com/infra/agent", "github.com/octo/cli"]
PKGS = ["internal/config", "internal/server", "internal/store", "internal/auth", "pkg/client", "pkg/retry",
        "cmd/app", "cmd/migrate", "internal/handlers", "internal/queue", "pkg/ratelimit", "internal/cache",
        "internal/metrics", "pkg/version", "internal/db/postgres", "internal/worker"]
TESTS = ["TestLoad", "TestServeHTTP", "TestPut", "TestGetMissing", "TestBackoff", "TestParseFlags",
         "TestTokenExpiry", "TestRoundTrip", "TestMigrateUp", "TestLimiter/burst", "TestCache_Evict",
         "TestHandler/returns_404", "TestWorkerShutdown"]


def elapsed(rng):
    return rng.choice([f"{rng.randint(1, 999)}ms", f"{rng.uniform(1, 30):.3f}s", f"{rng.randint(1, 99)}ms"])


def generate(rng):
    d = Doc()
    mod = rng.choice(MODS)
    full = rng.random() < .3
    pkgs = rng.sample(PKGS, rng.randint(2, len(PKGS)))
    skipped, failed = [], []
    ntests = 0
    testname = rng.random() < .3
    for p in pkgs:
        name = f"{mod}/{p}" if full else p
        r = rng.random()
        n = rng.randint(1, 40)
        if r < .12:
            if testname:
                d.line(f"EMPTY {name}", "row", ["EMPTY", name])
            else:
                d.line(f"∅  {name}", "row", ["∅", name])
            continue
        ntests += n
        if r < .22:
            t = rng.choice(TESTS)
            failed.append((name, t))
            st, g = "FAIL", "✖"
        elif r < .3:
            skipped.append((name, rng.choice(TESTS)))
            st, g = "PASS", "✓"
        else:
            st, g = "PASS", "✓"
        if testname:
            names = rng.sample(TESTS, rng.randint(1, 3))
            if st == "FAIL":
                names.append(failed[-1][1])
            for t in names:
                s = "FAIL" if st == "FAIL" and t == names[-1] else "PASS"
                dur = f"({rng.uniform(0, 3):.2f}s)"
                d.line(f"{s} {name}.{t} {dur}", "row", [s, f"{name}.{t}", dur])
            if rng.random() < .3 or st == "FAIL":
                el = f"({elapsed(rng)})"
                d.line(f"{st} {name} {el}", "row", [st, name, el])
            continue
        cached = st == "PASS" and rng.random() < .3
        el = "(cached)" if cached else f"({elapsed(rng)})"
        text = f"{g}  {name} {el}"
        cells = [g, name, el]
        if rng.random() < .4:
            cov = f"{rng.uniform(0, 100):.1f}% of statements"
            text += f" (coverage: {cov})"
            cells += ["coverage", cov]
        d.line(text, "row", cells)
    if skipped and rng.random() < .8:
        d.blank()
        d.section("=== Skipped")
        for name, t in skipped:
            dur = f"({rng.uniform(0, .1):.2f}s)"
            d.line(f"=== SKIP: {name} {t} {dur}", "row", ["SKIP", name, t, dur])
            d.skip(f"    {t.split('/')[0].lower()}_test.go:{rng.randint(10, 300)}: "
                   + rng.choice(["requires docker", "skipping integration test in short mode", "flaky, see #1234"]))
            d.blank()
    if failed:
        d.blank()
        d.section("=== Failed")
        for name, t in failed:
            dur = f"({rng.uniform(0, 5):.2f}s)"
            d.line(f"=== FAIL: {name} {t} {dur}", "row", ["FAIL", name, t, dur])
            for _ in range(rng.randint(1, 3)):
                d.skip(f"    {t.split('/')[0].lower()}_test.go:{rng.randint(10, 300)}: "
                       + rng.choice(["expected 3, got 2", "unexpected error: context deadline exceeded",
                                     "got status 500, want 200", "mismatch (-want +got):"]))
            d.blank()
    secs = f"{rng.uniform(0.3, 240):.3f}s"
    parts = []
    if rng.random() < .1:
        parts.append(f"{rng.randint(2, 3)} runs")
    parts.append(f"{ntests} tests")
    if skipped:
        parts.append(f"{len(skipped)} skipped")
    if failed:
        parts.append(f"{len(failed)} failure{'s' if len(failed) > 1 else ''}")
    tail = f"in {secs}"
    text = "DONE " + ", ".join(parts) + " " + tail
    if not (failed or (skipped and d.lines[-1] == "")):
        d.blank()
    d.line(text, "row", ["DONE"] + parts + [tail])
    return d
