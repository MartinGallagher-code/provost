#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Generic Mode Tests
##
## Tests for --generic flag (technique-only strategy filtering) and the
## _techniques.sh shared library functions.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

MFE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "========================================"
echo "Generic Mode Tests"
echo "========================================"

# ---------------------------------------------------------------------------
# Basic extraction: --generic with colon-delimited input
# ---------------------------------------------------------------------------

test_generic_basic_kv_colon () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 8080\nUser: admin\n' > "$tmpfile"
    output=$(run_mfe --generic -f plain "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Host" "--generic should extract Host from colon input"
    assert_contains "$output" "Port" "--generic should extract Port from colon input"
    assert_contains "$output" "User" "--generic should extract User from colon input"
}

# ---------------------------------------------------------------------------
# JSON input is recognized by --generic
# ---------------------------------------------------------------------------

test_generic_json_input () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    output=$(run_mfe --generic -f plain "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "name" "--generic should extract name from JSON"
    assert_contains "$output" "value" "--generic should extract value from JSON"
}

# ---------------------------------------------------------------------------
# YAML input is recognized by --generic
# ---------------------------------------------------------------------------

test_generic_yaml_input () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'host: localhost\nport: 8080\n' > "$tmpfile"
    output=$(run_mfe --generic -f plain "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "host" "--generic should extract host from YAML"
    assert_contains "$output" "port" "--generic should extract port from YAML"
}

# ---------------------------------------------------------------------------
# CSV input is recognized by --generic
# ---------------------------------------------------------------------------

test_generic_csv_input () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Name,Age,City\nAlice,30,Portland\n' > "$tmpfile"
    output=$(run_mfe --generic -f plain "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Name" "--generic should extract Name from CSV"
    assert_contains "$output" "Age" "--generic should extract Age from CSV"
}

# ---------------------------------------------------------------------------
# Format-specific strategies are excluded when --generic is active
# (ab.sh is a benchmark strategy that should not appear in --debug output)
# ---------------------------------------------------------------------------

test_generic_excludes_format_specific () {
    local tmpfile debug_out
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 8080\n' > "$tmpfile"
    debug_out=$(run_mfe --generic --debug "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_not_contains "$debug_out" "Strategy 'ab'" "--generic should exclude ab strategy"
    assert_not_contains "$debug_out" "Strategy 'nginx-conf'" "--generic should exclude nginx-conf strategy"
    assert_not_contains "$debug_out" "Strategy 'sysbench'" "--generic should exclude sysbench strategy"
}

# ---------------------------------------------------------------------------
# Technique strategies ARE present in --debug output under --generic
# ---------------------------------------------------------------------------

test_generic_includes_technique_strategies () {
    local tmpfile debug_out
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 8080\n' > "$tmpfile"
    debug_out=$(run_mfe --generic --debug "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$debug_out" "colons" "--generic should include colons strategy in debug"
}

# ---------------------------------------------------------------------------
# --generic conflicts with --strategy
# ---------------------------------------------------------------------------

test_generic_conflict_strategy () {
    local tmpfile output exit_code
    tmpfile=$(mktemp)
    printf 'Host: localhost\n' > "$tmpfile"
    exit_code=0
    if output=$(run_mfe --generic --strategy colons "$tmpfile" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    rm -f "$tmpfile"
    assert_exit_nonzero "$exit_code" "--generic + --strategy should exit non-zero"
    assert_contains "$output" "cannot be used together" "should report conflict message"
}

# ---------------------------------------------------------------------------
# --generic conflicts with --chain
# ---------------------------------------------------------------------------

test_generic_conflict_chain () {
    local tmpfile output exit_code
    tmpfile=$(mktemp)
    printf 'Host: localhost\n' > "$tmpfile"
    exit_code=0
    if output=$(run_mfe --generic --chain 'colons|json' "$tmpfile" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    rm -f "$tmpfile"
    assert_exit_nonzero "$exit_code" "--generic + --chain should exit non-zero"
    assert_contains "$output" "cannot be used together" "should report conflict message"
}

# ---------------------------------------------------------------------------
# --generic works with -f (format flag)
# ---------------------------------------------------------------------------

test_generic_with_format_flag () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\n' > "$tmpfile"
    output=$(run_mfe --generic -f csv "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Name" "--generic -f csv should produce CSV with Name"
    assert_contains "$output" "Age" "--generic -f csv should produce CSV with Age"
}

# ---------------------------------------------------------------------------
# --generic works with --aggregate
# ---------------------------------------------------------------------------

test_generic_with_aggregate () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\nScore: 30\n' > "$tmpfile"
    output=$(run_mfe --generic --aggregate -r "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Score_count" "--generic --aggregate should produce count"
    assert_contains "$output" "Score_sum" "--generic --aggregate should produce sum"
}

# ---------------------------------------------------------------------------
# --generic works with --rename
# ---------------------------------------------------------------------------

test_generic_with_rename () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Host: localhost\n' > "$tmpfile"
    output=$(run_mfe --generic --rename 'Host=hostname' -f plain "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "hostname" "--generic --rename should use new name"
    assert_not_contains "$output" "Host localhost" "--generic --rename should not use old name"
}

# ---------------------------------------------------------------------------
# --generic works with --sort
# ---------------------------------------------------------------------------

test_generic_with_sort () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Zebra: last\nAlpha: first\n' > "$tmpfile"
    output=$(run_mfe --generic --sort -r "$tmpfile")
    rm -f "$tmpfile"
    local alpha_pos zebra_pos
    alpha_pos=$(echo "$output" | grep -n "Alpha" | head -1 | cut -d: -f1)
    zebra_pos=$(echo "$output" | grep -n "Zebra" | head -1 | cut -d: -f1)
    if [[ -n "$alpha_pos" && -n "$zebra_pos" && "$alpha_pos" -lt "$zebra_pos" ]]; then
        assert_eq "ok" "ok" "--generic --sort: Alpha before Zebra"
    else
        assert_eq "Alpha before Zebra" "wrong order" "--generic --sort should sort alphabetically"
    fi
}

# ---------------------------------------------------------------------------
# --generic with --min-confidence 85 — only the grammar tier (json/csv/yaml…, 85) runs
# ---------------------------------------------------------------------------

test_generic_with_min_confidence () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf '{"x": 1}\n' > "$tmpfile"
    # At confidence 85, only json (c85, grammar tier) should match; colons
    # (general-structure tier, 55..60) should not
    output=$(run_mfe --generic --min-confidence 85 -f plain "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "x" "--generic --min-confidence 85 should extract JSON fields"
}

# ---------------------------------------------------------------------------
# --generic with --count
# ---------------------------------------------------------------------------

test_generic_with_count () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\nCity: Portland\n' > "$tmpfile"
    output=$(run_mfe --generic --count "$tmpfile")
    rm -f "$tmpfile"
    # Should output a number >= 1 (exact count may vary due to multi-strategy)
    assert_match "$output" "^[0-9]+$" "--generic --count should output a number"
}

# ---------------------------------------------------------------------------
# --generic with empty / no-match input exits 0 (no crash)
# ---------------------------------------------------------------------------

test_generic_empty_input_no_crash () {
    local tmpfile exit_code
    tmpfile=$(mktemp)
    printf 'no extractable fields here just plain words\n' > "$tmpfile"
    run_mfe --generic "$tmpfile" >/dev/null 2>&1
    exit_code=$?
    rm -f "$tmpfile"
    assert_exit_zero "$exit_code" "--generic with no-match input should exit 0"
}

# ---------------------------------------------------------------------------
# --list-strategies shows [G] marker for generic (delimited/structured) strategies
# ---------------------------------------------------------------------------

test_generic_list_strategies_shows_G_marker () {
    local output
    output=$(run_mfe --list-strategies)
    assert_contains "$output" "[G]" "--list-strategies should show [G] marker for generic strategies"
}

# ---------------------------------------------------------------------------
# Unit test: _tech_kv_colon basic extraction
# ---------------------------------------------------------------------------

test_technique_kv_colon_basic () {
    local output
    # Source the library directly, then call the function
    output=$(bash -c "
        source \"$MFE_DIR/lib/_helpers.sh\"
        source \"$MFE_DIR/lib/_techniques.sh\"
        _tech_kv_colon 'Host: localhost
Port: 8080' ''
    ")
    assert_contains "$output" "Host localhost" "_tech_kv_colon should extract Host"
    assert_contains "$output" "Port 8080" "_tech_kv_colon should extract Port"
}

# ---------------------------------------------------------------------------
# Unit test: _tech_kv_colon skips URL values
# ---------------------------------------------------------------------------

test_technique_kv_colon_url_skip () {
    local output
    output=$(bash -c "
        source \"$MFE_DIR/lib/_helpers.sh\"
        source \"$MFE_DIR/lib/_techniques.sh\"
        _tech_kv_colon 'Link: //example.com/path
Host: localhost' ''
    ")
    assert_not_contains "$output" "Link" "_tech_kv_colon should skip URL values"
    assert_contains "$output" "Host" "_tech_kv_colon should still extract other fields"
}

# ---------------------------------------------------------------------------
# Unit test: _tech_kv_equals skips comparison operators
# ---------------------------------------------------------------------------

test_technique_kv_equals_skip_comparisons () {
    local output
    output=$(bash -c "
        source \"$MFE_DIR/lib/_helpers.sh\"
        source \"$MFE_DIR/lib/_techniques.sh\"
        _tech_kv_equals 'x == y
Name=Alice
a += b' ''
    ")
    assert_not_contains "$output" "x " "_tech_kv_equals should skip == comparisons"
    assert_not_contains "$output" "a " "_tech_kv_equals should skip += comparisons"
    assert_contains "$output" "Name" "_tech_kv_equals should extract Name=Alice"
}

# ---------------------------------------------------------------------------
# Unit test: _tech_validate_key
# ---------------------------------------------------------------------------

test_technique_validate_key () {
    bash -c "
        source \"$MFE_DIR/lib/_helpers.sh\"
        source \"$MFE_DIR/lib/_techniques.sh\"
        _tech_validate_key ''
        [[ \$_TECH_KEY_VALID -eq 0 ]] || exit 1   # empty should be invalid
        _tech_validate_key 'NormalKey'
        [[ \$_TECH_KEY_VALID -eq 1 ]] || exit 1   # normal key should be valid
        long=\$(printf '%0.s_' {1..51})
        _tech_validate_key \"\$long\"
        [[ \$_TECH_KEY_VALID -eq 0 ]] || exit 1   # 51-char key should be invalid
        _tech_validate_key '9digitstart'
        [[ \$_TECH_KEY_VALID -eq 0 ]] || exit 1   # digit-start should be invalid
    "
    assert_exit_zero "$?" "_tech_validate_key should correctly validate keys"
}

# ---------------------------------------------------------------------------
# Unit test: _tech_split_blocks
# ---------------------------------------------------------------------------

test_technique_split_blocks () {
    local tmpscript result
    tmpscript=$(mktemp)
    cat > "$tmpscript" <<SCRIPT
source "$MFE_DIR/lib/_helpers.sh"
source "$MFE_DIR/lib/_techniques.sh"
input=\$'block1_line1\nblock1_line2\n\nblock2_line1\nblock2_line2'
_tech_split_blocks "\$input"
count=0
_remaining="\$_TECH_BLOCKS"
while [[ -n "\$_remaining" ]]; do
    _block="\${_remaining%%\$'\\x01'*}"
    [[ "\$_remaining" == *\$'\\x01'* ]] && _remaining="\${_remaining#*\$'\\x01'}" || _remaining=""
    count=\$((count + 1))
done
[[ \$count -eq 2 ]] || exit 1
SCRIPT
    bash "$tmpscript"
    result=$?
    rm -f "$tmpscript"
    assert_exit_zero "$result" "_tech_split_blocks should split into 2 blocks"
}

# ---------------------------------------------------------------------------
# Register all tests
# ---------------------------------------------------------------------------

run_test "generic: basic kv-colon extraction"                    test_generic_basic_kv_colon
run_test "generic: JSON input recognized"                        test_generic_json_input
run_test "generic: YAML input recognized"                        test_generic_yaml_input
run_test "generic: CSV input recognized"                         test_generic_csv_input
run_test "generic: format-specific strategies excluded"          test_generic_excludes_format_specific
run_test "generic: technique strategies present in debug"         test_generic_includes_technique_strategies
run_test "generic: conflicts with --strategy"                    test_generic_conflict_strategy
run_test "generic: conflicts with --chain"                       test_generic_conflict_chain
run_test "generic: works with -f (format flag)"                  test_generic_with_format_flag
run_test "generic: works with --aggregate"                       test_generic_with_aggregate
run_test "generic: works with --rename"                          test_generic_with_rename
run_test "generic: works with --sort"                            test_generic_with_sort
run_test "generic: works with --min-confidence"                  test_generic_with_min_confidence
run_test "generic: works with --count"                           test_generic_with_count
run_test "generic: empty input exits 0"                          test_generic_empty_input_no_crash
run_test "generic: --list-strategies shows [G] marker"           test_generic_list_strategies_shows_G_marker
run_test "technique: _tech_kv_colon basic"                       test_technique_kv_colon_basic
run_test "technique: _tech_kv_colon URL skip"                    test_technique_kv_colon_url_skip
run_test "technique: _tech_kv_equals skip comparisons"           test_technique_kv_equals_skip_comparisons
run_test "technique: _tech_validate_key"                         test_technique_validate_key
run_test "technique: _tech_split_blocks"                         test_technique_split_blocks

print_summary
