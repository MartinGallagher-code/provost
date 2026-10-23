#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

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
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
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
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    # separator: __DATASET__ <TAB> n <TAB> strategy <TAB> confidence
    sep=$(printf '%s\n' "$out" | grep '__DATASET__' | head -1)
    assert_contains "$sep" "$(printf '__DATASET__\t1\t')" "separator carries index 1"
}

# PROVOST_MULTI_TEXT_DIR: each emitted dataset's own input text lands in
# DIR/ds.N.txt (provost re-reads a gate-rejected part with the layout model).
test_multi_text_dir () {
    local tmpfile dir out n
    tmpfile=$(mktemp); dir=$(mktemp -d)
    _multi_iostat_input > "$tmpfile"
    out=$(PROVOST_MULTI_TEXT_DIR="$dir" run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "$(ls "$dir" | grep -c '^ds\.[0-9]*\.txt$')" "$n" "one ds.N.txt per dataset"
    assert_contains "$(cat "$dir"/ds.*.txt)" "avg-cpu" "the parts' text is the input's"
    rm -rf "$tmpfile" "$dir"
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
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "blank-separated record stream re-forms into one dataset"
    assert_contains "$out" "nginx" "first record present"
    assert_contains "$out" "curl" "second record present"
}

test_multi_conflicts_with_batch () {
    local rc=0
    printf 'x\n' | run_extract --multi --batch >/dev/null 2>&1 || rc=$?
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
    out=$(run_extract --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "a legend that names the columns folds into its table"
    assert_contains "$out" "entry1.name kmalloc-8192" "the legend's words become column names"
    assert_not_contains "$out" "entry1.text # name" "the legend is not also kept as prose"
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
    out=$(run_extract --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "entry1.text # date" "a legend two names short is kept as prose, not guessed at"
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
    out=$(run_extract --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
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
    out=$(run_extract --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "entry1.text # slabinfo" "comment run kept verbatim, one row per line"
    assert_contains "$out" "kmalloc-8192" "the table itself still parses"
}

# An ASCII box drawn with `+---+` rules and `|` fences is ONE table, not three
# datasets. The rules look like boundaries, so the split shreds it — and the
# shredded parse used to WIN, because the frame lines it kept counted as
# recovered content while nothing charged the cells that were just `|`.
test_multi_pipe_box_stays_one_table () {
    local tmpfile out n
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
--------------------------------------------------
|                  ListBuckets                   |
+----------------------------+-------------------+
|            Name            |   CreationDate    |
+----------------------------+-------------------+
|  acme-prod-assets          |  2024-03-11T08:14Z |
|  acme-prod-logs            |  2024-03-11T08:15Z |
|  acme-terraform-state      |  2023-11-02T19:41Z |
EOF
    out=$(run_extract --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "1" "$n" "an ASCII box is one table, not a split"
    assert_contains "$out" "acme-prod-assets" "the rows survive"
    assert_not_contains "$out" ".A |" "a cell that is only a delimiter never survives"
}

# A comment run whose every line is `# key: value` is a kv block that happens
# to be commented out, not prose. age-keygen writes its metadata that way.
test_multi_commented_kv_is_parsed () {
    local tmpfile out
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
# created: 2026-07-10T06:00:00Z
# public key: age1abc123def456
AGE-SECRET-KEY-1QQQQQQQQQQQQQQQ
EOF
    out=$(run_extract --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "entry1.key created" "a commented kv run parses as key/value"
    assert_contains "$out" "entry2.value age1abc123def456" "and keeps its values"
}

# ...but a comment run that is NOT all `key: value` stays verbatim prose.
test_multi_mixed_comment_run_stays_text () {
    local tmpfile out
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
# slabinfo - version: 2.1
# see the live counters
kmalloc-8192          128    128   8192
kmalloc-1024         2048   2048   1024
dentry              48210  48312    192
EOF
    out=$(run_extract --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    assert_contains "$out" "entry1.text # slabinfo" "a mixed comment run is still kept verbatim"
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
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
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
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "2" "$n" "count preamble splits from the rows below it"
}

# The lead signature collapses a digit RUN to one `#`. Per-digit, an address
# table never looks uniform — `10.0.0.1` and `10.0.0.100` differ — so the rows
# below a preamble failed the same-shape test purely on octet width.
test_multi_preamble_over_varied_width_numbers () {
    local tmpfile out n
    tmpfile=$(mktemp)
    cat > "$tmpfile" <<'EOF'
Scanning 3 hosts
10.0.0.1     up
10.0.0.10    up
10.0.0.100   up
EOF
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "2" "$n" "rows differing only in digit count still count as one shape"
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
    out=$(run_extract --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
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
    out=$(run_extract --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
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
    out=$(run_extract --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_contains "$out" "%user" "the avg-cpu block the whole-input parse would drop is kept"
    [ "$n" -ge 2 ] && assert_eq "1" "1" "a split that recovers content survives the veto" \
        || assert_eq "2+" "$n" "a split that recovers content survives the veto"
}

# Each separator carries the dataset's own quality measures (2026-10-20, for
# provost's auto-multi): coverage and consistency against the dataset's own
# blocks, and their non-blank line count.
_multi_table_kv_input () {
    cat <<'EOF'
Volume   Files   Size   Status
vol-a    12      1.0    OK
vol-b    13      2.0    OK
vol-c    14      3.0    WARN
vol-d    15      4.0    OK
vol-e    16      5.0    OK
vol-f    17      6.0    OK

Elapsed time:   01:00:12
Exit code:      0
Next run:       2026-07-12 01:00
Operator name:  ops team
Pool name:      main pool
Retention:      7 days
EOF
}

test_multi_separator_carries_measures () {
    local tmpfile out sep1 sep2
    tmpfile=$(mktemp)
    _multi_table_kv_input > "$tmpfile"
    out=$(run_extract --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    sep1=$(printf '%s\n' "$out" | grep '^__DATASET__' | sed -n 1p)
    sep2=$(printf '%s\n' "$out" | grep '^__DATASET__' | sed -n 2p)
    assert_eq "7" "$(printf '%s\n' "$sep1" | awk -F'\t' '{ print NF }')" "separator has 7 fields"
    assert_eq "$(printf '100\t100\t7')" "$(printf '%s\n' "$sep1" | cut -f5-7)" "table: coverage, consistency, lines"
    assert_eq "$(printf 'key-value\t80\t100\t100\t6')" "$(printf '%s\n' "$sep2" | cut -f3-7)" "kv block: strategy, conf, measures, lines"
}

test_multi_emit_meta_summary () {
    local tmpfile meta out
    tmpfile=$(mktemp)
    _multi_table_kv_input > "$tmpfile"
    meta=$(run_extract --multi --emit-meta -f tsv --max-strategies 1 "$tmpfile" 2>&1 >/dev/null | grep '^__MULTI_META__')
    assert_eq "$(printf '__MULTI_META__\tsplit\t2\t100\t13')" "$meta" "summary: split, 2 datasets, joint coverage 100 of 13 lines"
    out=$(run_extract --multi --emit-meta -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    assert_not_contains "$out" "__MULTI_META__" "the summary goes to stderr only"
    meta=$(run_extract --multi -f tsv --max-strategies 1 "$tmpfile" 2>&1 >/dev/null)
    assert_not_contains "$meta" "__MULTI_META__" "no summary without --emit-meta"
    rm -f "$tmpfile"
}

# A comment run kept verbatim has nothing to measure: `-` / `-`, its lines.
test_multi_text_group_measures () {
    local tmpfile out sep
    tmpfile=$(mktemp)
    printf '# first note here\n# second note here\n\nname  size\na     1\nb     2\nc     3\n' > "$tmpfile"
    out=$(run_extract --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    sep=$(printf '%s\n' "$out" | grep "$(printf '^__DATASET__\t[0-9]*\ttext\t')" | head -1)
    assert_eq "$(printf -- '-\t-\t2')" "$(printf '%s\n' "$sep" | cut -f5-7)" "text group: unmeasured, 2 lines"
}

run_test "scoring vetoes a losing split"        test_multi_scoring_vetoes_a_losing_split
run_test "scoring keeps a winning split"        test_multi_scoring_keeps_a_winning_split
run_test "count preamble is its own dataset"    test_multi_count_preamble_splits
run_test "aligned header is not a preamble"     test_multi_header_is_not_a_preamble
run_test "digit runs collapse in the lead sig"  test_multi_preamble_over_varied_width_numbers
run_test "rule line splits, and is dropped"     test_multi_rule_line_splits
run_test "an ASCII pipe box stays one table"    test_multi_pipe_box_stays_one_table
run_test "commented kv run parses as kv"        test_multi_commented_kv_is_parsed
run_test "mixed comment run stays verbatim"     test_multi_mixed_comment_run_stays_text
run_test "iostat-like input yields 3 datasets"  test_multi_iostat_three_datasets
run_test "separator line format"                test_multi_separator_format
run_test "record stream stays one dataset"      test_multi_record_stream_stays_one
run_test "--multi/--batch conflict"             test_multi_conflicts_with_batch
run_test "legend folds in as the table header"  test_multi_comment_legend_becomes_header
run_test "under-naming legend is not folded"    test_multi_undernaming_legend_not_folded
run_test "legend may omit the row ordinal"      test_multi_legend_may_omit_row_ordinal
run_test "comment run kept verbatim"            test_multi_comment_run_kept_verbatim

run_test "separator carries per-dataset measures" test_multi_separator_carries_measures
run_test "--emit-meta summary line"            test_multi_emit_meta_summary
run_test "comment run reports no measures"     test_multi_text_group_measures

print_summary
