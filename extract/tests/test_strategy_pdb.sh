#!/bin/bash
################################################################################
## Strategy Tests: pdb
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: pdb"
echo "========================================"

test_pdb_detect () {
    local output
    output=$(run_mfe -d -s pdb "$SAMPLES_DIR/pdb/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect PDB output"
}

test_pdb_values () {
    local output
    output=$(run_mfe -r -s pdb "$SAMPLES_DIR/pdb/basic.txt")
    assert_contains "$output" "pdb_id 8ABC" "should extract PDB ID"
    assert_contains "$output" "classification OXIDOREDUCTASE" "should extract classification"
    assert_contains "$output" "title CRYSTAL STRUCTURE OF HUMAN CARBONIC ANHYDRASE II" "should extract title"
    assert_contains "$output" "num_atoms 8" "should count ATOM records"
    assert_contains "$output" "num_hetatm 3" "should count HETATM records"
}

test_pdb_structure () {
    local output
    output=$(run_mfe -r -s pdb "$SAMPLES_DIR/pdb/basic.txt")
    assert_contains "$output" "resolution 1.54" "should extract resolution"
    assert_contains "$output" "r_factor 0.1820" "should extract R factor"
    assert_contains "$output" "space_group P 21 21 21" "should extract space group"
    assert_contains "$output" "compound" "should extract compound"
}

test_pdb_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s pdb "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "pdb: detection" test_pdb_detect
run_test "pdb: extracted values" test_pdb_values
run_test "pdb: structure details" test_pdb_structure
run_test "pdb: not detected for JSON" test_pdb_not_json

print_summary
