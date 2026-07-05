#!/bin/bash
################################################################################
## Strategy Tests: ps-aux
################################################################################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
echo ""
echo "Strategy Tests: ps-aux"

test_ps_aux_basic () {
    local output
    output=$(run_mfe -r -s ps-aux "$SAMPLES_DIR/ps-aux/basic.txt")
    assert_contains "$output" "entry1.user root" "first user"
    assert_contains "$output" "entry1.pid 1" "first pid"
    assert_contains "$output" "entry1.command /sbin/init" "first command"
    assert_contains "$output" "entry2.user www-data" "second user"
    assert_contains "$output" "entry2.command nginx:_worker_process" "command joins trailing spaces"
    assert_contains "$output" "total_entries 3" "counts all processes, skips header"
}
test_ps_aux_detects () {
    local output
    output=$(run_mfe -d -s ps-aux "$SAMPLES_DIR/ps-aux/basic.txt" 2>&1)
    assert_not_contains "$output" "not applicable" "ps-aux must match ps aux output"
}
run_test "ps-aux: basic extraction" test_ps_aux_basic
run_test "ps-aux: detected" test_ps_aux_detects
print_summary
