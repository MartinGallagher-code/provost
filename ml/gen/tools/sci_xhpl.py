"""HPL `xhpl` (HPL.out): banners, `KEY : value` explanations and parameters
(several values per key), then per-test T/V result tables, start/end times,
the residual check with dot leaders, and a `Finished` summary."""
import itertools
from lib import Doc, fake

TOOL = "xhpl"

RULE = "=" * 80
DASH = "-" * 80
DAYS = "Mon Tue Wed Thu Fri Sat Sun".split()
MONS = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()


def _pkv(d, key, vals):
    """HPL prints `KEY    :` then each value right-aligned in 8 columns."""
    text = f"{key:<7}:" + "".join(f"{v:>8} " for v in vals)
    d.line(text, "kv", [key] + vals)


def _ts(t):
    import time
    g = time.gmtime(t)
    return f"{DAYS[g.tm_wday]} {MONS[g.tm_mon - 1]} {g.tm_mday:2d} {g.tm_hour:02d}:{g.tm_min:02d}:{g.tm_sec:02d} {g.tm_year}"


def generate(rng):
    d = Doc()
    ver, date = rng.choice([("2.3", "December 2, 2018"), ("2.2", "February 24, 2016"), ("2.1", "October 26, 2012")])
    d.skip(RULE)
    d.skip(f"HPLinpack {ver}  --  High-Performance Linpack benchmark  --   {date}")
    d.skip("Written by A. Petitet and R. Clint Whaley,  Innovative Computing Laboratory, UTK")
    d.skip("Modified by Piotr Luszczek, Innovative Computing Laboratory, UTK")
    d.skip("Modified by Julien Langou, University of Colorado Denver")
    d.skip(RULE)
    d.blank()
    d.skip("An explanation of the input/output parameters follows:")
    for k, v in [("T/V", "Wall time / encoded variant."), ("N", "The order of the coefficient matrix A."),
                 ("NB", "The partitioning blocking factor."), ("P", "The number of process rows."),
                 ("Q", "The number of process columns."), ("Time", "Time in seconds to solve the linear system."),
                 ("Gflops", "Rate of execution for solving the linear system.")]:
        d.line(f"{k:<7}: {v}", "kv", [k, v])
    d.blank()
    d.skip("The following parameter values will be used:")
    d.blank()
    Ns = sorted(rng.sample([rng.randint(1000, 300000) // 192 * 192 for _ in range(6)], rng.choice([1, 1, 1, 2, 3])))
    NBs = sorted(set(rng.choice([[192], [256], [128], [232], [384], [192, 256], [128, 192, 256]])))
    procs = rng.choice([1, 2, 4, 8, 16, 32, 64, 128])
    P = rng.choice([p for p in (1, 2, 4, 8) if procs % p == 0 and p * p <= procs] or [1])
    Q = procs // P
    PQs = [(P, Q)] + ([(Q, P)] if rng.random() < 0.2 and P != Q else [])
    pfact = rng.sample(["Left", "Crout", "Right"], rng.choice([1, 1, 2]))
    nbmin = rng.choice([["4"], ["2"], ["2", "4"]])
    ndiv = ["2"]
    rfact = rng.sample(["Left", "Crout", "Right"], 1)
    bcast = rng.sample(["1ring", "1ringM", "2ring", "2ringM", "Long", "LongM"], rng.choice([1, 1, 2]))
    depth = rng.choice([["0"], ["1"], ["0", "1"]])
    _pkv(d, "N", [str(n) for n in Ns])
    _pkv(d, "NB", [str(n) for n in NBs])
    pmap = rng.choice(["Row-major process mapping", "Row-major process mapping", "Column-major process mapping"])
    d.line(f"PMAP   : {pmap}", "kv", ["PMAP", pmap])
    _pkv(d, "P", [str(p) for p, _ in PQs])
    _pkv(d, "Q", [str(q) for _, q in PQs])
    _pkv(d, "PFACT", pfact)
    _pkv(d, "NBMIN", nbmin)
    _pkv(d, "NDIV", ndiv)
    _pkv(d, "RFACT", rfact)
    _pkv(d, "BCAST", bcast)
    _pkv(d, "DEPTH", depth)
    swap = rng.choice(["Mix (threshold = 64)", "Spread-roll (long)", "Binary-exchange"])
    for k, v in [("SWAP", swap), ("L1", rng.choice(["transposed form", "no-transposed form"])),
                 ("U", rng.choice(["transposed form", "no-transposed form"])), ("EQUIL", rng.choice(["yes", "no"])),
                 ("ALIGN", "8 double precision words")]:
        d.line(f"{k:<7}: {v}", "kv", [k, v])
    d.blank()
    d.skip(DASH)
    d.blank()
    d.skip("- The matrix A is randomly generated for each test.")
    d.skip("- The following scaled residual check will be computed:")
    d.skip("      ||Ax-b||_oo / ( eps * ( || x ||_oo * || A ||_oo + || b ||_oo ) * N )")
    k1 = "The relative machine precision (eps) is taken to be"
    d.line(f"- {k1}               1.110223e-16", "kv", [k1, "1.110223e-16"])
    k2 = "Computational tests pass if scaled residuals are less than"
    d.line(f"- {k2}                16.0", "kv", [k2, "16.0"])
    d.blank()
    tests = list(itertools.product(Ns, NBs, PQs, pfact, nbmin, rfact, bcast, depth))
    rng.shuffle(tests)
    tests = sorted(tests[:rng.randint(1, 4)], key=lambda t: (t[0], t[1]))
    peak = rng.uniform(20, 3000) * procs
    t0 = rng.randint(1_500_000_000, 1_790_000_000)
    passed = failed = 0
    for N, NB, (p, q), pf, nm, rf, bc, dp in tests:
        d.skip(RULE)
        hdr = ["T/V", "N", "NB", "P", "Q", "Time", "Gflops"]
        d.line(f"{'T/V':<8}{'N':>12}{'NB':>6}{'P':>6}{'Q':>6}{'Time':>19}{'Gflops':>23}", "header", hdr)
        d.skip(DASH)
        code = {"1ring": 0, "1ringM": 1, "2ring": 2, "2ringM": 3, "Long": 4, "LongM": 5}[bc]
        tv = f"W{'R' if pmap.startswith('Row') else 'C'}{dp}{code}{rf[0]}{ndiv[0]}{pf[0]}{nm}"
        gf = peak * rng.uniform(0.5, 0.92) * min(1.0, N / 40000) if N > 0 else 1.0
        secs = (2.0 / 3.0 * N ** 3 + 2.0 * N ** 2) / (gf * 1e9)
        g = f"{gf:.4e}"
        tm = f"{secs:.2f}"
        d.line(f"{tv:<8}{N:>12}{NB:>6}{p:>6}{q:>6}{tm:>19}{g:>23}", "row", [tv, str(N), str(NB), str(p), str(q), tm, g])
        st = _ts(t0)
        t0 += int(secs) + rng.randint(0, 2)
        en = _ts(t0)
        d.line(f"HPL_pdgesv() start time {st}", "kv", ["HPL_pdgesv() start time", st])
        d.blank()
        d.line(f"HPL_pdgesv() end time   {en}", "kv", ["HPL_pdgesv() end time", en])
        d.blank()
        d.skip(DASH)
        res = rng.uniform(1e-4, 1e-2) if rng.random() < 0.93 else rng.uniform(16, 1e6)
        ok = res < 16
        passed += ok
        failed += not ok
        verdict = "PASSED" if ok else "FAILED"
        key = "||Ax-b||_oo/(eps*(||A||_oo*||x||_oo+||b||_oo)*N)"
        val = f"{res:.8e}"
        d.line(f"{key}= {val:>16} ...... {verdict}", "kv", [key, val, verdict])
    d.skip(RULE)
    d.blank()
    d.line(f"Finished {len(tests):6d} tests with the following results:", "kv",
           ["Finished", f"{len(tests)} tests with the following results:"])
    for n, txt in ((passed, "tests completed and passed residual checks,"),
                   (failed, "tests completed and failed residual checks,"),
                   (0, "tests skipped because of illegal input values.")):
        d.line(f"         {n:6d} {txt}", "row", [str(n), txt])
    d.skip(DASH)
    d.blank()
    d.skip("End of Tests.")
    d.skip(RULE)
    return d
