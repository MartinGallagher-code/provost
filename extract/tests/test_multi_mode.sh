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
# is a boundary too: /proc/slabinfo's `# name <active_objs> …` is neither part
# of the table nor a table of its own.
_multi_comment_input () {
    cat <<'EOF'
# name            <active_objs> <num_objs> <objsize>
kmalloc-8192          128    128   8192
kmalloc-1024         2048   2048   1024
dentry              48210  48312    192
EOF
}

test_multi_comment_run_splits_block () {
    local tmpfile out n
    tmpfile=$(mktemp)
    _multi_comment_input > "$tmpfile"
    out=$(run_mfe --generic --multi -f tsv --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    n=$(printf '%s\n' "$out" | grep -c '__DATASET__')
    assert_eq "2" "$n" "comment legend splits from the table it sits above"
    assert_contains "$out" "$(printf '__DATASET__\t1\ttext')" "the comment run is a text dataset"
    assert_contains "$out" "kmalloc-8192" "the table itself still parses"
}

test_multi_comment_run_kept_verbatim () {
    local tmpfile out
    tmpfile=$(mktemp)
    _multi_comment_input > "$tmpfile"
    out=$(run_mfe --generic --multi -f plain --max-strategies 1 "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    # Kept as-is (one lineN field), not forced through a parser that would
    # invent columns out of the legend's words.
    assert_contains "$out" "line1 # name" "comment line kept verbatim under a lineN field"
}

run_test "iostat-like input yields 3 datasets"  test_multi_iostat_three_datasets
run_test "separator line format"                test_multi_separator_format
run_test "record stream stays one dataset"      test_multi_record_stream_stays_one
run_test "--multi/--batch conflict"             test_multi_conflicts_with_batch
run_test "comment run splits its block"         test_multi_comment_run_splits_block
run_test "comment run kept verbatim"            test_multi_comment_run_kept_verbatim

print_summary
