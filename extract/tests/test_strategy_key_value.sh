#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: key-value (generic aligned "Label:  value" listings)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: key-value"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s key-value "$SAMPLES_DIR/key-value/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "key-value should detect aligned Label: value listings"
}

# Each pair becomes an indexed row group (entry<N>.key / entry<N>.value) so the
# capture tidy melt renders a two-column key/value table — one row per property.
test_extract () {
    local output
    output=$(run_mfe -r -s key-value "$SAMPLES_DIR/key-value/basic.txt")
    assert_contains "$output" "entry1.key Architecture" "first key"
    assert_contains "$output" "entry1.value x86_64" "first value"
    assert_contains "$output" "entry2.key CPU op-mode(s)" "multi-word key preserved"
    assert_contains "$output" "entry8.value AMD EPYC 7763 64-Core Processor" "value with spaces preserved"
    assert_contains "$output" "total_entries 15" "fifteen properties"
}

# Wrapped continuation lines (no colon) fold into the previous value.
test_wrapped_value () {
    local output
    output=$(run_mfe -r -s key-value "$SAMPLES_DIR/key-value/basic.txt")
    assert_contains "$output" "entry12.value fpu vme de pse" "Flags value starts correctly"
    assert_contains "$output" "clflush mmx fxsr sse sse2" "wrapped continuation folded into the value"
    assert_not_contains "$output" "entry13.key pge" "continuation line must not become its own key"
}

# A value that itself contains a colon splits on the FIRST colon only.
test_value_with_colon () {
    local tmp
    tmp=$(mktemp)
    printf 'Spec rstack overflow:      Vulnerable: Safe RET, no microcode\n' > "$tmp"
    printf 'Model name:                AMD EPYC 7763 64-Core Processor\n' >> "$tmp"
    printf 'Byte Order:                Little Endian\n' >> "$tmp"
    printf 'Vendor ID:                 AuthenticAMD\n' >> "$tmp"
    printf 'CPU family:                25\n' >> "$tmp"
    local output
    output=$(run_mfe -r -s key-value "$tmp")
    rm -f "$tmp"
    assert_contains "$output" "entry1.key Spec rstack overflow" "key stops at first colon"
    assert_contains "$output" "entry1.value Vulnerable: Safe RET, no microcode" "value keeps its inner colon"
}

# Must NOT steal compact YAML or JSON (those go to their own strategies).
test_not_yaml () {
    local output
    output=$(run_mfe -d -s key-value "$SAMPLES_DIR/yaml/basic.yaml" 2>&1)
    assert_contains "$output" "not applicable" "key-value should not match compact YAML"
}

test_not_json () {
    local output
    output=$(run_mfe -d -s key-value "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "key-value should not match JSON"
}

run_test "key-value: detection" test_detect
run_test "key-value: extraction" test_extract
run_test "key-value: wrapped continuation values" test_wrapped_value
run_test "key-value: value with inner colon" test_value_with_colon
run_test "key-value: not confused with YAML" test_not_yaml
run_test "key-value: not confused with JSON" test_not_json

print_summary
