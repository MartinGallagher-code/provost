#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Golden Output Verification for all strategies
##
## Runs each strategy against the sample named by its `## Sample:` header and
## compares the output, LINE FOR LINE AND IN ORDER, to a stored "golden"
## snapshot. This catches silent regressions where extraction logic changes but
## tests still pass because they only check for presence of fields — including
## ordering regressions (the row order of a table is data).
##
## Every strategy MUST have a sample and a golden: a missing `## Sample:`
## header, a header pointing at a missing file, or a missing golden is a
## FAILURE, not a skip. A golden with no strategy behind it is a failure too.
##
## Extra fixtures: `tests/golden/<strategy>@<file>.txt` is the golden for
## `<file>` in the same samples directory as the strategy's `## Sample:` (e.g.
## `tsv@empty-cells.tsv.txt` for `samples/tsv/empty-cells.tsv`). Each one found
## is verified the same way.
##
## Usage:
##   bash verify_strategy_outputs.sh [--update] [--check] [--strategy NAME]
##
##   --update          Write current output as the baseline (runs each strategy
##                     twice and refuses to write a non-deterministic output)
##   --check           Compare current output to baseline (default)
##   --strategy NAME   Verify only the named strategy (repeatable)
##   --verbose         Print PASS lines as well as FAIL
##
## Golden files are stored in: tests/golden/<strategy-name>.txt
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTRACT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVOST_EXTRACT_SCRIPT="$EXTRACT_DIR/provost-extract"
STRATEGIES_DIR="$EXTRACT_DIR/strategies"
GOLDEN_DIR="$SCRIPT_DIR/golden"

mode="check"
opt_strategy_filter=()
opt_verbose=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --update)   mode="update"; shift ;;
        --check)    mode="check"; shift ;;
        --strategy) opt_strategy_filter+=("$2"); shift 2 ;;
        --verbose)  opt_verbose=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; NC=''
fi

TOTAL=0; PASSED=0; FAILED=0
FAILED_NAMES=()

mkdir -p "$GOLDEN_DIR"

################################################################################
## _strategy_index
## Echoes "name<TAB>sample-header" for every strategy file (sample-header is
## the `## Sample:` value, relative to extract/, or empty), sorted by name.
_strategy_index () {
    local strat_file
    for strat_file in "$STRATEGIES_DIR"/*/*.sh; do
        [[ -f "$strat_file" ]] || continue
        awk 'NR > 15 { exit }
             /^## Name: / { n = substr($0, 10) }
             /^## Sample: / && s == "" { s = substr($0, 12) }
             END { if (n != "") printf "%s\t%s\n", n, s }' "$strat_file"
    done | sort
}

################################################################################
## _run_strategy <name> <sample_file>
## Runs the engine with the strategy and plain format; blank lines dropped,
## ORDER KEPT.
_run_strategy () {
    bash "$PROVOST_EXTRACT_SCRIPT" --strategy "$1" --format plain "$2" 2>/dev/null | grep -v '^$' || true
}

_fail () { # <label> <message>
    FAILED=$((FAILED + 1))
    FAILED_NAMES+=("$1")
    printf "  %sFAIL%s: %s — %s\n" "$RED" "$NC" "$1" "$2"
}

# _verify_one <label> <strategy> <sample> <golden>
_verify_one () {
    local label="$1" strat="$2" sample="$3" golden="$4"
    TOTAL=$((TOTAL + 1))
    if [[ ! -f "$sample" ]]; then
        _fail "$label" "sample file not found: ${sample#"$EXTRACT_DIR"/}"
        return
    fi
    local current; current="$(_run_strategy "$strat" "$sample")"
    if [[ "$mode" == "update" ]]; then
        local again; again="$(_run_strategy "$strat" "$sample")"
        if [[ "$current" != "$again" ]]; then
            _fail "$label" "output is not deterministic (two runs differ) — golden not written"
            return
        fi
        printf '%s\n' "$current" > "$golden"
        printf "  %sWROTE%s: %s → %s fields\n" "$GREEN" "$NC" "$label" "$(printf '%s\n' "$current" | grep -c .)"
        PASSED=$((PASSED + 1))
        return
    fi
    if [[ ! -f "$golden" ]]; then
        _fail "$label" "no golden file ${golden#"$EXTRACT_DIR"/} (run --update --strategy $strat and review it)"
        return
    fi
    local expected; expected="$(grep -v '^$' "$golden" || true)"
    if [[ "$current" == "$expected" ]]; then
        PASSED=$((PASSED + 1))
        [[ $opt_verbose -eq 1 ]] && printf "  %sPASS%s: %s\n" "$GREEN" "$NC" "$label"
    else
        _fail "$label" "output differs from golden (order-sensitive)"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$current") | head -12 | sed 's/^/      /'
    fi
}

################################################################################
## Determine list of strategies to test
declare -A SAMPLE_OF=()
all_strategies=()
while IFS=$'\t' read -r _n _s; do
    [[ -z "$_n" ]] && continue
    SAMPLE_OF[$_n]="$_s"
    all_strategies+=("$_n")
done < <(_strategy_index)
if [[ ${#opt_strategy_filter[@]} -gt 0 ]]; then
    for _n in "${opt_strategy_filter[@]}"; do
        [[ -n "${SAMPLE_OF[$_n]+x}" ]] || { echo "Unknown strategy: $_n" >&2; exit 1; }
    done
    run_strategies=("${opt_strategy_filter[@]}")
else
    run_strategies=("${all_strategies[@]}")
fi

echo "========================================"
if [[ "$mode" == "update" ]]; then
    echo "Golden Output Update Mode"
    echo "Writing baselines to: $GOLDEN_DIR/"
else
    echo "Golden Output Verification (order-sensitive)"
fi
echo "========================================"

for strat_name in "${run_strategies[@]}"; do
    sample_rel="${SAMPLE_OF[$strat_name]}"
    if [[ -z "$sample_rel" ]]; then
        TOTAL=$((TOTAL + 1))
        _fail "$strat_name" "no '## Sample:' header"
        continue
    fi
    sample_file="$EXTRACT_DIR/$sample_rel"
    _verify_one "$strat_name" "$strat_name" "$sample_file" "$GOLDEN_DIR/${strat_name}.txt"

    # Extra fixtures: golden/<strategy>@<file>.txt <-> <sample dir>/<file>
    sample_dir="$(dirname "$sample_file")"
    for extra in "$GOLDEN_DIR/${strat_name}@"*.txt; do
        [[ -f "$extra" ]] || continue
        efile="$(basename "$extra" .txt)"; efile="${efile#"${strat_name}@"}"
        _verify_one "$strat_name@$efile" "$strat_name" "$sample_dir/$efile" "$extra"
    done
done

# Orphan goldens: a golden whose strategy no longer exists is dead weight that
# nothing verifies (only checked on a full run).
if [[ ${#opt_strategy_filter[@]} -eq 0 ]]; then
    for g in "$GOLDEN_DIR"/*.txt; do
        [[ -f "$g" ]] || continue
        gname="$(basename "$g" .txt)"; gname="${gname%%@*}"
        if [[ -z "${SAMPLE_OF[$gname]+x}" ]]; then
            TOTAL=$((TOTAL + 1))
            _fail "$(basename "$g")" "golden has no strategy named '$gname'"
        fi
    done
fi

echo ""
echo "========================================"
if [[ "$mode" == "update" ]]; then
    echo "Updated: $PASSED baselines written, $FAILED failed"
else
    echo "Results: $PASSED passed, $FAILED failed (of $TOTAL)"
fi
if [[ $FAILED -gt 0 ]]; then
    printf "%sFailed:%s\n" "$RED" "$NC"
    for n in "${FAILED_NAMES[@]}"; do
        echo "  - $n"
    done
    echo "========================================"
    exit 1
fi
[[ "$mode" == "check" ]] && printf "%sAll strategies match their golden output.%s\n" "$GREEN" "$NC"
echo "========================================"
