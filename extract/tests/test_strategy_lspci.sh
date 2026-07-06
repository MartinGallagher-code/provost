#!/bin/bash
################################################################################
## Strategy Tests: lspci
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lspci"
echo "========================================"

test_lspci_detect () {
    local output
    output=$(run_mfe -d -s lspci "$SAMPLES_DIR/lspci/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect lspci output"
}

test_lspci_values () {
    local output
    output=$(run_mfe -r -s lspci "$SAMPLES_DIR/lspci/basic.txt")
    assert_contains "$output" "entry1.slot 00:02.0" "should extract VGA slot"
    assert_contains "$output" "entry1.class VGA compatible controller" "should extract VGA class"
    assert_contains "$output" "entry1.driver i915" "should extract VGA driver"
    assert_contains "$output" "entry2.slot 03:00.0" "should extract Ethernet slot"
    assert_contains "$output" "entry2.class Ethernet controller" "should extract Ethernet class"
    assert_contains "$output" "entry2.driver igb" "should extract Ethernet driver"
    assert_contains "$output" "entry3.driver nvme" "should extract NVMe driver"
    assert_contains "$output" "entry4.class 3D controller" "should extract GPU class"
    assert_contains "$output" "entry4.driver nvidia" "should extract GPU driver"
    assert_contains "$output" "total_entries 4" "should count 4 devices"
}

test_lspci_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s lspci "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "lspci: detection" test_lspci_detect
run_test "lspci: specific values" test_lspci_values
run_test "lspci: not detected for JSON" test_lspci_not_json

print_summary
