#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Numeric-column exclusion visibility (ENV-132)
##
## When envoy-analyze classifies a column as numeric (≥80% of values parse
## as numbers, the remaining ≤20% are non-numeric), the mean/std are
## computed from the numeric subset only and the rest are silently dropped.
## Pre-ENV-132 the user had no way to tell.
##
## This test asserts:
##   1. A clean (100% numeric) column produces no exclusion annotation.
##   2. An 80/20 column produces a "Note: N non-numeric value(s) excluded"
##      line in the Summary stats item.
##   3. --strict on a clean column exits 0; --strict on the 80/20 column
##      exits 1 with a message naming the dirty column.
################################################################################

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANALYZE="$SCRIPT_DIR/../envoy-analyze"

pass=0
fail=0
fail_msgs=()

_check () {
    local name="$1" cond="$2" details="${3:-}"
    if [[ "$cond" == "1" ]]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        fail_msgs+=("$name${details:+: $details}")
    fi
}

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Build the fixtures fresh so the test is self-contained.
cat >"$sandbox/clean.csv" <<'EOF'
id,score
1,10
2,20
3,30
4,40
5,50
EOF

cat >"$sandbox/dirty.csv" <<'EOF'
id,score
a,10
b,20
c,30
d,40
e,50
f,60
g,70
h,80
i,broken
j,broken
EOF

##############################################################################
# 1. Clean column → no Note line
##############################################################################
out=$(bash "$ANALYZE" --all "$sandbox/clean.csv" 2>&1)
_check "clean column shows Mean" \
    "$([[ "$out" == *"Mean: "* ]] && echo 1 || echo 0)"
_check "clean column produces NO non-numeric Note line" \
    "$([[ "$out" != *"non-numeric value"* ]] && echo 1 || echo 0)"

##############################################################################
# 2. 80/20 column → exclusion annotation in Summary stats
##############################################################################
out=$(bash "$ANALYZE" --all "$sandbox/dirty.csv" 2>&1)
_check "dirty column still classified numeric (Mean shows)" \
    "$([[ "$out" == *"Mean: 45"* ]] && echo 1 || echo 0)"
_check "dirty column shows non-numeric exclusion count" \
    "$([[ "$out" == *"2 non-numeric value(s) excluded"* ]] && echo 1 || echo 0)" \
    "expected 'Note: 2 non-numeric value(s) excluded' in: $(echo "$out" | grep -A2 'Summary stats')"
_check "dirty column shows numeric percentage" \
    "$([[ "$out" == *"80.00% numeric"* ]] && echo 1 || echo 0)"

##############################################################################
# 3. --strict
##############################################################################
bash "$ANALYZE" --strict "$sandbox/clean.csv" >/dev/null 2>&1
rc=$?
_check "--strict on clean column exits 0" \
    "$([[ $rc -eq 0 ]] && echo 1 || echo 0)" "rc=$rc"

err=$(bash "$ANALYZE" --strict "$sandbox/dirty.csv" 2>&1 >/dev/null)
rc=$?
_check "--strict on dirty column exits non-zero" \
    "$([[ $rc -ne 0 ]] && echo 1 || echo 0)" "rc=$rc"
_check "--strict error mentions the dirty column name" \
    "$([[ "$err" == *"score"* ]] && echo 1 || echo 0)" "$err"
_check "--strict error mentions the non-numeric count" \
    "$([[ "$err" == *"2 non-numeric"* ]] && echo 1 || echo 0)" "$err"

total=$((pass + fail))
echo ""
echo "Results: $pass/$total passed, $fail failed"
if (( fail > 0 )); then
    printf '  - %s\n' "${fail_msgs[@]}" >&2
    exit 1
fi
echo "All tests passed."
