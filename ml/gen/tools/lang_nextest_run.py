"""`cargo nextest run`: right-aligned status words with bracketed durations,
one line per test, a rule, a summary, re-listed failures, and optional
captured STDOUT/STDERR sections."""
from lib import Doc, fake

TOOL = "nextest-run"

MODS = ["tests", "parser::tests", "lexer::tests", "store::tests", "api::handlers::tests", "config::tests", "codec::tests"]
NAMES = ["it_works", "parses_empty_input", "roundtrip", "rejects_bad_header", "handles_unicode", "concurrent_writes",
         "decode_large_frame", "default_config_loads", "retries_on_timeout", "merges_overlapping_ranges",
         "serializes_nested_struct", "empty_vec_is_none"]


def _dur(rng, slow=False):
    v = rng.uniform(60, 400) if slow else rng.choice([rng.uniform(0, .05), rng.uniform(0, 1.5), rng.uniform(0, 30)])
    return f"{v:.3f}s"


def generate(rng):
    d = Doc()
    crate = rng.choice(["my-crate", "tokio-util", "serde_yaml", "acme-api", fake.word(rng) + "-core"])
    if rng.random() < .5:
        d.skip(f"   Compiling {crate} v{fake.version(rng)} (/home/{fake.user(rng)}/src/{crate})")
    d.skip(f"    Finished {rng.choice(['test', '`test` profile'])} [unoptimized + debuginfo] target(s) in {rng.uniform(.1, 90):.2f}s")
    bins = [crate, f"{crate}::integration", f"{crate}::bin/{crate}", f"{crate}::cli"][:rng.randint(1, 4)]
    tests = []
    for _ in range(rng.randint(3, 24)):
        b = rng.choice(bins)
        name = (rng.choice(MODS) + "::" if b == crate else "") + rng.choice(NAMES)
        tests.append((b, name))
    skipped = rng.choice([0, 0, 1, rng.randint(2, 9)])
    sk = f" ({skipped} skipped)" if skipped else ""
    d.skip(f"    Starting {len(tests)} tests across {len(bins)} binar{'y' if len(bins) == 1 else 'ies'}{sk}")
    failed, passed = [], 0
    for b, name in tests:
        st = rng.choices(["PASS", "FAIL", "SLOW", "LEAK", "SIGSEGV"], [40, 4, 2, 1, .3])[0]
        if st == "SLOW":
            dur = f"> {_dur(rng, True)}"
            d.line(f"{'SLOW':>12} [{dur:>9}] {b} {name}", "row", ["SLOW", dur, b, name])
            st = "PASS"
        dur = _dur(rng)
        d.line(f"{st:>12} [{dur:>9}] {b} {name}", "row", [st, dur, b, name])
        if st in ("PASS", "LEAK"):
            passed += 1
        else:
            failed.append((st, dur, b, name))
    show = [f for f in failed if rng.random() < .7]
    for st, dur, b, name in show:
        for stream in ("STDOUT", "STDERR"):
            t = f"--- {stream}:{' ' * rng.randint(8, 16)}{b} {name} ---"
            d.section(t)
            if stream == "STDOUT":
                d.blank()
                d.skip("running 1 test")
                d.line(f"test {name} ... FAILED", "kv", [f"test {name}", "FAILED"])
                d.blank()
            else:
                d.skip(f"thread '{name}' panicked at {rng.choice(['src', 'tests'])}/{rng.choice(['lib', 'integration', 'parser'])}.rs:{rng.randint(1, 900)}:{rng.randint(1, 40)}:")
                d.skip(rng.choice(["assertion `left == right` failed", "called `Option::unwrap()` on a `None` value",
                                   "index out of bounds: the len is 3 but the index is 7"]))
                d.skip("note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace")
        d.blank()
    d.skip("-" * 12)
    total = f"{rng.uniform(.01, 120):.3f}s"
    parts = [f"{len(tests)} tests run", f"{passed} passed"]
    if failed:
        parts.append(f"{len(failed)} failed")
    if skipped:
        parts.append(f"{skipped} skipped")
    summ = f"{parts[0]}: " + ", ".join(parts[1:])
    d.line(f"     Summary [{total:>9}] {summ}", "kv", ["Summary", total, summ])
    for st, dur, b, name in failed:
        d.line(f"{st:>12} [{dur:>9}] {b} {name}", "row", [st, dur, b, name])
    if failed:
        d.skip("error: test run failed")
    return d
