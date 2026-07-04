#!/bin/bash
################################################################################
## Strategy Tests: block-records
## Consolidates tests from: blank-line-records, repeated-blocks
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: block-records"
echo "========================================"

# --- blank-line-records cases ---

test_br_basic () {
    local output
    output=$(run_mfe -r -s block-records "$SAMPLES_DIR/blank-line-records/basic.txt")
    assert_contains "$output" "record1.Name Server-A" "should extract record1 Name"
    assert_contains "$output" "record1.IP 10.0.0.1" "should extract record1 IP"
    assert_contains "$output" "record1.Status Active" "should extract record1 Status"
    assert_contains "$output" "record2.Name Server-B" "should extract record2 Name"
    assert_contains "$output" "record2.IP 10.0.0.2" "should extract record2 IP"
    assert_contains "$output" "record2.Status Inactive" "should extract record2 Status"
    assert_contains "$output" "record3.Name Server-C" "should extract record3 Name"
}

test_br_multiple_records () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: alpha\nPort: 8080\n\nHost: beta\nPort: 9090\n\nHost: gamma\nPort: 7070\n\nHost: delta\nPort: 6060\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s block-records "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "record1.Host alpha" "should extract record1 Host"
    assert_contains "$output" "record2.Host beta" "should extract record2 Host"
    assert_contains "$output" "record3.Host gamma" "should extract record3 Host"
    assert_contains "$output" "record4.Host delta" "should extract record4 Host"
    assert_contains "$output" "record4.Port 6060" "should extract record4 Port"
}

test_br_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s block-records "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "block-records should not apply to JSON"
}

# --- repeated-blocks cases (use record prefix now) ---

test_br_repeated_blocks_sample () {
    local output
    output=$(run_mfe -r -s block-records "$SAMPLES_DIR/repeated-blocks/basic.txt")
    assert_contains "$output" "record1.Interface eth0" "should extract record1 Interface"
    assert_contains "$output" "record1.Status up" "should extract record1 Status"
    assert_contains "$output" "record1.IP 10.0.0.1" "should extract record1 IP"
    assert_contains "$output" "record1.MTU 1500" "should extract record1 MTU"
    assert_contains "$output" "record2.Interface eth1" "should extract record2 Interface"
    assert_contains "$output" "record2.Status down" "should extract record2 Status"
}

test_br_repeated_field_names () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Name: Alice\nRole: Admin\n\nName: Bob\nRole: User\n\nName: Charlie\nRole: Viewer\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s block-records "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "record1.Name Alice" "should extract record1 Name"
    assert_contains "$output" "record2.Name Bob" "should extract record2 Name"
    assert_contains "$output" "record3.Name Charlie" "should extract record3 Name"
    assert_contains "$output" "record3.Role Viewer" "should extract record3 Role"
}

# --- mixed colon and equals in same blocks (2+ blank lines, so detected via condition a) ---

test_br_mixed_delimiters () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Host: server1\nPort=8080\n\nHost: server2\nPort=9090\n\nHost: server3\nPort=7070\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s block-records "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "record1.Host server1" "should extract colon-delimited host"
    assert_contains "$output" "record1.Port 8080" "should extract equals-delimited port"
    assert_contains "$output" "record2.Host server2" "should extract second host"
    assert_contains "$output" "record3.Host server3" "should extract third host"
}

run_test "block-records: basic extraction (blank-line-records sample)" test_br_basic
run_test "block-records: multiple records" test_br_multiple_records
run_test "block-records: not detected for JSON" test_br_not_detected_for_json
run_test "block-records: repeated-blocks sample" test_br_repeated_blocks_sample
run_test "block-records: repeated field names" test_br_repeated_field_names
run_test "block-records: mixed colon and equals in blocks" test_br_mixed_delimiters

print_summary
