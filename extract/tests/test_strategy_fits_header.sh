#!/bin/bash
################################################################################
## Strategy Tests: fits-header
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: fits-header"
echo "========================================"

test_fits_header_detect () {
    local output
    output=$(run_mfe -d -s fits-header "$SAMPLES_DIR/fits-header/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect FITS header output"
}

test_fits_header_values () {
    local output
    output=$(run_mfe -r -s fits-header "$SAMPLES_DIR/fits-header/basic.txt")
    assert_contains "$output" "simple T" "should extract SIMPLE"
    assert_contains "$output" "bitpix -32" "should extract BITPIX"
    assert_contains "$output" "naxis 2" "should extract NAXIS"
    assert_contains "$output" "naxis1 2048" "should extract NAXIS1"
    assert_contains "$output" "naxis2 2048" "should extract NAXIS2"
    assert_contains "$output" "extend T" "should extract EXTEND"
}

test_fits_header_observation () {
    local output
    output=$(run_mfe -r -s fits-header "$SAMPLES_DIR/fits-header/basic.txt")
    assert_contains "$output" "object NGC 1234" "should extract OBJECT"
    assert_contains "$output" "telescope Keck-I" "should extract TELESCOP"
    assert_contains "$output" "instrument LRIS" "should extract INSTRUME"
    assert_contains "$output" "date_obs 2024-03-15T08:23:45" "should extract DATE-OBS"
    assert_contains "$output" "exptime 1200.0" "should extract EXPTIME"
    assert_contains "$output" "filter V-band" "should extract FILTER"
}

test_fits_header_wcs () {
    local output
    output=$(run_mfe -r -s fits-header "$SAMPLES_DIR/fits-header/basic.txt")
    assert_contains "$output" "ctype1 RA---TAN" "should extract CTYPE1"
    assert_contains "$output" "ctype2 DEC--TAN" "should extract CTYPE2"
    assert_contains "$output" "equinox 2000.0" "should extract EQUINOX"
    assert_contains "$output" "crval1 185.7289583" "should extract CRVAL1"
}

test_fits_header_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s fits-header "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "fits-header: detection" test_fits_header_detect
run_test "fits-header: basic values" test_fits_header_values
run_test "fits-header: observation metadata" test_fits_header_observation
run_test "fits-header: WCS coordinates" test_fits_header_wcs
run_test "fits-header: not detected for JSON" test_fits_header_not_json

print_summary
