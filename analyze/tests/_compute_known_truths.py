#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
"""Generate synthetic datasets and the hand-calculated answers that
``test_known_values_extended.sh`` asserts against (ENV-124).

Usage::

    python3 tests/_compute_known_truths.py --emit samples
    python3 tests/_compute_known_truths.py --print

The first form (re)generates the CSV samples under ``samples/``; the second
prints the truth table the test references. Both modes are deterministic
(seeded), so the next person can verify or regenerate without asking what
the expected values "ought to be".
"""
from __future__ import annotations

import argparse
import math
import random
import statistics
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLES = ROOT / "samples"


# ---------------------------------------------------------------------------
# Datasets

def _benford_value(rng: random.Random) -> int:
    """Draw a single Benford-distributed positive integer.

    P(first digit = d) = log10(1 + 1/d). We sample uniformly in log space
    over a couple of orders of magnitude and round to an integer; that
    yields the Benford distribution exactly.
    """
    return int(round(10 ** (rng.uniform(0, 4))))


def make_benford(seed: int = 1) -> tuple[list[dict], dict]:
    """200 rows. ``benford`` column drawn from log-uniform → first digits
    follow Benford. ``uniform`` column drawn from uniform(1, 1000) → first
    digits do NOT follow Benford. Truth table records the exact chi-square
    statistic for each."""
    rng = random.Random(seed)
    rows = []
    for _ in range(200):
        b = _benford_value(rng)
        u = rng.randint(1, 9999)
        rows.append({"benford": b, "uniform": u})

    expected = [30.1, 17.6, 12.5, 9.7, 7.9, 6.7, 5.8, 5.1, 4.6]

    def chi2(values: list[int]) -> float:
        nonzero = [v for v in values if v != 0]
        first = [int(str(abs(v)).lstrip("0").lstrip(".")[0]) for v in nonzero
                 if str(abs(v)).lstrip("0").lstrip(".")]
        first = [d for d in first if 1 <= d <= 9]
        n = len(first)
        if n < 20:
            return -1.0
        counts = Counter(first)
        s = 0.0
        for d in range(1, 10):
            obs = counts.get(d, 0) / n * 100
            ex = expected[d - 1]
            s += (obs - ex) ** 2 / ex
        return s

    truth = {
        "benford_chi2": round(chi2([r["benford"] for r in rows]), 2),
        "uniform_chi2": round(chi2([r["uniform"] for r in rows]), 2),
    }
    return rows, truth


def make_categorical(seed: int = 2) -> tuple[list[dict], dict]:
    """60 rows. ``device`` and ``os`` are correlated (phone↔iOS/Android,
    laptop↔macOS/Linux/Windows). ``country`` is low-cardinality (3 values)
    so its Cramer's V vs ``device`` is small but computable, and the
    expected-frequency warning fires if the cell count is too low."""
    rng = random.Random(seed)
    rows = []
    cells = [
        ("phone", "iOS", 12),
        ("phone", "Android", 14),
        ("laptop", "macOS", 8),
        ("laptop", "Linux", 9),
        ("laptop", "Windows", 11),
        ("phone", "Linux", 1),
        ("phone", "Windows", 2),
        ("laptop", "iOS", 1),
        ("laptop", "Android", 2),
    ]
    countries = ["US", "UK", "DE"]
    for d, o, n in cells:
        for _ in range(n):
            rows.append({"device": d, "os": o,
                         "country": rng.choice(countries)})
    rng.shuffle(rows)

    # Cramer's V for device vs os (hand calc).
    contingency: dict[tuple[str, str], int] = Counter()
    for r in rows:
        contingency[(r["device"], r["os"])] += 1
    devices = sorted({r["device"] for r in rows})
    oses = sorted({r["os"] for r in rows})
    n = len(rows)
    row_totals = {d: sum(contingency[(d, o)] for o in oses) for d in devices}
    col_totals = {o: sum(contingency[(d, o)] for d in devices) for o in oses}
    # Match provost-analyze's awk (lib/_categorical.sh::run_cramers_v): only
    # iterate observed-cell combinations (`for key in joint`), not all
    # row*col combinations. Zero-observation cells are skipped on both
    # sides — keeps the truth table aligned with what the tool reports.
    chi2 = 0.0
    for (d, o), obs in contingency.items():
        exp = row_totals[d] * col_totals[o] / n
        if exp > 0:
            chi2 += (obs - exp) ** 2 / exp
    k = min(len(devices), len(oses)) - 1
    cramers_v = math.sqrt(chi2 / (n * k))

    truth = {
        "n": n,
        "cramers_v_device_os": round(cramers_v, 4),
        "device_unique": len(devices),
        "os_unique": len(oses),
        "country_unique": 3,
    }
    return rows, truth


def make_spearman(seed: int = 3) -> tuple[list[dict], dict]:
    """15 rows. ``x`` increasing, ``y`` is x squared with a small noise
    floor — pure-monotonic so Spearman ρ is exactly 1.0 by ranks. ``z`` is
    the negative monotonic of x → ρ = -1.0. ``noisy`` is x with a single
    rank inversion swapped in to give a known partial ρ."""
    xs = list(range(1, 16))
    ys = [v * v for v in xs]
    zs = [-v for v in xs]
    noisy = list(xs)
    # Single adjacent swap at positions 7,8 (0-indexed): values 8 and 9
    # become 9 and 8. Spearman ρ for n=15 with one adjacent inversion:
    # sum d_i^2 = 1+1 = 2 → ρ = 1 - 6*2 / (15 * (15^2 - 1)) = 1 - 12/3360
    # = 1 - 0.0035714... = 0.996429.
    noisy[7], noisy[8] = noisy[8], noisy[7]
    rows = [{"x": x, "y": y, "z": z, "noisy": n}
            for x, y, z, n in zip(xs, ys, zs, noisy)]
    truth = {
        "spearman_x_y": 1.000000,
        "spearman_x_z": -1.000000,
        "spearman_x_noisy": round(1 - 6 * 2 / (15 * (15**2 - 1)), 6),
    }
    return rows, truth


def make_bimodal_seeded(seed: int = 4) -> tuple[list[dict], dict]:
    """50 rows drawn from two well-separated normal-ish clusters: 25 rows
    near 10 (peak A), 25 rows near 90 (peak B). Designed so the bimodality
    detector's 10-bin histogram puts A in bin 0-1 and B in bin 8-9 with a
    clean valley near 0 in the middle bins."""
    rng = random.Random(seed)
    rows = []
    for _ in range(25):
        rows.append({"v": round(rng.gauss(10, 3), 2)})
    for _ in range(25):
        rows.append({"v": round(rng.gauss(90, 3), 2)})
    rng.shuffle(rows)
    values = [r["v"] for r in rows]
    truth = {
        "n": len(values),
        "min": round(min(values), 2),
        "max": round(max(values), 2),
        "expect_bimodal": True,
    }
    return rows, truth


# ---------------------------------------------------------------------------
# Emit / print

def _write_csv(path: Path, rows: list[dict]) -> None:
    if not rows:
        path.write_text("")
        return
    cols = list(rows[0].keys())
    lines = [",".join(cols)]
    for r in rows:
        lines.append(",".join(str(r[c]) for c in cols))
    path.write_text("\n".join(lines) + "\n")


GENERATORS = {
    "known_benford.csv": make_benford,
    "known_categorical.csv": make_categorical,
    "known_spearman.csv": make_spearman,
    "known_bimodal_seeded.csv": make_bimodal_seeded,
}


def cmd_emit(target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for filename, gen in GENERATORS.items():
        rows, truth = gen()
        _write_csv(target / filename, rows)
        print(f"wrote {target / filename}: {len(rows)} rows; truth={truth}")


def cmd_print() -> None:
    for filename, gen in GENERATORS.items():
        _, truth = gen()
        print(f"{filename}:")
        for k, v in truth.items():
            print(f"    {k} = {v}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--emit", nargs="?", const=str(SAMPLES),
                        help="Write CSV samples (defaults to samples/)")
    parser.add_argument("--print", action="store_true",
                        help="Print the truth table the tests reference")
    args = parser.parse_args(argv)
    if args.emit:
        cmd_emit(Path(args.emit))
    elif args.print:
        cmd_print()
    else:
        parser.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
