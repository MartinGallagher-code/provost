#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Confidence-ceiling tests (QD-056)
##
## The ceilings that prune detection are read by ONE awk over every strategy
## file (lib/_ceiling.awk, through _strategy_ceiling), not one awk per file.
## These tests keep the per-file scan it replaced as the oracle: every shipped
## strategy, and plugin strategies of every shape, must get the ceiling the
## old scan gave. A shim on PATH counts the awk processes a small capture
## starts, so the per-file scan cannot come back unnoticed.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Confidence-ceiling Tests"
echo "========================================"

ENGINE_DIR="$(dirname "$PROVOST_EXTRACT_SCRIPT")"
CT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/ceil_tests.XXXXXX")"
REAL_AWK="$(command -v awk)"

# THE ORACLE: _strategy_ceiling as it was before QD-056, one awk per file.
_old_ceiling () {
    local c
    c="$(awk '
        /^## Confidence-Max:/ { hdr = $3 + 0; have = 1 }
        {
            line = $0; sub(/^[ \t]+/, "", line)
            if (line ~ /^#/) next
            while ((i = index(line, "_STRATEGY_CONFIDENCE=")) > 0) {
                rest = substr(line, i + 21)
                if (match(rest, /^[0-9]+/)) {
                    v = substr(rest, 1, RLENGTH) + 0; if (v > mx) mx = v
                } else computed = 1
                line = rest
            }
        }
        END {
            if (have) { print hdr; exit }
            if (computed) { print 100; exit }
            print (mx > 50 ? mx : 50)
        }' "$1" 2>/dev/null)"
    [[ "$c" =~ ^[0-9]+$ ]] || c=100
    printf '%s\n' "$c"
}

# _new_ceilings FILE... — the engine's _strategy_ceiling for each FILE, as
# "CEILING<TAB>FILE" lines, from one fresh engine shell with those files as
# its strategy list (extra env: CT_ENV, as NAME=VALUE words)
_new_ceilings () {
    env ${CT_ENV:-} bash -c '
        set -o pipefail
        source "$1/lib/_log.sh"; source "$1/lib/_helpers.sh"; source "$1/lib/_discovery.sh"
        shift
        _SORTED_STRATEGIES=""
        for f in "$@"; do _SORTED_STRATEGIES+="050|1.0|$f"$'"'"'\n'"'"'; done
        for f in "$@"; do _strategy_ceiling "$f"; printf "%s\t%s\n" "$_CEIL" "$f"; done' \
        _ "$ENGINE_DIR" "$@"
}

_shipped_files () {
    local f
    for f in "$ENGINE_DIR"/strategies/*.sh "$ENGINE_DIR"/strategies/*/*.sh; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
    done
}

test_every_shipped_strategy () {
    local -a files=() ; local f c n=0 bad=0 got
    mapfile -t files < <(_shipped_files)
    assert_line_count_ge "$(printf '%s\n' "${files[@]}")" 200 "the shipped strategies are found"
    got="$(_new_ceilings "${files[@]}")"
    while IFS=$'\t' read -r c f; do
        n=$((n + 1))
        if [[ "$c" != "$(_old_ceiling "$f")" ]]; then
            bad=$((bad + 1)); echo "    $f: new $c, old $(_old_ceiling "$f")"
        fi
    done <<< "$got"
    assert_eq "$n" "${#files[@]}" "one ceiling for every shipped strategy"
    assert_eq "$bad" "0" "every shipped strategy's ceiling equals the per-file scan's"
}

test_awk_table_matches_oracle () {
    # lib/_ceiling.awk on its own, as provost's batch runs it
    local -a files=(); local c f bad=0
    mapfile -t files < <(_shipped_files)
    while IFS=$'\t' read -r c f; do
        [[ "$c" == "$(_old_ceiling "$f")" ]] || bad=$((bad + 1))
    done < <(awk -f "$ENGINE_DIR/lib/_ceiling.awk" "${files[@]}")
    assert_eq "$bad" "0" "lib/_ceiling.awk's table equals the per-file scan's"
}

_plugins () {
    local d="$1"; mkdir -p "$d"
    cat > "$d/hdr.sh" <<'EOF'
## Name: hdr
## Priority: 50
## Confidence-Max: 72
strategy_detect () { local s=40; _STRATEGY_CONFIDENCE=$s; _STRATEGY_CONFIDENCE=95; }
EOF
    cat > "$d/computed.sh" <<'EOF'
## Name: computed
## Priority: 50
strategy_detect () { local x=61; _STRATEGY_CONFIDENCE=$x; return 0; }
EOF
    cat > "$d/literal.sh" <<'EOF'
## Name: literal
## Priority: 50
strategy_detect () {
    # _STRATEGY_CONFIDENCE=$commented (a comment is not read)
    [[ -n "$1" ]] && _STRATEGY_CONFIDENCE=77 || _STRATEGY_CONFIDENCE=30
}
EOF
    cat > "$d/neither.sh" <<'EOF'
## Name: neither
## Priority: 50
strategy_detect () { return 1; }
EOF
    cat > "$d/low.sh" <<'EOF'
## Name: low
strategy_detect () { _STRATEGY_CONFIDENCE=20; }
EOF
    : > "$d/empty.sh"
    printf '## Confidence-Max: 64' > "$d/nonl.sh"       # no final newline
    cat > "$d/twohdr.sh" <<'EOF'
## Confidence-Max: 40
## Confidence-Max: 88
EOF
    cat > "$d/badhdr.sh" <<'EOF'
## Confidence-Max: -5
EOF
}

test_plugin_shapes () {
    local d="$CT_TMP/plug" c f got
    _plugins "$d"
    got="$(_new_ceilings "$d"/*.sh)"
    while IFS=$'\t' read -r c f; do
        assert_eq "$c" "$(_old_ceiling "$f")" "plugin ${f##*/}: the per-file scan's ceiling"
    done <<< "$got"
    assert_contains "$got" "72	$d/hdr.sh" "a ## Confidence-Max header is the ceiling"
    assert_contains "$got" "100	$d/computed.sh" "a computed _STRATEGY_CONFIDENCE=\$x is 100"
    assert_contains "$got" "77	$d/literal.sh" "the largest literal is the ceiling"
    assert_contains "$got" "50	$d/neither.sh" "neither a header nor an assignment: 50"
    assert_contains "$got" "50	$d/empty.sh" "an empty file: 50"
    assert_contains "$got" "100	$d/badhdr.sh" "a header that is not a whole number: 100"
}

test_handed_down_table () {
    # a table handed down (as provost's batch does) is read with no scan; a
    # file it lacks is still scanned
    local d="$CT_TMP/hand" got
    _plugins "$d"
    printf '33\t%s\n' "$d/hdr.sh" > "$CT_TMP/table.tsv"
    got="$(CT_ENV="_PROVOST_CEIL_TABLE=$CT_TMP/table.tsv" _new_ceilings "$d/hdr.sh" "$d/literal.sh")"
    assert_contains "$got" "33	$d/hdr.sh" "the handed-down table is what the engine uses"
    assert_contains "$got" "77	$d/literal.sh" "a file the table lacks is scanned"
}

test_edited_between_runs () {
    local d="$CT_TMP/edit" got
    mkdir -p "$d"
    printf '## Name: e\n## Confidence-Max: 60\n' > "$d/e.sh"
    got="$(_new_ceilings "$d/e.sh")"
    assert_contains "$got" "60	$d/e.sh" "before the edit"
    printf '## Name: e\n## Confidence-Max: 90\n' > "$d/e.sh"
    got="$(_new_ceilings "$d/e.sh")"
    assert_contains "$got" "90	$d/e.sh" "a plugin edited between runs gets its new ceiling"
}

test_plugin_dir_engine_run () {
    # a --plugin-dir strategy whose ceiling decides a pruning: a plugin with a
    # header of 99 is never pruned, and wins over the shipped tsv
    local d="$CT_TMP/pd" out
    mkdir -p "$d"
    cat > "$d/zz-tabs.sh" <<'EOF'
## Name: zz-tabs
## Priority: 99
## Confidence-Max: 99
strategy_detect () { local c=99; [[ "$1" == *$'\t'* ]] && _STRATEGY_CONFIDENCE=$c; }
strategy_extract () { echo "plugged yes"; }
EOF
    printf 'a\tb\n1\t2\n' > "$CT_TMP/in.tsv"
    out="$(run_extract --plugin-dir "$d" --emit-meta -f tsv --max-strategies 1 "$CT_TMP/in.tsv" 2>&1)"
    assert_contains "$out" "zz-tabs" "the plugin, ranked by its ceiling, wins"
}

test_awk_count_small_tsv () {
    # A shim on PATH counts awk processes: the per-file scan started one per
    # strategy (well over 200 for a small TSV); one scan starts a handful.
    local shim="$CT_TMP/shim" log="$CT_TMP/awk.log" n
    mkdir -p "$shim"
    printf '#!/bin/sh\necho x >> "$AWK_COUNT_LOG"\nexec %s "$@"\n' "$REAL_AWK" > "$shim/awk"
    chmod +x "$shim/awk"
    printf 'name\tsize\tkind\nalpha\t10\tfile\nbravo\t20\tdir\n' > "$CT_TMP/small.tsv"
    : > "$log"
    AWK_COUNT_LOG="$log" PATH="$shim:$PATH" \
        bash "$PROVOST_EXTRACT_SCRIPT" --emit-meta -f tsv --max-strategies 1 "$CT_TMP/small.tsv" > /dev/null 2>&1
    n="$(wc -l < "$log")"; n="${n//[!0-9]/}"
    echo "    awk processes for a small TSV: $n"
    if (( n < 1 || n >= 20 )); then
        _assert_failed "a small TSV started $n awk processes (want 1 to 19)"
    fi
}

run_test "ceilings: every shipped strategy equals the per-file scan" test_every_shipped_strategy
run_test "ceilings: lib/_ceiling.awk's table equals the per-file scan" test_awk_table_matches_oracle
run_test "ceilings: plugin strategies of every shape" test_plugin_shapes
run_test "ceilings: a handed-down table is read, gaps are scanned" test_handed_down_table
run_test "ceilings: a plugin edited between runs" test_edited_between_runs
run_test "ceilings: a --plugin-dir strategy in a real run" test_plugin_dir_engine_run
run_test "ceilings: a small TSV starts few awk processes" test_awk_count_small_tsv

print_summary
rc=$?
rm -rf "$CT_TMP"
exit $rc
