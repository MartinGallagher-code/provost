#!/bin/bash
################################################################################
## Strategy Tests: nfsstat
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: nfsstat"
echo "========================================"

test_nfsstat_detect () {
    local output
    output=$(run_mfe -d -s nfsstat "$SAMPLES_DIR/nfsstat/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect nfsstat output"
}

test_nfsstat_values () {
    local output
    output=$(run_mfe -r -s nfsstat "$SAMPLES_DIR/nfsstat/basic.txt")
    assert_contains "$output" "server.rpc_calls 1845623" "should extract server rpc calls"
    assert_contains "$output" "server.rpc_badcalls 127" "should extract server rpc badcalls"
    assert_contains "$output" "server.nfs_version v3" "should extract server nfs version"
    assert_contains "$output" "client.rpc_calls 923456" "should extract client rpc calls"
    assert_contains "$output" "client.rpc_badcalls 42" "should extract client rpc badcalls"
}

test_nfsstat_nfs_ops () {
    local output
    output=$(run_mfe -r -s nfsstat "$SAMPLES_DIR/nfsstat/basic.txt")
    assert_contains "$output" "server.v3.null_count 0" "should extract null op count"
    assert_contains "$output" "server.v3.getattr_count 564123" "should extract getattr count"
    assert_contains "$output" "server.v3.getattr_percent 30" "should extract getattr percent"
    assert_contains "$output" "server.v3.read_count 445678" "should extract read count"
    assert_contains "$output" "server.v3.write_count 234567" "should extract write count"
}

test_nfsstat_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s nfsstat "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "nfsstat: detection" test_nfsstat_detect
run_test "nfsstat: specific values" test_nfsstat_values
run_test "nfsstat: nfs operation stats" test_nfsstat_nfs_ops
run_test "nfsstat: not detected for JSON" test_nfsstat_not_json

print_summary
