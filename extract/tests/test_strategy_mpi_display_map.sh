#!/bin/bash
################################################################################
## Strategy Tests: mpi-display-map
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: mpi-display-map"
echo "========================================"

SAMPLE_DISPLAY_MAP=$(cat <<'EOFSAMPLE'
 Display the map for job 12345

 Num nodes: 2

 Data for node: compute01   Num procs: 2
    Rank 0: slot=0, binding=0001
    Rank 1: slot=1, binding=0010

 Data for node: compute02   Num procs: 2
    Rank 2: slot=0, binding=0001
    Rank 3: slot=1, binding=0010
EOFSAMPLE
)

test_mpi_display_map_detect () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_DISPLAY_MAP" > "$tmpfile"
    local output
    output=$(run_mfe -d -s mpi-display-map "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "applicable" "mpi-display-map should detect display-map output"
}

test_mpi_display_map_extract () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_DISPLAY_MAP" > "$tmpfile"
    local output
    output=$(run_mfe -r -s mpi-display-map "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "num_nodes 2" "should extract num_nodes"
    assert_contains "$output" "total_procs 4" "should extract total_procs"
    assert_contains "$output" "node.compute01.name compute01" "should extract node name"
    assert_contains "$output" "node.compute01.rank.0.slot 0" "should extract rank slot"
    assert_contains "$output" "node.compute02.rank.3.binding 0010" "should extract rank binding"
}

test_mpi_display_map_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s mpi-display-map "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "mpi-display-map should not apply to JSON"
}

run_test "mpi-display-map: detection" test_mpi_display_map_detect
run_test "mpi-display-map: basic extraction" test_mpi_display_map_extract
run_test "mpi-display-map: not detected for JSON" test_mpi_display_map_not_json

print_summary
