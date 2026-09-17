#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for ENV-164 — float_cmp delegates to awk; no integer overflow,
##                     no scientific-notation rejection
##
## Pre-ENV-164, `float_cmp` (in `lib/_helpers.sh`) scaled values by 1e6
## and compared via bash arithmetic. That had two latent bugs:
##
##   1. Any value above ~9.2e12 (signed-64-bit max / 1e6) overflowed
##      during the scale step. A column of nanosecond timestamps,
##      financial cents, or large primary-key IDs silently produced
##      wrong comparison results — driving wrong threshold flags,
##      wrong CV / correlation classifications, wrong quality scores.
##
##   2. Scientific notation (`1e-05`, `2.5e7`) was rejected with
##      `value too great for base` because `10#1e-05` is not valid in
##      bash's base-10 arithmetic. awk routinely produces scientific
##      notation from `printf %g` for very small or very large numbers,
##      so a column whose mean rounded outside `[1e-4, 1e6]` could
##      abort the analyze pipeline mid-run.
##
## After the fix, float_cmp is a one-line wrapper around an awk BEGIN
## block. We pin the new behaviour:
##   - Old overflow case (13-digit ints) now compares correctly.
##   - Scientific notation in either operand works.
##   - Negatives, decimals, and equality remain correct.
##   - Invalid operator returns rc=1 (matches old behaviour).
##   - Bash drift guard: the production source no longer contains the
##     `10#${a_int:-0}` overflow-prone scaling line.
################################################################################

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPERS="$EA_DIR/lib/_helpers.sh"

[[ -r "$HELPERS" ]] || { echo "FATAL: $HELPERS missing"; exit 1; }

# shellcheck disable=SC1090
source "$HELPERS"

PASS=0
FAIL=0
_pass () { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
_fail () { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; if [[ -n "${2:-}" ]]; then printf '    %s\n' "$2" >&2; fi; }

echo ""
echo "========================================"
echo "ENV-164: float_cmp via awk (no overflow, no scientific rejection)"
echo "========================================"

###############################################################################
# Section A — overflow regression (the audit's headline)
###############################################################################

# A1: 13-digit ints near the bash-arith overflow boundary.
if float_cmp 9999999999999 ">" 8999999999999; then
    _pass "13-digit > 13-digit (was BUG: bash arith overflowed signed-64)"
else
    _fail "13-digit comparison still wrong"
fi
if float_cmp 9999999999999 "<" 9999999999999.1; then
    _pass "13-digit < 13-digit + small fraction"
else
    _fail "13-digit fractional comparison wrong"
fi

# A2: equal large-int comparison.
if float_cmp 9999999999999 "==" 9999999999999; then
    _pass "13-digit == 13-digit equal"
else
    _fail "13-digit equality wrong"
fi

# A3: 14-15 digit ints (well past the old overflow). At ~16-17 digits
#     IEEE-754 doubles lose precision and adjacent integers round
#     together; we don't pin behaviour past the double's mantissa.
if float_cmp 99999999999999 ">" 99999999999990; then
    _pass "14-digit > 14-digit"
else
    _fail "14-digit comparison wrong"
fi

###############################################################################
# Section B — scientific notation
###############################################################################

# B1: `1e-05` / `1e-04` round-trip without aborting the pipeline.
if float_cmp 1e-05 "<" 1e-04; then
    _pass "1e-05 < 1e-04 (scientific notation)"
else
    _fail "1e-05 < 1e-04 wrong (should be true)"
fi
if float_cmp 1e-04 "<" 1e-05; then
    _fail "1e-04 < 1e-05 wrong (should be false)"
else
    _pass "1e-04 < 1e-05 correctly false"
fi

# B2: large positive scientific notation.
if float_cmp 2.5e7 ">" 2e7; then
    _pass "2.5e7 > 2e7"
else
    _fail "2.5e7 > 2e7 wrong"
fi

# B3: mixed scientific + plain decimal.
if float_cmp 1e3 "==" 1000; then
    _pass "1e3 == 1000 (mixed forms)"
else
    _fail "1e3 == 1000 wrong"
fi

###############################################################################
# Section C — old-behaviour regressions (decimals, negatives, ops)
###############################################################################

if float_cmp 3.14 ">" 2.0; then _pass "3.14 > 2.0"; else _fail "3.14 > 2.0 wrong"; fi
if float_cmp -3.14 "<" 0; then _pass "-3.14 < 0"; else _fail "-3.14 < 0 wrong"; fi
if float_cmp -3.14 ">" -3.15; then _pass "-3.14 > -3.15"; else _fail "-3.14 > -3.15 wrong"; fi
if float_cmp 3.14 "==" 3.140; then _pass "3.14 == 3.140 (trailing-zero invariance)"; else _fail "3.14 == 3.140 wrong"; fi
if float_cmp 5 ">=" 5; then _pass "5 >= 5"; else _fail "5 >= 5 wrong"; fi
if float_cmp 5 "<=" 5; then _pass "5 <= 5"; else _fail "5 <= 5 wrong"; fi
if float_cmp 0 "!=" 1; then _pass "0 != 1"; else _fail "0 != 1 wrong"; fi
if ! float_cmp 0 "!=" 0; then _pass "0 != 0 correctly false"; else _fail "0 != 0 wrong"; fi

# Invalid operator → rc=1 (legacy behaviour).
float_cmp 1 "??" 2; rc=$?
if [[ "$rc" -eq 1 ]]; then
    _pass "invalid operator returns rc=1"
else
    _fail "invalid operator rc unexpected: $rc"
fi

###############################################################################
# Section D — drift guard
###############################################################################

# D1: source no longer contains the overflow-prone `10#${a_int:-0} * 1000000`.
if grep -qF '10#${a_int:-0} * 1000000' "$HELPERS"; then
    _fail "drift: lib/_helpers.sh still has the overflow-prone scaling line"
else
    _pass "drift: overflow-prone bash-arith scaling is gone"
fi

# D2: source delegates to awk.
if grep -qE 'awk -v a=' "$HELPERS"; then
    _pass "drift: float_cmp delegates to awk"
else
    _fail "drift: awk delegation missing"
fi

###############################################################################

echo ""
echo "========================================"
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$((PASS+FAIL))" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "========================================"
    exit 1
fi
echo "All tests passed."
echo "========================================"
