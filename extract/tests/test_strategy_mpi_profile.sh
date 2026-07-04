#!/bin/bash
################################################################################
## Strategy Tests: mpi-profile
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: mpi-profile"
echo "========================================"

SAMPLE_MPIP=$(cat <<'EOFSAMPLE'
@ mpiP
@ Command : ./myapp
@ Version                  : 3.5
@ MPI Version              : 3.1
@ Comm_size                : 16
@ App Time (s)             : 120.5
@ MPI Time (s)             : 45.2
@ MPI %                    : 37.5

@--- Callsite Time statistics (all, milliseconds): ---
  Name       Site  Time    App%   MPI%
  MPI_Bcast  1     12000   9.9    26.5
  MPI_Allreduce 2  8500    7.1    18.8
  MPI_Send   3     5000    4.1    11.1
---@
EOFSAMPLE
)

test_mpi_profile_detect () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_MPIP" > "$tmpfile"
    local output
    output=$(run_mfe -d -s mpi-profile "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "applicable" "mpi-profile should detect mpiP output"
}

test_mpi_profile_extract () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_MPIP" > "$tmpfile"
    local output
    output=$(run_mfe -r -s mpi-profile "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "comm_size 16" "should extract comm_size"
    assert_contains "$output" "total_time 120.5" "should extract total_time"
    assert_contains "$output" "mpi_time 45.2" "should extract mpi_time"
    assert_contains "$output" "mpi_percent 37.5" "should extract mpi_percent"
}

test_mpi_profile_callsites () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_MPIP" > "$tmpfile"
    local output
    output=$(run_mfe -r -s mpi-profile "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "callsite.1.name MPI_Bcast" "should extract first callsite name"
    assert_contains "$output" "callsite.1.time 12000" "should extract first callsite time"
}

test_mpi_profile_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s mpi-profile "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "mpi-profile should not apply to JSON"
}

run_test "mpi-profile: detection" test_mpi_profile_detect
run_test "mpi-profile: basic extraction" test_mpi_profile_extract
run_test "mpi-profile: callsite parsing" test_mpi_profile_callsites
run_test "mpi-profile: not detected for JSON" test_mpi_profile_not_json

print_summary
