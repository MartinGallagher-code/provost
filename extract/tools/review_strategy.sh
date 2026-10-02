#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Review Tool for provost-extract
##
## Human spot-check workflow: runs a strategy against its sample file, shows
## detected fields and values, and asks the user to confirm/reject each field.
## Outputs an accuracy report at the end.
##
## Usage: review_strategy.sh STRATEGY_NAME [OPTIONS]
##        review_strategy.sh --help
##
## Part of provost. Copyright (C) 2026 Martin J. Gallagher. GPL-3.0-or-later.
################################################################################

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVOST_EXTRACT_SCRIPT="$EXTRACT_DIR/provost-extract"

usage () {
    cat <<'EOF'
Strategy Review Tool (review_strategy.sh)

Usage: review_strategy.sh STRATEGY_NAME [OPTIONS]

Runs a strategy against its sample file and walks the user through each
extracted field for human verification. Outputs an accuracy report.

Arguments:
  STRATEGY_NAME         Name of the strategy to review (e.g. "json", "syslog")

Options:
  --sample FILE         Override the sample file (default: use strategy's ## Sample: header)
  --auto                Non-interactive mode: just show all fields without prompting
  --format FMT          Output report format: text (default), csv
  -h, --help            Show this help

Interactive Controls:
  y/Enter               Accept field as correct
  n                     Reject field as incorrect
  s                     Skip field (neither correct nor incorrect)
  q                     Quit review early and show partial report

Examples:
  review_strategy.sh json
  review_strategy.sh syslog --sample /tmp/my-syslog.log
  review_strategy.sh csv --auto
EOF
}

# Defaults
opt_strategy=""
opt_sample=""
opt_auto=0
opt_format="text"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage; exit 0 ;;
        --sample)
            [[ $# -lt 2 ]] && echo "error: --sample requires an argument" >&2 && exit 1
            opt_sample="$2"; shift 2 ;;
        --auto)
            opt_auto=1; shift ;;
        --format)
            [[ $# -lt 2 ]] && echo "error: --format requires an argument" >&2 && exit 1
            opt_format="$2"; shift 2 ;;
        -*)
            echo "error: unknown option: $1" >&2; exit 1 ;;
        *)
            if [[ -z "$opt_strategy" ]]; then
                opt_strategy="$1"; shift
            else
                echo "error: unexpected argument: $1" >&2; exit 1
            fi
            ;;
    esac
done

if [[ -z "$opt_strategy" ]]; then
    echo "error: strategy name is required" >&2
    echo "Run 'review_strategy.sh --help' for usage." >&2
    exit 1
fi

# Find strategy file
strategy_file=""
for sf in "$EXTRACT_DIR/strategies"/*/"${opt_strategy}.sh" "$EXTRACT_DIR/strategies/${opt_strategy}.sh"; do
    if [[ -f "$sf" ]]; then
        strategy_file="$sf"
        break
    fi
done

if [[ -z "$strategy_file" ]]; then
    echo "error: strategy not found: $opt_strategy" >&2
    echo "Available strategies:" >&2
    bash "$PROVOST_EXTRACT_SCRIPT" list 2>&1 | head -20 >&2
    exit 1
fi

echo "Strategy file: $strategy_file"

# Read strategy metadata for sample path
if [[ -z "$opt_sample" ]]; then
    # Parse ## Sample: header from strategy file
    n=0
    while IFS= read -r meta_line; do
        n=$((n + 1))
        [[ $n -gt 15 ]] && break
        case "$meta_line" in
            '## Sample: '*)
                opt_sample="${meta_line#'## Sample: '}"
                # Resolve relative to EXTRACT_DIR
                if [[ "${opt_sample:0:1}" != "/" ]]; then
                    opt_sample="$EXTRACT_DIR/$opt_sample"
                fi
                ;;
        esac
    done < "$strategy_file"
fi

if [[ -z "$opt_sample" ]]; then
    echo "error: no sample file found in strategy header and none provided via --sample" >&2
    exit 1
fi

if [[ ! -f "$opt_sample" ]]; then
    echo "error: sample file not found: $opt_sample" >&2
    exit 1
fi

echo "Sample file: $opt_sample"
echo ""

# Run extraction
echo "Running strategy '$opt_strategy' against sample..."
extraction_output=""
extraction_rc=0
extraction_output=$(bash "$PROVOST_EXTRACT_SCRIPT" -s "$opt_strategy" -r "$opt_sample" 2>/dev/null) || extraction_rc=$?

if [[ -z "$extraction_output" ]]; then
    echo "No fields extracted. The strategy did not match or produced no output."
    echo ""
    echo "=== Review Report ==="
    echo "Strategy: $opt_strategy"
    echo "Sample: $opt_sample"
    echo "Result: NO FIELDS EXTRACTED"
    echo "Exit code: $extraction_rc"
    exit 1
fi

# Count fields
total_fields=0
while IFS= read -r line; do
    [[ -n "$line" ]] && total_fields=$((total_fields + 1))
done <<< "$extraction_output"

echo "Extracted $total_fields field(s)."
echo ""

# Review each field
accepted=0
rejected=0
skipped=0
field_reports=""
field_num=0

while IFS= read -r field_line; do
    [[ -z "$field_line" ]] && continue
    field_num=$((field_num + 1))

    # Strip strategy prefix if present
    clean_line="$field_line"
    case "$clean_line" in
        STRAT-*) clean_line="${clean_line#*	}" ;;
    esac

    # Parse field name and value
    field_name="${clean_line%% *}"
    field_value="${clean_line#* }"

    if [[ $opt_auto -eq 1 ]]; then
        # Non-interactive: just show the field
        printf "  [%d/%d] %-30s = %s\n" "$field_num" "$total_fields" "$field_name" "$field_value"
        skipped=$((skipped + 1))
        field_reports="${field_reports}SKIP ${field_name} ${field_value}"$'\n'
        continue
    fi

    # Interactive: show and prompt
    echo "--- Field $field_num/$total_fields ---"
    printf "  Name:  %s\n" "$field_name"
    printf "  Value: %s\n" "$field_value"

    # Read from /dev/tty for interactive input (even when stdin is redirected)
    if [[ -t 0 ]] || [[ -e /dev/tty ]]; then
        printf "  Accept? [Y/n/s/q] "
        if [[ -t 0 ]]; then
            read -r response
        else
            read -r response < /dev/tty
        fi
    else
        echo "  (non-interactive: skipping)"
        response="s"
    fi

    case "${response:-y}" in
        y|Y|"")
            accepted=$((accepted + 1))
            field_reports="${field_reports}OK   ${field_name} ${field_value}"$'\n'
            echo "  -> Accepted"
            ;;
        n|N)
            rejected=$((rejected + 1))
            field_reports="${field_reports}FAIL ${field_name} ${field_value}"$'\n'
            echo "  -> Rejected"
            ;;
        s|S)
            skipped=$((skipped + 1))
            field_reports="${field_reports}SKIP ${field_name} ${field_value}"$'\n'
            echo "  -> Skipped"
            ;;
        q|Q)
            echo "  -> Quit early"
            break
            ;;
        *)
            skipped=$((skipped + 1))
            field_reports="${field_reports}SKIP ${field_name} ${field_value}"$'\n'
            echo "  -> Skipped (unrecognized input)"
            ;;
    esac
    echo ""
done <<< "$extraction_output"

# Compute accuracy
reviewed=$((accepted + rejected))
if [[ $reviewed -gt 0 ]]; then
    # Integer arithmetic for percentage
    accuracy=$(( (accepted * 100) / reviewed ))
else
    accuracy="N/A"
fi

echo ""

if [[ "$opt_format" == "csv" ]]; then
    # CSV report
    echo "strategy,sample,total_fields,accepted,rejected,skipped,accuracy"
    echo "${opt_strategy},${opt_sample},${total_fields},${accepted},${rejected},${skipped},${accuracy}"
else
    # Text report
    echo "=== Review Report ==="
    echo "Strategy:  $opt_strategy"
    echo "Sample:    $opt_sample"
    echo "Total:     $total_fields field(s)"
    echo "Accepted:  $accepted"
    echo "Rejected:  $rejected"
    echo "Skipped:   $skipped"
    if [[ "$accuracy" != "N/A" ]]; then
        echo "Accuracy:  ${accuracy}%"
    else
        echo "Accuracy:  N/A (no fields reviewed)"
    fi
    echo ""
    echo "--- Field Details ---"
    if [[ -n "$field_reports" ]]; then
        printf '%s' "$field_reports"
    fi
    echo "====================="
fi
