#!/bin/bash
################################################################################
## --multi (multi-dataset) tests
##
## One input may hold SEVERAL datasets — iostat prints an avg-cpu kv block AND
## a Device table. --multi splits on blank-line boundaries, groups consecutive
## blocks that detect the same strategy AND share shape (modal token count),
## and emits each group as its own dataset behind a __DATASET__ separator.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "--multi (multi-dataset) Tests"
echo "========================================"

# iostat-like: banner + avg-cpu kv block + Device table = 3 datasets, with the
# avg-cpu block NOT swallowed by the bigger table.
_multi_iostat_input () {
    cat <<'EOF'
Linux 5.15.0-91-generic (host01) 	07/07/2026 	_x86_64_	(8 CPU)

avg-cpu:  %user   %nice %system %iowait  %steal   %idle
           4.21    0.00    1.83    0.42    0.00   93.54

Device            r/s     w/s     rkB/s     wkB/s
sda             12.34    8.91   1024.50    512.30
sdb              3.21    2.10    256.40    128.20
EOF
}

test_multi_iostat_three_datasets () {
    local tmpfile out n
    tmpfile=$(mktemp)
    _multi_iostat_input > "$tmpfile"
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "3" "$n" "three datasets emitted (banner, avg-cpu, Device)"
    assert_contains "$out" "%user" "avg-cpu block survives as its own dataset"
    assert_contains "$out" "Device" "Device table survives as its own dataset"
    assert_contains "$out" "93.54" "avg-cpu values present"
    assert_contains "$out" "1024.50" "Device values present"
}

test_multi_separator_format () {
    local tmpfile out sep
    tmpfile=$(mktemp)
    _multi_iostat_input > "$tmpfile"
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    # separator: __DATASET__ <TAB> n <TAB> strategy <TAB> confidence
    sep=$(printf '%s\n' "$out" | grep '__DATASET__' | head -1)
    assert_contains "$sep" "$(printf '__DATASET__\t1\t')" "separator carries index 1"
}

# A blank-line record STREAM must NOT shatter: its blocks share strategy and
# shape, so they re-form into ONE dataset.
test_multi_record_stream_stays_one () {
    local tmpfile out n
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
Package: nginx
Version: 1.24.0
Priority: optional

Package: curl
Version: 8.5.0
Priority: optional
EOF
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "blank-separated record stream re-forms into one dataset"
    assert_contains "$out" "nginx" "first record present"
    assert_contains "$out" "curl" "second record present"
}

test_multi_conflicts_with_batch () {
    local rc=0
    printf 'x\n' | run_mfe --multi --batch >/dev/null 2>&1 || rc=$?
    assert_eq "1" "$rc" "--multi and --batch conflict"
}

# A `#`-led legend sitting directly above a table — no blank line between —
# is a boundary candidate, but /proc/slabinfo's `# name <active_objs> …` names
# exactly the columns below it, so the parse that reads it as the table's
# HEADER wins on the score and the columns come out named.
_multi_comment_input () {
    cat <<'EOF'
# name            <active_objs> <num_objs> <objsize>
kmalloc-8192          128    128   8192
kmalloc-1024         2048   2048   1024
dentry              48210  48312    192
EOF
}

test_multi_comment_legend_becomes_header () {
    local tmpfile out n
    tmpfile=$(mktemp)
    _multi_comment_input > "$tmpfile"
    out=$(run_mfe --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "a legend that names the columns folds into its table"
    assert_contains "$out" "entry1.name kmalloc-8192" "the legend's words become column names"
    assert_not_contains "$out" "line1 # name" "the legend is not also kept as prose"
}

# ...but only when it actually names the columns. A legend two names short of
# its rows would shift every value, so it is left alone rather than guessed at.
test_multi_undernaming_legend_not_folded () {
    local tmpfile out
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
# date time auth host term
1 07/11/2026 08:02:11 root yes 10.0.1.4 pts/0
2 07/11/2026 08:44:03 alice yes 10.0.1.9 pts/1
3 07/11/2026 09:15:52 bob no 203.0.113.7 ssh
EOF
    out=$(run_mfe --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "line1 # date" "a legend two names short is kept as prose, not guessed at"
    assert_not_contains "$out" "entry1.date 1" "and never labels the rows it does not match"
}

# The single allowed exception: a legend may omit a leading ROW ORDINAL, which
# is generated rather than named. aureport prints `1.`/`2.` down its first
# column and its `# date time …` legend names only the rest.
test_multi_legend_may_omit_row_ordinal () {
    local tmpfile out
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
# date time acct host
1. 03/01/2024 08:12:33 root sshd
2. 03/01/2024 09:45:02 alice sshd
3. 03/02/2024 14:22:17 bob sshd
EOF
    out=$(run_mfe --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "entry1.num 1." "the unnamed ordinal column gets an explicit name"
    assert_contains "$out" "entry1.date 03/01/2024" "and the legend's names land on the right values"
}

# A multi-line comment run is prose, not a header: kept verbatim either way.
test_multi_comment_run_kept_verbatim () {
    local tmpfile out
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
# slabinfo - version: 2.1
# see /proc/slabinfo for the live counters
kmalloc-8192          128    128   8192
kmalloc-1024         2048   2048   1024
dentry              48210  48312    192
EOF
    out=$(run_mfe --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "line1 # slabinfo" "comment run kept verbatim under a lineN field"
    assert_contains "$out" "kmalloc-8192" "the table itself still parses"
}

# A rule line (`------`) is a boundary, never a data row: 7z-benchmark rules off
# its per-dict rows from the Avr/Tot summary below, which is a separate dataset.
_multi_rule_input () {
    cat <<'EOF'
Dict     Speed Usage    R/U Rating
22:      48210   644  12048  77488
23:      47122   641  12211  78221
----------------------------------
Avr:     47666   642  12129  77854
EOF
}

test_multi_rule_line_splits () {
    local tmpfile out n
    tmpfile=$(mktemp)
    _multi_rule_input > "$tmpfile"
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "2" "$n" "a rule line splits the rows above from the summary below"
    assert_not_contains "$out" "------" "the rule line itself is dropped, never a data row"
}

# A count preamble ("running 3 tests") is its own dataset, not the first row of
# the table under it -- but an ordinary HEADER row must never be mistaken for one.
test_multi_count_preamble_splits () {
    local tmpfile out n
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
running 3 tests
test bench_parse_small ... ok
test bench_parse_large ... ok
test bench_encode ... ok
EOF
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "2" "$n" "count preamble splits from the rows below it"
}

test_multi_header_is_not_a_preamble () {
    local tmpfile out n
    tmpfile=$(mktemp)
    # Carries a number and alphabetic words like a preamble, but is column
    # aligned (2+ spaces) -- a header, so it must stay with its rows.
    cat > "$tmpfile" <<'EOF'
TOP 3 PODS   STATUS
pod-1   Running
pod-2   Running
pod-3   Running
EOF
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "an aligned header row is not treated as a count preamble"
}

# The scored search: a boundary that DESTROYS a better whole-input parse must
# be vetoed. kubectl describe has no blank line -- a top kv block runs straight
# into `Conditions:` and `Events:` -- and describe-report handles all three
# shapes together. Any candidate split of it loses content, so the whole input
# must win.
test_multi_scoring_vetoes_a_losing_split () {
    local tmpfile out n
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
Name:                   api-gateway
Namespace:              production
Replicas:               3 desired | 3 updated
Conditions:
  Type           Status  Reason
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
EOF
    out=$(run_mfe --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "a split that loses to the whole-input parse is vetoed"
}

# ...but a split that RECOVERS dropped content must survive the veto: without
# it, only the Device table would be kept and the avg-cpu block lost.
test_multi_scoring_keeps_a_winning_split () {
    local tmpfile out n
    tmpfile=$(mktemp)
    _multi_iostat_input > "$tmpfile"
    out=$(run_mfe --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_contains "$out" "%user" "the avg-cpu block the whole-input parse would drop is kept"
    [ "$n" -ge 2 ] && assert_eq "1" "1" "a split that recovers content survives the veto" \
        || assert_eq "2+" "$n" "a split that recovers content survives the veto"
}

run_test "scoring vetoes a losing split"        test_multi_scoring_vetoes_a_losing_split
run_test "scoring keeps a winning split"        test_multi_scoring_keeps_a_winning_split
run_test "count preamble is its own dataset"    test_multi_count_preamble_splits
run_test "aligned header is not a preamble"     test_multi_header_is_not_a_preamble
run_test "rule line splits, and is dropped"     test_multi_rule_line_splits
run_test "iostat-like input yields 3 datasets"  test_multi_iostat_three_datasets
run_test "separator line format"                test_multi_separator_format
run_test "record stream stays one dataset"      test_multi_record_stream_stays_one
run_test "--multi/--batch conflict"             test_multi_conflicts_with_batch
run_test "legend folds in as the table header"  test_multi_comment_legend_becomes_header
run_test "under-naming legend is not folded"    test_multi_undernaming_legend_not_folded
run_test "legend may omit the row ordinal"      test_multi_legend_may_omit_row_ordinal
run_test "comment run kept verbatim"            test_multi_comment_run_kept_verbatim

print_summary
