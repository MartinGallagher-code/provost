#!/bin/bash
################################################################################
## Strategy Tests: systemd-unit
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: systemd-unit"
echo "========================================"

test_systemd_unit_basic () {
    local output
    output=$(run_mfe -r -s systemd-unit "$SAMPLES_DIR/systemd-unit/basic.txt")
    assert_contains "$output" "Unit.Description" "should extract Unit description"
    assert_contains "$output" "Service.Type simple" "should extract Service type"
    assert_contains "$output" "Install.WantedBy multi-user.target" "should extract Install WantedBy"
}

test_systemd_unit_service_fields () {
    local output
    output=$(run_mfe -r -s systemd-unit "$SAMPLES_DIR/systemd-unit/basic.txt")
    assert_contains "$output" "Service.User appuser" "should extract service user"
    assert_contains "$output" "Service.Restart on-failure" "should extract restart policy"
    assert_contains "$output" "Service.RestartSec 5" "should extract restart seconds"
}

test_systemd_unit_not_for_plain_ini () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '[database]\nhost=localhost\nport=5432\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s systemd-unit "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect plain INI"
}

run_test "systemd-unit: basic extraction" test_systemd_unit_basic
run_test "systemd-unit: service fields" test_systemd_unit_service_fields
run_test "systemd-unit: not detected for plain INI" test_systemd_unit_not_for_plain_ini

print_summary
