#!/bin/bash
################################################################################
## Golden Output Verification for all strategies
##
## Runs each strategy against its first sample file and compares to a stored
## "golden" snapshot.  This catches silent regressions where extraction logic
## changes but tests still pass because they only check for presence of fields.
##
## Usage:
##   bash verify_strategy_outputs.sh [--update] [--check] [--strategy NAME]
##
##   --update          Write current output as the baseline (run once to capture)
##   --check           Compare current output to baseline (default)
##   --strategy NAME   Verify only the named strategy (repeatable)
##   --verbose         Print PASS lines as well as FAIL
##
## Golden files are stored in: tests/golden/<strategy-name>.txt
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MFE_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-extract"
SAMPLES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/samples"
STRATEGIES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/strategies"
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

TOTAL=0; PASSED=0; FAILED=0; SKIPPED=0
FAILED_NAMES=()

mkdir -p "$GOLDEN_DIR"

################################################################################
## _first_sample_file <strategy_name>
## Echoes the path to the first sample file for a strategy, or nothing.
_first_sample_file () {
    local name="$1"
    local sdir="$SAMPLES_DIR/$name"
    [[ -d "$sdir" ]] || return 1
    local f
    for f in "$sdir"/*; do
        [[ -f "$f" ]] || continue
        case "$f" in
            *.md|*/HANDOFF.md) continue ;;
        esac
        echo "$f"
        return 0
    done
    return 1
}

################################################################################
## _get_all_strategies
## Echoes all strategy names (from ## Name: headers) sorted alphabetically.
_get_all_strategies () {
    local strat_file strat_name
    for strat_file in "$STRATEGIES_DIR"/*/*.sh; do
        [[ -f "$strat_file" ]] || continue
        strat_name=""
        while IFS= read -r _line; do
            case "$_line" in
                "## Name: "*) strat_name="${_line#\#\# Name: }"; break ;;
            esac
        done < "$strat_file"
        [[ -n "$strat_name" ]] && echo "$strat_name"
    done | sort
}

################################################################################
## _run_strategy <name> <sample_file>
## Runs mfe with the strategy and plain format. Outputs to stdout.
_run_strategy () {
    local name="$1"
    local sample="$2"
    bash "$MFE_SCRIPT" --strategy "$name" --format plain --raw "$sample" 2>/dev/null \
        | grep -v '^STRAT-' \
        | sed 's/^[A-Z_-]*:[0-9]*	//'
    # Strip any remaining STRAT prefix in case -r flag exposes them
}

################################################################################
## _normalize_output <text>
## Normalize output for comparison: strip STRAT prefix lines, sort lines
## (strategies may emit fields in any order depending on file system).
_normalize_output () {
    echo "$1" | grep -v '^$' | sort
}

################################################################################
## Determine list of strategies to test
if [[ ${#opt_strategy_filter[@]} -gt 0 ]]; then
    all_strategies=("${opt_strategy_filter[@]}")
else
    mapfile -t all_strategies < <(_get_all_strategies)
fi

if [[ "$mode" == "update" ]]; then
    echo "========================================"
    echo "Golden Output Update Mode"
    echo "Writing baselines to: $GOLDEN_DIR/"
    echo "========================================"
else
    echo "========================================"
    echo "Golden Output Verification"
    echo "========================================"
fi

for strat_name in "${all_strategies[@]}"; do
    TOTAL=$((TOTAL + 1))

    # Find sample file
    sample_file=""
    sample_file=$(_first_sample_file "$strat_name") || true

    if [[ -z "$sample_file" ]]; then
        SKIPPED=$((SKIPPED + 1))
        [[ $opt_verbose -eq 1 ]] && printf "  %sSKIP%s: %s (no sample dir)\n" "$YELLOW" "$NC" "$strat_name"
        continue
    fi

    golden_file="$GOLDEN_DIR/${strat_name}.txt"

    # Run extraction
    current_output=$(bash "$MFE_SCRIPT" --strategy "$strat_name" --format plain "$sample_file" 2>/dev/null || true)

    if [[ "$mode" == "update" ]]; then
        echo "$current_output" > "$golden_file"
        printf "  %sWROTE%s: %s → %s fields\n" "$GREEN" "$NC" "$strat_name" "$(echo "$current_output" | grep -c .)"
        PASSED=$((PASSED + 1))
        continue
    fi

    # Check mode: compare to golden
    if [[ ! -f "$golden_file" ]]; then
        SKIPPED=$((SKIPPED + 1))
        printf "  %sSKIP%s: %s (no golden file — run --update first)\n" "$YELLOW" "$NC" "$strat_name"
        continue
    fi

    golden_content=$(cat "$golden_file")

    # Normalize both for comparison (sort fields — order may vary)
    current_norm=$(_normalize_output "$current_output")
    golden_norm=$(_normalize_output "$golden_content")

    if [[ "$current_norm" == "$golden_norm" ]]; then
        PASSED=$((PASSED + 1))
        [[ $opt_verbose -eq 1 ]] && printf "  %sPASS%s: %s\n" "$GREEN" "$NC" "$strat_name"
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$strat_name")
        printf "  %sFAIL%s: %s\n" "$RED" "$NC" "$strat_name"
        # Show diff (first 10 lines)
        echo "    Expected (golden):"
        echo "$golden_norm" | head -5 | sed 's/^/      /'
        echo "    Actual (current):"
        echo "$current_norm" | head -5 | sed 's/^/      /'
    fi
done

echo ""
echo "========================================"
if [[ "$mode" == "update" ]]; then
    echo "Updated: $PASSED baselines written, $SKIPPED skipped (no sample)"
else
    echo "Results: $PASSED passed, $FAILED failed, $SKIPPED skipped"
    if [[ $FAILED -gt 0 ]]; then
        printf "%sFailed strategies:%s\n" "$RED" "$NC"
        for n in "${FAILED_NAMES[@]}"; do
            echo "  - $n"
        done
        echo "========================================"
        exit 1
    else
        printf "%sAll verified strategies match golden output.%s\n" "$GREEN" "$NC"
    fi
fi
echo "========================================"
