#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for ENV-182 — provost-extract dispatch / validate edge cases.
##
## Sub-bug 1 (provost-extract:660-666):
##   Pre-fix: `text=$(head -c $((N+1)))` then `[[ ${#text} -gt N ]]`.
##   `$(...)` strips trailing newlines, so an input of exactly N+1
##   bytes ending in newline(s) shrank to ≤ N bytes after capture
##   and slipped past the size cap. Real symptom: large
##   newline-terminated inputs ignored the --max-input-size limit.
##   Fix: stage stdin into a same-FS temp file with `head -c N+2`,
##   measure raw byte count via `wc -c` BEFORE the `$(<file)` strip,
##   and compare against the cap.
##
## Sub-bug 2 (lib/_dispatch.sh:274):
##   `for k in "${!_bs_strategy_counts[@]}"; do …` aborts under
##   bash 4.x with `set -u` when the assoc array has no keys.
##   Fix: explicit `declare -A foo=()` initializer plus a
##   `${#arr[@]} -gt 0` guard around the loop.
##
## Sub-bug 3 (lib/_dispatch.sh:447):
##   Replay command was constructed with single-quote splices:
##     local cmd="provost-extract --replay '${matched_strategies}'"
##   A value containing `'` produced a broken / injection-prone
##   command that pasted into a shell mis-parses or runs unintended
##   code. Fix: shell-quote each piece via `printf '%q'` so the
##   emitted line round-trips through bash word-splitting.
################################################################################

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Resolve the engine relative to this test dir (tests/.. == the engine root),
# not via a hardcoded "provost-extract" directory name — so the suite runs unchanged
# when the tree is vendored elsewhere (e.g. provost/lib/extract/). Matches helpers.sh.
ENGINE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EE="$ENGINE_ROOT/provost-extract"
DISPATCH="$ENGINE_ROOT/lib/_dispatch.sh"

PASS=0
FAIL=0
_pass () { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
_fail () { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; if [[ -n "${2:-}" ]]; then printf '    %s\n' "$2" >&2; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/env182_test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo ""
echo "========================================"
echo "ENV-182: extract dispatch — oversize, empty-array, replay-quote"
echo "========================================"

###############################################################################
# Section A — oversized-input check fires on newline-terminated input
###############################################################################

# Use a tiny cap so we don't blast the test environment.
SMALL_CAP=64

# A1: input of exactly CAP+1 bytes plus trailing newlines.
# Pre-fix `$(head -c CAP+1)` strips the newlines, so ${#text} ≤ CAP
# and the cap check missed. Post-fix the cap check uses raw byte
# count and fires.
{
    head -c $((SMALL_CAP + 1)) /dev/zero | tr '\0' 'x'
    printf '\n\n\n'
} > "$WORK/oversize.in"

err_out=$(bash "$EE" --max-input-size $SMALL_CAP < "$WORK/oversize.in" 2>&1; echo "rc=$?")
if [[ "$err_out" == *"too large"* && "$err_out" == *"rc=1"* ]]; then
    _pass "oversized stdin (CAP+1 bytes + newlines) triggers --max-input-size cap"
else
    _fail "oversized cap missed newline-terminated input" \
          "$(printf '%s' "$err_out" | head -3)"
fi

# A2: input of exactly CAP bytes (no overflow) is accepted, even when
# trailing newlines push the byte count to CAP+2. The cap is
# inclusive — input <= CAP must NOT trigger the abort. We feed CAP-2
# bytes of payload + 2 trailing newlines for a total of CAP bytes.
{
    head -c $((SMALL_CAP - 2)) /dev/zero | tr '\0' 'x'
    printf '\n\n'
} > "$WORK/under.in"

err_out=$(bash "$EE" --max-input-size $SMALL_CAP < "$WORK/under.in" 2>&1; echo "rc=$?")
if [[ "$err_out" != *"too large"* ]]; then
    _pass "under-cap input is not rejected"
else
    _fail "under-cap input incorrectly rejected" "$(printf '%s' "$err_out" | head -3)"
fi

# A3: drift — the new staging-into-tempfile path is wired in.
if grep -qE 'provost-extract-stage' "$EE" && grep -qE 'wc -c < "\$_raw_stage"' "$EE"; then
    _pass "drift: provost-extract uses temp-file staging + wc -c byte cap"
else
    _fail "drift: provost-extract still uses \${#text}-only oversize check"
fi

###############################################################################
# Section B — empty assoc-array iteration in batch summary
###############################################################################

# B1: source the lib in a fresh shell with `set -u`, declare an empty
# assoc array the same way _dispatch.sh does, and iterate. Pre-fix
# this aborted on bash 4.x; the explicit `=()` initializer is the
# documented fix, so we reproduce that pattern in isolation.
out=$(bash -c 'set -u; declare -A foo=(); for k in "${!foo[@]}"; do echo "$k"; done; echo done' 2>&1)
if [[ "$out" == "done" ]]; then
    _pass "empty assoc array iteration is set -u safe with =() initializer"
else
    _fail "empty assoc array initializer fix didn't hold" "got: $out"
fi

# B2: drift — _dispatch.sh's declaration uses the empty initializer.
if grep -qE 'declare -A _bs_strategy_counts=\(\)' "$DISPATCH"; then
    _pass "drift: _dispatch.sh uses 'declare -A foo=()' for batch counts"
else
    _fail "drift: _dispatch.sh missing empty-init for _bs_strategy_counts"
fi

# B3: drift — the iteration is guarded by a size check.
if grep -qE '\$\{#_bs_strategy_counts\[@\]\} -gt 0' "$DISPATCH"; then
    _pass "drift: _dispatch.sh guards iteration with size check"
else
    _fail "drift: _dispatch.sh missing size-guard around assoc iteration"
fi

###############################################################################
# Section C — replay command shell-quotes each piece
###############################################################################

# C1: drift — `printf '%q'` is wired in for the cmdline build path.
if grep -qE "_qstrats=\\\$\(printf '%q' \"\\\$matched_strategies\"\)" "$DISPATCH"; then
    _pass "drift: _dispatch.sh quotes matched_strategies via printf %q"
else
    _fail "drift: _dispatch.sh missing printf %q for matched_strategies"
fi
if grep -qE "_qfile=\\\$\(printf '%q' \"\\\$file\"\)" "$DISPATCH"; then
    _pass "drift: _dispatch.sh quotes file via printf %q"
else
    _fail "drift: _dispatch.sh missing printf %q for file"
fi
if grep -qE "_qfields=\\\$\(printf '%q' \"\\\$fields\"\)" "$DISPATCH"; then
    _pass "drift: _dispatch.sh quotes fields via printf %q"
else
    _fail "drift: _dispatch.sh missing printf %q for fields"
fi

# C2: drift — the legacy single-quote splice is gone.
if grep -nE "cmd=\"provost-extract --replay '\\\$\{matched_strategies\}'\"" "$DISPATCH" >/dev/null 2>&1; then
    _fail "drift: _dispatch.sh still has legacy single-quote splice for replay"
else
    _pass "drift: legacy single-quote splice removed from _dispatch.sh replay"
fi

# C3: round-trip — quoted output round-trips through eval. We
# simulate the dispatch path by mirroring the new construction in
# isolation; if the values come back equal post-eval, the quoting is
# correct.
matched_strategies="strat1,strat2"
file="it's a name.txt"
fields="a,b,c"
_qstrats=$(printf '%q' "$matched_strategies")
_qfile=$(printf '%q' "$file")
_qfields=$(printf '%q' "$fields")
cmd="provost-extract --replay ${_qstrats} ${_qfile} ${_qfields}"
# Round-trip the cmd through bash word-splitting via `eval set --`.
# After this, $1..$5 contain the parsed argv (provost-extract / --replay /
# strategies / file / fields). The single-quote in $file must
# survive intact.
eval "set -- $cmd"
if [[ "$#" == "5" \
   && "$1" == "provost-extract" \
   && "$2" == "--replay" \
   && "$3" == "$matched_strategies" \
   && "$4" == "$file" \
   && "$5" == "$fields" ]]; then
    _pass "replay command with single-quote in filename round-trips through eval"
else
    _fail "replay round-trip wrong" \
          "argc=$# argv1=$1 argv2=$2 argv3=$3 argv4=$4 argv5=$5"
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
