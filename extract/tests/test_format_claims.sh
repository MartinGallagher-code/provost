#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Format-level parsers decline what they do not understand, and multi-section
## reports keep their sections (round-2 benchmark patterns 2, 5 and 6, worked
## 2026-10-16).
##
## Every fixture is written for this test or lives under samples/ — none is a
## corpus or benchmark input. Each shape is a DIFFERENT tool from the round-2
## input that exposed it (ltrace for strace, cargo test for pytest, node
## exporter for the apiserver, check_load for check_disk, rpm -qi for openssl
## list, hiera for apt-config, nmcli -t for gpgconf, netstat -rn / arp -a /
## ipcs for route print and diskutil, mutt -v for vim --version, a sorted-list
## comparison for comm).
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Format Claims + Section Tests"
echo "========================================"

EXTRACT_DIR="$(dirname "$PROVOST_EXTRACT_SCRIPT")"
SMP="$EXTRACT_DIR/samples"
T="$(mktemp -d "${TMPDIR:-/tmp}/format_claims.XXXXXX")"

_winner () {
    run_extract --emit-meta -f tsv --max-strategies 1 "$@" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $2; exit }'
}
_plain () { run_extract -f plain --max-strategies 1 "$@" 2>/dev/null; }

# --- Part A: format parsers decline -------------------------------------------

test_toml_needs_its_grammar () {
    cat > "$T/cfg.txt" <<'EOF'
Plugins are disabled because this shell runs as root.
Set ACME_ALLOW_ROOT=1 to enable plugins for the root user.
[core.editor] vim
[core.pager] less -FRX
[cache.dir] /root/.cache/acme
[cache.ttl] 86400
[remote.origin.url] https://registry.acme.dev
[log.level] info
EOF
    local w; w="$(_winner "$T/cfg.txt")"
    [[ "$w" != toml ]] || _assert_failed "a [key] value listing is not TOML (got $w)"
    cat > "$T/cargo.toml" <<'EOF'
# generated
[build]
jobs = 8
rustflags = ["-C", "target-cpu=native"]

[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = [
  "-C", "link-arg=-fuse-ld=lld",
]
EOF
    assert_eq "$(_winner "$T/cargo.toml")" "toml" "real TOML (multi-line array) still TOML"
}

test_equals_declines_nested_equals () {
    cat > "$T/ltrace.txt" <<'EOF'
setlocale(LC_ALL, "")                            = "C.UTF-8"
getenv("HOME")                                   = "/root"
malloc(24)                                       = 0x55d1c0a2b2c0
memcpy(0x55d1c0a2b2c0, "key=value", 9)           = 0x55d1c0a2b2c0
fopen("/etc/app.conf", "r")                      = 0x55d1c0a2b2f0
strchr("mode=fast\n", '=')                       = "=fast\n"
puts("done")                                     = 5
EOF
    local w; w="$(_winner "$T/ltrace.txt")"
    [[ "$w" != equals ]] || _assert_failed "ltrace's call = result lines are not KEY=VALUE (got $w)"
    printf 'LANG=C.UTF-8\nHOME=/root\nPATH=/usr/bin:/bin\nEDITOR=vim\n' > "$T/env.txt"
    assert_eq "$(_winner "$T/env.txt")" "equals" "an env dump is still equals"
    assert_eq "$(_FR_BIG_BYTES=0 _winner "$T/ltrace.txt")" "$w" "awk route decides the same"
}

test_vertical_line_needs_a_pure_rule () {
    cat > "$T/cargo-test.txt" <<'EOF'
running 2 tests
test parser::tests::empty_input ... ok
test parser::tests::trailing_comma ... FAILED

failures:

---- parser::tests::trailing_comma stdout ----
thread 'parser::tests::trailing_comma' panicked at src/parser.rs:88:9:
assertion `left == right` failed

test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.03s
EOF
    local w; w="$(_winner "$T/cargo-test.txt")"
    [[ "$w" != vertical-line ]] || _assert_failed "a titled rule is not a column underline (got $w)"
    cat > "$T/cov.txt" <<'EOF'
Name                      Stmts   Miss  Cover
---------------------------------------------
src/app/cli.py               48     12    75%
src/app/core.py             120      9    92%
---------------------------------------------
TOTAL                       168     21    88%
EOF
    assert_eq "$(_winner "$T/cov.txt")" "vertical-line" "a header over a pure rule is still vertical-line"
}

test_yaml_declines_a_table_with_colons () {
    cat > "$T/wmic.txt" <<'EOF'
DriveLetter  FileSystem  Label        SerialNumber
C:           NTFS        Windows      3456789012
D:           NTFS        Data         1234567890
E:           FAT32       BOOTSTICK    2233445566
EOF
    local w; w="$(_winner "$T/wmic.txt")"
    [[ "$w" != yaml ]] || _assert_failed "drive letters are not YAML keys (got $w)"
    printf 'Loaded profile\nname: web\nreplicas: 3\nimage: nginx:1.27\nstrategy: rolling\nport: 8080\n' > "$T/banner.yaml"
    assert_eq "$(_winner "$T/banner.yaml")" "yaml" "a gutter-free banner over YAML is still YAML"
}

test_csv_ignores_label_set_commas () {
    cat > "$T/metrics.txt" <<'EOF'
node_filesystem_avail_bytes{device="/dev/nvme0n1p2",fstype="ext4",mountpoint="/"} 1.8231476224e+11
node_filesystem_avail_bytes{device="tmpfs",fstype="tmpfs",mountpoint="/run"} 3.3488896e+09
node_filesystem_size_bytes{device="/dev/nvme0n1p2",fstype="ext4",mountpoint="/"} 4.9083162624e+11
node_filesystem_size_bytes{device="tmpfs",fstype="tmpfs",mountpoint="/run"} 3.3509376e+09
EOF
    local w; w="$(_winner --generic "$T/metrics.txt")"
    [[ "$w" != csv ]] || _assert_failed "commas inside {labels} are not CSV separators (got $w)"
}

test_semicolons_inside_words_are_not_records () {
    printf 'OK - load average: 0.12, 0.15, 0.10|load1=0.120;5.000;10.000;0; load5=0.150;4.000;6.000;0; load15=0.100;3.000;4.000;0;\n' > "$T/nagios.txt"
    local w; w="$(_winner "$T/nagios.txt")"
    [[ "$w" != semicolon-values ]] || _assert_failed "Nagios perfdata is not one semicolon record (got $w)"
    printf '3;fio-3.36;randread;0;0;28221440;482104;120526;58539;3;137;5.21\n' > "$T/fio.txt"
    assert_eq "$(_winner "$T/fio.txt")" "semicolon-values" "fio terse is still semicolon-values"
}

test_colons_records () {
    local out
    out="$(_plain "$SMP/colons/rpm-qi.txt")"
    assert_eq "$(_winner "$SMP/colons/rpm-qi.txt")" "colons" "rpm -qi: colons"
    assert_contains "$out" "entry2.Name coreutils" "second record opened by the repeated first key"
    assert_contains "$out" "entry3.Architecture x86_64" "every record keeps its fields"
    assert_contains "$out" "total_entries 3" "three records"
    out="$(_plain "$SMP/colons/opencl-platforms.txt")"
    assert_contains "$out" "entry1.section Platforms" "bare heading names the section"
    assert_contains "$out" "entry3.Vendor The pocl project" "indented records split"
    out="$(_FR_BIG_BYTES=0 _plain "$SMP/colons/rpm-qi.txt")"
    assert_contains "$out" "entry2.Name coreutils" "awk route hands records to the bash loop"
}

test_json_reads_object_literals () {
    assert_eq "$(_winner "$SMP/json/node-inspect.txt")" "json" "node inspect literal: json"
    assert_contains "$(_plain "$SMP/json/node-inspect.txt")" "heapUsed 5192344" "bare key read"
    assert_contains "$(_plain "$SMP/json/node-interfaces.txt")" "eth0.0.family IPv4" "single-quoted value read"
    printf "[\n  { model: 'Xeon', speed: 0 },\n  { model: 'Xeon', speed: 1, },\n]\n" > "$T/cpus.txt"
    assert_contains "$(_plain "$T/cpus.txt")" "entry2.speed 1" "a literal array is one row per element"
    printf "{ a: 1, f: [Function: f] }\n" > "$T/fn.txt"
    local w; w="$(_winner "$T/fn.txt")"
    [[ "$w" != json ]] || _assert_failed "a literal holding a function is not data (got $w)"
}

test_colon_fields_namespaces_and_spaced_fields () {
    cat > "$T/hiera.txt" <<'EOF'
profile::base::ntp::servers ["0.pool.ntp.org", "1.pool.ntp.org"]
profile::base::ssh::permit_root_login "no"
profile::web::nginx::worker_processes 4
role::db::postgres::max_connections 200
EOF
    local w; w="$(_winner "$T/hiera.txt")"
    [[ "$w" != colon-fields ]] || _assert_failed "a :: namespace is not a field delimiter (got $w)"
    assert_eq "$(_winner "$SMP/colon-fields/nmcli-terse.txt")" "colon-fields" "nmcli -t: colon-fields"
    assert_contains "$(_plain "$SMP/colon-fields/nmcli-terse.txt")" "entry2.A home wifi 5G" "a field with blanks stays whole"
    printf 'web::10.0.0.1:80\napi::10.0.0.2:8080\ndb::10.0.0.3:5432\n' > "$T/listeners.txt"
    assert_eq "$(_winner "$T/listeners.txt")" "colon-fields" "a :: delimiter before a number still counts"
    printf '06:00:00  1 of 3 START model a\n06:00:02  1 of 3 OK model a\n06:00:04  Finished\n' > "$T/clock.txt"
    w="$(_winner "$T/clock.txt")"
    [[ "$w" != colon-fields ]] || _assert_failed "clock colons are not fields (got $w)"
}

# --- Part B: sections and indentation ------------------------------------------

test_key_value_lists_and_labels () {
    local out
    out="$(_plain "$SMP/key-value/docker-info-lists.txt")"
    assert_contains "$out" "https://mirror.gcr.io/" "list item kept"
    assert_eq "$(grep -c '^entry[0-9]*\.key Registry Mirrors$' <<< "$out")" "2" "one row per list item"
    cat > "$T/probe.txt" <<'EOF'
Input #0, matroska, from 'clip.mkv':
  Duration: 00:01:02.00, start: 0.000000, bitrate: 900 kb/s
  Stream #0:0: Video: vp9 (Profile 0), yuv420p, 1280x720
  Stream #0:1(eng): Audio: opus, 48000 Hz, stereo
Stream mapping:
  Stream #0:0 -> #0:0 (vp9 (native) -> h264 (libx264))
  Stream #0:1 -> #0:1 (opus (native) -> aac (native))
Press [q] to stop, [?] for help
Output #0, mp4, to 'clip.mp4':
  Stream #0:0: Video: h264, yuv420p, 1280x720
  Stream #0:1: Audio: aac (LC), 48000 Hz, stereo
EOF
    out="$(_plain -s key-value "$T/probe.txt")"
    assert_contains "$out" ".key Stream #0:1(eng)" "a label holding a colon stays whole"
    assert_contains "$out" ".value Stream #0:1 -> #0:1 (opus (native) -> aac (native))" "mapping lines are rows"
    assert_contains "$out" ".key Press [q] to stop, [?] for help" "an unindented text line is its own row"
}

test_section_tables () {
    local out
    assert_eq "$(_winner "$SMP/section-tables/netstat-rn.txt")" "section-tables" "netstat -rn: section-tables"
    out="$(_plain "$SMP/section-tables/netstat-rn.txt")"
    assert_contains "$out" "section Internet6" "IPv6 rows carry their section"
    assert_contains "$out" "Netif utun0" "padded-wider table reads the same columns"
    out="$(_plain "$SMP/section-tables/arp-a.txt")"
    assert_contains "$out" "Internet_Address 172.27.95.255" "two-word label from offsets"
    assert_contains "$out" "section Interface: 172.27.80.1 --- 0x1c" "per-interface section"
    out="$(_plain "$SMP/section-tables/ipcs.txt")"
    assert_contains "$out" "section Semaphore Arrays" "titled-rule sections"
    assert_contains "$out" "nsems 17" "different headers unioned"
    out="$(_plain -s section-tables "$SMP/section-tables/iptables-chains.txt")"
    assert_contains "$out" "target DOCKER-USER" "a one-row chain reads the shared columns"
    local w
    cat > "$T/svc.txt" <<'EOF'
Service 'web'
  state                running
  pid                  4120
  restarts             0

Service 'worker'
  state                stopped
  pid                  -
  restarts             3
EOF
    w="$(_winner "$T/svc.txt")"
    [[ "$w" != section-tables ]] || _assert_failed "two-column key/value blocks are not titled tables"
    printf 'Name   Size\nfoo    1\nbar    2\n' > "$T/one.txt"
    w="$(_winner "$T/one.txt")"
    [[ "$w" != section-tables ]] || _assert_failed "one untitled table is not section-tables"
}

test_kv_report_sign_grid () {
    assert_eq "$(_winner "$SMP/kv-report/feature-grid.txt")" "kv-report" "banner + sign grid: kv-report ranked"
    local out; out="$(_plain "$SMP/kv-report/feature-grid.txt")"
    assert_contains "$out" ".key cscope" "grid token is a row"
    assert_contains "$out" ".section Optional features (+ enabled, - disabled)" "grid title is its section"
    assert_contains "$out" ".key Linking" "key lines after the grid kept"
    out="$(_plain "$SMP/kv-report/mutt-v.txt")"
    assert_contains "$out" ".key USE_SSL_GNUTLS" "mutt compile options read"
}

test_indent_columns () {
    local out; out="$(_plain "$SMP/indent-tree/comm-columns.txt")"
    assert_eq "$(_winner "$SMP/indent-tree/comm-columns.txt")" "indent-tree" "TAB columns: indent-tree"
    assert_contains "$out" $'entry5.depth 2\nentry5.name eleven' "column rank kept as depth"
    assert_not_contains "$out" "parent" "columns are not a tree"
    assert_contains "$(_plain "$SMP/indent-tree/basic.txt")" "parent" "a real tree keeps its parents"
}

test_indented_hierarchy_needs_key_colons () {
    cat > "$T/report.txt" <<'EOF'
FAILURES
  test_app.py:14: AssertionError
  test_app.py:23: AssertionError
slowest durations
  0.31s call     test_app.py::test_slow
  0.12s call     test_app.py::test_medium
EOF
    local w; w="$(_winner "$T/report.txt")"
    [[ "$w" != indented-hierarchy ]] || _assert_failed "file:line colons are not keys (got $w)"
}

run_test "toml needs its grammar"                     test_toml_needs_its_grammar
run_test "equals declines = inside brackets"          test_equals_declines_nested_equals
run_test "vertical-line needs a pure rule"            test_vertical_line_needs_a_pure_rule
run_test "yaml declines a table with colons"          test_yaml_declines_a_table_with_colons
run_test "csv ignores label-set commas"               test_csv_ignores_label_set_commas
run_test "semicolons inside words"                    test_semicolons_inside_words_are_not_records
run_test "colons: repeated records"                   test_colons_records
run_test "json: object literals"                      test_json_reads_object_literals
run_test "colon-fields: namespaces, spaced fields"    test_colon_fields_namespaces_and_spaced_fields
run_test "key-value: lists and labels"                test_key_value_lists_and_labels
run_test "section-tables"                             test_section_tables
run_test "kv-report: sign grid"                       test_kv_report_sign_grid
run_test "indent-tree: TAB columns"                   test_indent_columns
run_test "indented-hierarchy needs key colons"        test_indented_hierarchy_needs_key_colons

rm -rf "$T"
print_summary
