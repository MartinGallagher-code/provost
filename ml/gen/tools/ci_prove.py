"""Perl `prove` (TAP::Harness): one dot-leader line per test file (`t/01.t ...
ok`), optional --timer columns, TAP diagnostics for failures, the Test Summary
Report table and the Files=/Tests= timing line with Result: PASS/FAIL."""
from lib import Doc

TOOL = "prove"

NAMES = ["00-load", "00-compile", "01-basic", "02-parse", "03-config", "04-roundtrip", "05-errors",
         "10-api", "11-auth", "20-db", "21-migrations", "30-unicode", "40-pod", "50-cli", "99-pod-coverage",
         "author-critic", "release-kwalitee", "lib/Foo/Bar", "regression/rt12345"]


def cpu(rng):
    v = [rng.uniform(0, .05), rng.uniform(0, .02), rng.uniform(0, 2), rng.uniform(0, .3)]
    vals = [f"{v[0]:.2f} usr", f"{v[1]:.2f} sys", f"{v[2]:.2f} cusr", f"{v[3]:.2f} csys", f"{sum(v):.2f} CPU"]
    text = f"({v[0]:5.2f} usr {v[1]:5.2f} sys + {v[2]:5.2f} cusr {v[3]:5.2f} csys = {sum(v):5.2f} CPU)"
    return text, vals


def generate(rng):
    d = Doc()
    files = sorted(f"{rng.choice(['t', 't', 'xt'])}/{n}.t" for n in rng.sample(NAMES, rng.randint(2, 14)))
    w = max(len(f) for f in files) + rng.randint(2, 6)
    timer = rng.random() < .3
    clock = [rng.randint(0, 23), rng.randint(0, 59), rng.randint(0, 59)]
    failed = []
    total_tests = 0
    for f in files:
        lead = f + " " + "." * (w - len(f)) + " "
        n = rng.randint(1, 120)
        total_tests += n
        r = rng.random()
        if timer:
            clock[2] += rng.randint(0, 3)
            clock[1] += clock[2] // 60
            clock[2] %= 60
            stamp = f"[{clock[0]:02d}:{clock[1] % 60:02d}:{clock[2]:02d}]"
        if r < .1:
            why = rng.choice(["no network", "Author tests not required for installation",
                              "Set RELEASE_TESTING to run", "DBD::Pg not installed"])
            res = f"skipped: {why}"
            if timer:
                d.line(f"{stamp} {lead}{res}", "row", [stamp, f, res])
            else:
                d.line(lead + res, "kv", [f, res])
            total_tests -= n
            continue
        if r < .22:
            bad = rng.randint(1, min(3, n))
            failed.append((f, n, bad))
            d.skip((stamp + " " if timer else "") + lead.rstrip() + " ")
            for _ in range(bad):
                tn = rng.randint(1, n)
                d.skip(f"#   Failed test '{rng.choice(['parses dates', 'round trip', 'handles undef', 'returns 200'])}'")
                d.skip(f"#   at {f} line {rng.randint(10, 300)}.")
                if rng.random() < .7:
                    got, exp = rng.choice([("'2024'", "'2025'"), ("undef", "'foo'"), ("'500'", "'200'")])
                    d.line(f"#          got: {got}", "kv", ["got", got])
                    d.line(f"#     expected: {exp}", "kv", ["expected", exp])
            d.skip(f"# Looks like you failed {bad} test{'s' if bad > 1 else ''} of {n}.")
            res = f"Dubious, test returned {bad} (wstat {bad * 256}, 0x{bad * 256:x})"
            if timer:
                d.line(f"{stamp} {lead}{res}", "row", [stamp, f, res])
            else:
                d.line(lead + res, "kv", [f, res])
            d.line(f"Failed {bad}/{n} subtests ", "row", [f"Failed {bad}/{n} subtests"])
            continue
        if timer:
            ms = f"{rng.randint(5, 4000)} ms"
            text, vals = cpu(rng)
            d.line(f"{stamp} {lead}ok {ms.rjust(8)} {text}", "row", [stamp, f, "ok", ms] + vals)
        else:
            d.line(lead + "ok", "kv", [f, "ok"])
    secs = rng.randint(0, 120)
    text, vals = cpu(rng)
    if timer:
        d.skip(f"[{clock[0]:02d}:{clock[1] % 60:02d}:{clock[2]:02d}]")
    if not failed:
        d.skip("All tests successful.")
    else:
        d.blank()
        d.section("Test Summary Report")
        d.skip("-------------------")
        for f, n, bad in failed:
            ws = bad * 256
            d.line(f"{f} (Wstat: {ws} (exited {bad}) Tests: {n} Failed: {bad})", "row",
                   [f, "Wstat", f"{ws} (exited {bad})", "Tests", str(n), "Failed", str(bad)])
            nums = sorted(rng.sample(range(1, n + 1), bad))
            key = "Failed test" if bad == 1 else "Failed tests"
            d.line(f"  {key}:  {', '.join(map(str, nums))}", "kv", [key, ", ".join(map(str, nums))])
            if rng.random() < .2:
                d.line(f"  Non-zero exit status: {bad}", "kv", ["Non-zero exit status", str(bad)])
    wall = f"{secs} wallclock secs"
    d.line(f"Files={len(files)}, Tests={total_tests}, {secs:2d} wallclock secs {text}", "row",
           ["Files", str(len(files)), "Tests", str(total_tests), wall] + vals)
    d.kv("Result", "FAIL" if failed else "PASS")
    return d
