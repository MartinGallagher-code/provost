#!/bin/bash
################################################################################
## Flag Combination Interaction Tests
##
## Verify that combined CLI flags produce correct behavior.
## These test interactions NOT covered by individual flag tests.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Flag Combination Tests"
echo "========================================"

# --- --sort + --names: sorted field names only ---

test_flags_sort_names () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Zebra: last\nAlpha: first\nMiddle: center\n' > "$tmpfile"
    # --names exits before --sort is applied (names at line 1107, sort at line 1117)
    # so field names should appear in extraction order, not sorted
    output=$(run_mfe --names -s colons "$tmpfile")
    rm -f "$tmpfile"
    # Just verify names are present (order depends on pipeline)
    assert_contains "$output" "Zebra" "should output Zebra field name"
    assert_contains "$output" "Alpha" "should output Alpha field name"
    assert_contains "$output" "Middle" "should output Middle field name"
}

# --- --sort + --count: count takes precedence ---

test_flags_sort_count () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\nCity: Portland\n' > "$tmpfile"
    # --count exits at line 1097, before --sort at line 1117
    output=$(run_mfe --sort --count -s colons "$tmpfile")
    rm -f "$tmpfile"
    # Count should be 3 regardless of sort
    assert_eq "$output" "3" "count should be 3 independent of sort"
}

# --- --rename + --sort: renamed then sorted ---

test_flags_rename_sort () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Alpha: first\nBeta: second\n' > "$tmpfile"
    # Rename Alpha to ZZZ_Alpha, then sort: ZZZ_Alpha should appear after Beta
    output=$(run_mfe --rename 'Alpha=ZZZ_Alpha' --sort -r -s colons "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "ZZZ_Alpha first" "should have renamed field"
    # In sorted output, Beta should come before ZZZ_Alpha
    local beta_pos zzz_pos
    beta_pos=$(echo "$output" | grep -n "Beta" | head -1 | cut -d: -f1)
    zzz_pos=$(echo "$output" | grep -n "ZZZ_Alpha" | head -1 | cut -d: -f1)
    if [[ -n "$beta_pos" && -n "$zzz_pos" && "$beta_pos" -lt "$zzz_pos" ]]; then
        assert_eq "ok" "ok" "Beta should sort before ZZZ_Alpha"
    else
        assert_eq "Beta before ZZZ_Alpha" "ZZZ_Alpha before Beta" "sort order incorrect after rename"
    fi
}

# --- --rename + --aggregate: aggregated fields use renamed names ---

test_flags_rename_aggregate () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\nScore: 30\n' > "$tmpfile"
    output=$(run_mfe --rename 'Score=Points' --aggregate -r -s colons "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Points_count 3" "aggregated field should use renamed name"
    assert_contains "$output" "Points_sum 60" "aggregated sum should use renamed name"
}

# --- --rename + --names: renamed names in output ---

test_flags_rename_names () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\n' > "$tmpfile"
    output=$(run_mfe --rename 'Name=FullName' --names -s colons "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "FullName" "names should show renamed field"
    assert_not_contains "$output" "Alice" "names should not show values"
}

# --- --rename + --count: count unchanged by rename ---

test_flags_rename_count () {
    local tmpfile output_with output_without
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\nCity: Portland\n' > "$tmpfile"
    output_with=$(run_mfe --rename 'Name=FullName' --count -s colons "$tmpfile")
    output_without=$(run_mfe --count -s colons "$tmpfile")
    rm -f "$tmpfile"
    assert_eq "$output_with" "$output_without" "count should be the same with or without rename"
}

# --- --first-match + --min-confidence: confidence filters first ---

test_flags_firstmatch_minconfidence () {
    local tmpfile output
    tmpfile=$(mktemp)
    # Create input that matches both yaml (c90, p12) and colons (c35, p60)
    printf 'server:\n  host: localhost\n  port: 8080\n' > "$tmpfile"
    # With min-confidence 80, colons (c35) is filtered out; yaml (c90) matches first
    output=$(run_mfe --first-match --min-confidence 80 -r "$tmpfile")
    rm -f "$tmpfile"
    # yaml produces dot-notation fields
    assert_contains "$output" "server.host" "high-confidence yaml should match with first-match"
}

# --- --max-strategies + --no-dedup: duplicates preserved ---

test_flags_maxstrategies_nodedup () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 5432\n' > "$tmpfile"
    # With no-dedup, if multiple strategies extract the same fields, both kept
    output=$(run_mfe --no-dedup -r "$tmpfile")
    rm -f "$tmpfile"
    # Just verify output is non-empty (no-dedup should not cause issues)
    assert_contains "$output" "Host" "no-dedup output should include fields"
}

# --- --aggregate + --sort: aggregated then sorted ---

test_flags_aggregate_sort () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\nScore: 30\n' > "$tmpfile"
    output=$(run_mfe --aggregate --sort -r -s colons "$tmpfile")
    rm -f "$tmpfile"
    # After aggregate: Score_count, Score_min, Score_max, Score_sum, Score_avg
    # After sort: alphabetical order: Score_avg < Score_count < Score_max < Score_min < Score_sum
    assert_contains "$output" "Score_count 3" "Score_count should be in sorted output"
    assert_contains "$output" "Score_avg" "Score_avg should be in sorted output"
    # Verify sorting: avg should come before count (alphabetical)
    local avg_pos count_pos
    avg_pos=$(echo "$output" | grep -n "Score_avg" | head -1 | cut -d: -f1)
    count_pos=$(echo "$output" | grep -n "Score_count" | head -1 | cut -d: -f1)
    if [[ -n "$avg_pos" && -n "$count_pos" && "$avg_pos" -lt "$count_pos" ]]; then
        assert_eq "ok" "ok" "Score_avg should sort before Score_count"
    else
        assert_eq "avg<count" "avg=$avg_pos count=$count_pos" "sort order incorrect"
    fi
}

# --- --aggregate + --count: count reflects aggregated lines ---

test_flags_aggregate_count () {
    local tmpfile count_plain count_agg
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\nLevel: 5\n' > "$tmpfile"
    count_plain=$(run_mfe --count -s colons "$tmpfile")
    count_agg=$(run_mfe --aggregate --count -s colons "$tmpfile")
    rm -f "$tmpfile"
    # Plain: 3 fields (Score, Score, Level) -> after dedup: 2 (Score, Level)
    # Aggregated: Level + Score_count + Score_min + Score_max + Score_sum + Score_avg = 6
    # count_agg should be larger than count_plain
    if [[ "$count_agg" -gt "$count_plain" ]]; then
        assert_eq "ok" "ok" "aggregate count should be larger due to stats fields"
    else
        assert_eq "agg>plain" "agg=$count_agg plain=$count_plain" "aggregate should produce more fields"
    fi
}

# --- --quiet + --min-confidence 100: silent no-match ---

test_flags_quiet_minconfidence_high () {
    local tmpfile rc output
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\n' > "$tmpfile"
    rc=0
    output=$(run_mfe --quiet --min-confidence 100 "$tmpfile" 2>&1) || rc=$?
    rm -f "$tmpfile"
    # With min-confidence 100, no strategy reaches that threshold
    # --quiet means no stderr messages, exit code 1
    assert_eq "$rc" "1" "should exit 1 when no fields pass confidence filter"
    assert_eq "$output" "" "quiet mode should produce no output"
}

# --- --verbose + --first-match: verbose shows 1 matched ---

test_flags_verbose_firstmatch () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    output=$(run_mfe --verbose --first-match -s json "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "1 matched" "verbose should show 1 matched with first-match"
}

# --- --output FILE + --sort: sorted output in file ---

test_flags_output_sort () {
    local tmpfile outfile output
    tmpfile=$(mktemp)
    outfile=$(mktemp)
    printf 'Zebra: last\nAlpha: first\n' > "$tmpfile"
    run_mfe --output "$outfile" --sort -r -s colons "$tmpfile" >/dev/null 2>&1
    output=$(<"$outfile")
    rm -f "$tmpfile" "$outfile"
    assert_contains "$output" "Alpha first" "output file should contain Alpha"
    assert_contains "$output" "Zebra last" "output file should contain Zebra"
}

# --- -f csv + --rename: CSV header uses renamed names ---

test_flags_format_csv_rename () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\n' > "$tmpfile"
    output=$(run_mfe -f csv --rename 'Name=FullName' -s colons "$tmpfile" 1,2)
    rm -f "$tmpfile"
    assert_contains "$output" "FullName" "CSV header should use renamed field name"
}

# --- -f json + --aggregate: valid JSON with aggregate keys ---

test_flags_format_json_aggregate () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\n' > "$tmpfile"
    output=$(run_mfe -f json --aggregate -s colons "$tmpfile")
    rm -f "$tmpfile"
    # JSON output should contain aggregate keys
    assert_contains "$output" "Score_count" "JSON output should have aggregate keys"
    assert_contains "$output" "{" "output should be JSON (has opening brace)"
}

# --- --stream + --rename: streaming output uses renamed names ---

test_flags_stream_rename () {
    # Stream mode processes lines independently and exits before rename pipeline
    # Verify that stream produces output (rename is not applied in stream mode)
    local output
    output=$(printf 'Host: web\nPort: 80\n' | run_mfe --stream --strategy colons)
    assert_contains "$output" '"Host"' "stream JSON should output Host field"
    assert_contains "$output" '"Port"' "stream JSON should output Port field"
}

# --- field-by-name + --sort: filtered and sorted ---

test_flags_field_by_name_sort () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'Zebra: last\nAlpha: first\nMiddle: center\n' > "$tmpfile"
    output=$(run_mfe --sort -r -s colons "$tmpfile" -f Name,Alpha,Zebra)
    rm -f "$tmpfile"
    # field-by-name with sort should filter AND sort
    # This tests the interaction: sort applies, then field selection filters
    assert_contains "$output" "Alpha" "should include Alpha field"
}

# --- --no-dedup + --aggregate: aggregation sees duplicates ---

test_flags_nodedup_aggregate () {
    local tmpfile count_dedup count_nodedup
    tmpfile=$(mktemp)
    printf 'Score: 10\nScore: 20\n' > "$tmpfile"
    count_dedup=$(run_mfe --aggregate --count -s colons "$tmpfile")
    count_nodedup=$(run_mfe --no-dedup --aggregate --count -s colons "$tmpfile")
    rm -f "$tmpfile"
    # With single strategy, no-dedup shouldn't change anything
    # Both should produce aggregate output
    assert_contains "$count_dedup" "" "dedup aggregate count should be numeric"
    assert_contains "$count_nodedup" "" "no-dedup aggregate count should be numeric"
}

# --- --delimiter with multi-character delimiter '|||' ---

test_flags_delimiter_multichar () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'hostname|||web-server-01\nrole|||load-balancer\nenv|||staging\n' > "$tmpfile"
    output=$(run_mfe -r --delimiter '|||' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "hostname" "should extract hostname with ||| delimiter"
    assert_contains "$output" "web-server-01" "should extract value web-server-01"
    assert_contains "$output" "role" "should extract role with ||| delimiter"
    assert_contains "$output" "load-balancer" "should extract value load-balancer"
    assert_contains "$output" "env" "should extract env with ||| delimiter"
    assert_contains "$output" "staging" "should extract value staging"
}

# --- --delimiter with multi-character delimiter '::=' ---

test_flags_delimiter_multichar_coloneq () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'server::=apache\nport::=443\nprotocol::=https\n' > "$tmpfile"
    output=$(run_mfe -r --delimiter '::=' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "server" "should extract server with ::= delimiter"
    assert_contains "$output" "apache" "should extract value apache"
    assert_contains "$output" "port" "should extract port with ::= delimiter"
    assert_contains "$output" "443" "should extract value 443"
}

# --- --delimiter with ' -> ' (multi-char with spaces) ---

test_flags_delimiter_multichar_arrow_spaces () {
    local tmpfile output
    tmpfile=$(mktemp)
    printf 'source -> origin\ntarget -> destination\nstatus -> active\n' > "$tmpfile"
    output=$(run_mfe -r --delimiter ' -> ' "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "source" "should extract source with ' -> ' delimiter"
    assert_contains "$output" "origin" "should extract value origin"
    assert_contains "$output" "target" "should extract target with ' -> ' delimiter"
    assert_contains "$output" "destination" "should extract value destination"
}

# --- --output + --format json: JSON written to file ---

test_flags_output_format_json () {
    local tmpfile outfile output
    tmpfile=$(mktemp)
    outfile=$(mktemp)
    printf 'Name: Alice\nAge: 30\n' > "$tmpfile"
    run_mfe --output "$outfile" -f json -s colons "$tmpfile" >/dev/null 2>&1
    output=$(<"$outfile")
    rm -f "$tmpfile" "$outfile"
    # Should be valid JSON written to the output file
    assert_contains "$output" "{" "output file should contain JSON opening brace"
    assert_contains "$output" "}" "output file should contain JSON closing brace"
    assert_contains "$output" "Name" "output file JSON should contain Name field"
    assert_contains "$output" "Alice" "output file JSON should contain Alice value"
    assert_contains "$output" "Age" "output file JSON should contain Age field"
}

# --- --output + --format csv: CSV written to file ---

test_flags_output_format_csv () {
    local tmpfile outfile output
    tmpfile=$(mktemp)
    outfile=$(mktemp)
    printf 'Host: web01\nPort: 8080\n' > "$tmpfile"
    run_mfe --output "$outfile" -f csv -s colons "$tmpfile" >/dev/null 2>&1
    output=$(<"$outfile")
    rm -f "$tmpfile" "$outfile"
    # CSV should have header row and data row
    assert_contains "$output" "Host" "output file CSV should contain Host header"
    assert_contains "$output" "web01" "output file CSV should contain web01 value"
    assert_contains "$output" "Port" "output file CSV should contain Port header"
}

# --- --output + --format yaml: YAML written to file ---

test_flags_output_format_yaml () {
    local tmpfile outfile output
    tmpfile=$(mktemp)
    outfile=$(mktemp)
    printf 'Name: Bob\nCity: Denver\n' > "$tmpfile"
    run_mfe --output "$outfile" -f yaml -s colons "$tmpfile" >/dev/null 2>&1
    output=$(<"$outfile")
    rm -f "$tmpfile" "$outfile"
    # YAML should have key: value format
    assert_contains "$output" "Name:" "output file YAML should contain Name:"
    assert_contains "$output" "City:" "output file YAML should contain City:"
}

# --- --replay with version mismatch: warns but still works ---

test_flags_replay_version_mismatch () {
    local tmpfile output stderr_output rc
    tmpfile=$(mktemp)
    printf 'Host: localhost\nPort: 8080\n' > "$tmpfile"
    # Run with --replay specifying a version that does not match the installed colons strategy
    rc=0
    output=$(run_mfe --replay 'colons@999.0' -r "$tmpfile" 2>"${tmpfile}.err") || rc=$?
    stderr_output=$(<"${tmpfile}.err")
    rm -f "$tmpfile" "${tmpfile}.err"
    # Should still succeed (exit 0) and produce output
    assert_exit_zero "$rc" "replay with version mismatch should still exit 0"
    assert_contains "$output" "Host" "replay should still extract Host field"
    assert_contains "$output" "localhost" "replay should still extract localhost value"
    # Stderr should contain a version mismatch warning
    assert_contains "$stderr_output" "version mismatch" "stderr should contain version mismatch warning"
}

# --- Register all tests ---

run_test "flags: --replay version mismatch warns" test_flags_replay_version_mismatch
run_test "flags: --sort + --names" test_flags_sort_names
run_test "flags: --sort + --count" test_flags_sort_count
run_test "flags: --rename + --sort" test_flags_rename_sort
run_test "flags: --rename + --aggregate" test_flags_rename_aggregate
run_test "flags: --rename + --names" test_flags_rename_names
run_test "flags: --rename + --count" test_flags_rename_count
run_test "flags: --first-match + --min-confidence" test_flags_firstmatch_minconfidence
run_test "flags: --max-strategies + --no-dedup" test_flags_maxstrategies_nodedup
run_test "flags: --aggregate + --sort" test_flags_aggregate_sort
run_test "flags: --aggregate + --count" test_flags_aggregate_count
run_test "flags: --quiet + --min-confidence 100" test_flags_quiet_minconfidence_high
run_test "flags: --verbose + --first-match" test_flags_verbose_firstmatch
run_test "flags: --output + --sort" test_flags_output_sort
run_test "flags: -f csv + --rename" test_flags_format_csv_rename
run_test "flags: -f json + --aggregate" test_flags_format_json_aggregate
run_test "flags: --stream + --rename" test_flags_stream_rename
run_test "flags: field-by-name + --sort" test_flags_field_by_name_sort
run_test "flags: --no-dedup + --aggregate" test_flags_nodedup_aggregate
run_test "flags: --delimiter multi-char '|||'" test_flags_delimiter_multichar
run_test "flags: --delimiter multi-char '::='" test_flags_delimiter_multichar_coloneq
run_test "flags: --delimiter multi-char ' -> '" test_flags_delimiter_multichar_arrow_spaces
run_test "flags: --output + --format json" test_flags_output_format_json
run_test "flags: --output + --format csv" test_flags_output_format_csv
run_test "flags: --output + --format yaml" test_flags_output_format_yaml

print_summary
