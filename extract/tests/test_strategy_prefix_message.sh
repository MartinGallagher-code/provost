#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: prefix-message (line diagnostics + logs) and help-columns
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: prefix-message / help-columns"
echo "========================================"

PM_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pm_tests.XXXXXX")"
trap 'rm -rf "$PM_TMP"' EXIT

# _winner FILE [engine args…] — the auto-detected strategy (generic set)
_winner () {
    local f="$1"; shift
    run_extract --generic --emit-meta -f tsv --max-strategies 1 "$@" "$f" 2>&1 >/dev/null |
        awk -F'\t' '/^__EXTRACT_META__/ { print $2 }'
}
# _conf FILE — its confidence
_conf () {
    run_extract --generic --emit-meta -f tsv --max-strategies 1 "$1" 2>&1 >/dev/null |
        awk -F'\t' '/^__EXTRACT_META__/ { print $3 }'
}
_pm () { run_extract -r -s prefix-message "$1"; }
_hc () { run_extract -r -s help-columns "$1"; }

################################################################################
## diagnostics
################################################################################

test_pm_gcc () {
    local f="$SAMPLES_DIR/prefix-message/basic.txt" out
    assert_eq "$(_winner "$f")" "prefix-message" "gcc output auto-detects as prefix-message"
    out=$(_pm "$f")
    assert_contains "$out" "entry1.file main.c" "file split off"
    assert_contains "$out" "entry1.line 5" "line split off"
    assert_contains "$out" "entry1.col 13" "column split off"
    assert_contains "$out" "entry1.severity warning" "severity split off"
    assert_contains "$out" "entry1.code -Wint-conversion" "trailing [-Wflag] becomes the code"
    assert_contains "$out" "entry2.message 'y' undeclared (first use in this function)" "message keeps its text"
    assert_contains "$out" "entry1.context main.c: In function 'main'" "the In-function title is context"
    assert_contains "$out" "entry4.context util.c: In function 'parse'" "context follows the next title"
    assert_contains "$out" 'entry2.detail 6 |     y = 3;; |     ^' "caret excerpt attached as detail"
    assert_contains "$out" "total_entries 4" "four diagnostics, no junk rows"
}

test_pm_flake8_mypy_style () {
    local f="$PM_TMP/flake8.txt" out
    cat > "$f" <<'EOF'
app/__init__.py:1:1: F401 'os' imported but unused
app/views.py:14:80: E501 line too long (97 > 79 characters)
app/views.py:22:5: E722 do not use bare 'except'
tests/test_views.py:9:1: F811 redefinition of unused 'client' from line 4
EOF
    assert_eq "$(_winner "$f")" "prefix-message" "flake8 auto-detects"
    out=$(_pm "$f")
    assert_contains "$out" "entry2.code E501" "code after the location"
    assert_contains "$out" "entry2.message line too long (97 > 79 characters)" "message after the code"
    cat > "$f" <<'EOF'
deploy.sh:4:8: warning: Double quote to prevent globbing and word splitting. [SC2086]
deploy.sh:9:1: note: Not following: ./env.sh was not specified as input. [SC1091]
backup.sh:22:3: warning: Use 'cd ... || exit' in case cd fails. [SC2164]
EOF
    out=$(_pm "$f")
    assert_contains "$out" "entry1.code SC2086" "trailing [code] split off"
    assert_contains "$out" "entry2.message Not following: ./env.sh was not specified as input." "message without the trailing code"
}

test_pm_msbuild_paren_location () {
    local out
    out=$(_pm "$SAMPLES_DIR/prefix-message/dotnet.txt")
    assert_contains "$out" "entry1.file /src/Billing/InvoiceService.cs" "file(line,col) path"
    assert_contains "$out" "entry1.line 42" "paren line"
    assert_contains "$out" "entry1.col 17" "paren column"
    assert_contains "$out" "entry1.code CS0168" "msbuild code"
    assert_contains "$out" "entry1.tag /src/Billing/Billing.csproj" "trailing project bracket kept (tag: the code column is taken)"
}

test_pm_rustc_location_under_headline () {
    local out
    out=$(_pm "$SAMPLES_DIR/prefix-message/rustc.txt")
    assert_contains "$out" "entry2.code E0308" "error[E0308] carries its code"
    assert_contains "$out" "entry2.file src/db.rs" "--> location fills file"
    assert_contains "$out" "entry2.line 31" "--> location fills line"
    assert_contains "$out" "entry2.message mismatched types" "headline is the message"
    assert_contains "$out" "entry6.message For more information about an error" "the trailing summary is a row of its own"
}

################################################################################
## logs
################################################################################

test_pm_log4j_stacktrace () {
    local f="$SAMPLES_DIR/prefix-message/logback.txt" out
    assert_eq "$(_winner "$f")" "prefix-message" "logback log auto-detects"
    out=$(_pm "$f")
    assert_contains "$out" "entry5.timestamp 10:16:12.774" "time"
    assert_contains "$out" "entry5.thread pool-2-thread-3" "[thread] beside a logger"
    assert_contains "$out" "entry5.level ERROR" "level"
    assert_contains "$out" "entry5.logger c.a.inventory.sync.Supplier" "logger before ' - '"
    assert_contains "$out" "entry5.message Sync failed" "message"
    assert_contains "$out" "entry5.detail java.net.SocketTimeoutException: Read timed out; at java.base" "stack trace attached to its record"
    assert_contains "$out" "Caused by: java.io.IOException: stream closed" "Caused by stays in the detail"
    assert_contains "$out" "total_entries 6" "six records, no row per stack frame"
}

test_pm_python_logging () {
    local out
    out=$(_pm "$SAMPLES_DIR/prefix-message/pylogging-basic.txt")
    assert_contains "$out" "entry2.level INFO" "LEVEL:"
    assert_contains "$out" "entry2.logger app.db" ":logger:"
    assert_contains "$out" "entry2.message Connected to postgres://db:5432/app" "message keeps its colons"
    assert_contains "$out" "entry4.detail Traceback (most recent call last):" "traceback attached"
    assert_contains "$out" "TimeoutError: upstream took too long" "exception line attached"
}

test_pm_nginx_journal_spring () {
    local out
    out=$(_pm "$SAMPLES_DIR/prefix-message/nginx-error.txt")
    assert_contains "$out" "entry4.timestamp 2026/10/14 09:47:10" "slash date"
    assert_contains "$out" "entry4.level error" "[error] is a level"
    assert_contains "$out" "entry4.pid 29#29" "pid#tid"
    out=$(_pm "$SAMPLES_DIR/prefix-message/journal-short-iso.txt")
    assert_contains "$out" "entry4.host web01" "host"
    assert_contains "$out" "entry4.process sshd" "process"
    assert_contains "$out" "entry4.pid 20431" "pid"
    assert_contains "$out" "entry4.message Accepted publickey for deploy" "message"
    out=$(_pm "$SAMPLES_DIR/prefix-message/spring.txt")
    assert_contains "$out" "entry1.pid 48211" "spring pid"
    assert_contains "$out" "entry1.thread main" "padded [   main] thread trimmed"
    assert_contains "$out" "entry1.logger com.acme.shop.ShopApplication" "padded logger"
    assert_contains "$out" "entry6.thread nio-8080-exec-3" "a record missing one trailing field keeps the rest"
    assert_contains "$out" "entry6.detail java.lang.IllegalStateException" "stack trace attached"
}

test_pm_markers () {
    local out
    assert_eq "$(_winner "$SAMPLES_DIR/prefix-message/markers.txt")" "prefix-message" "marker lines auto-detect"
    out=$(_pm "$SAMPLES_DIR/prefix-message/markers.txt")
    assert_contains "$out" "entry3.marker ✖" "marker column"
    assert_contains "$out" "entry3.message unit tests: 3 failed, 211 passed" "message"
}

################################################################################
## what it must leave alone
################################################################################

test_pm_declines_tables_and_lists () {
    local f="$PM_TMP/neg.txt"
    # a date column over a size/name grid is a table
    printf '%s\n' '2026-06-30 22:14  412481024   s3://media/report.parquet' \
        '2026-05-11 09:41 1478135156   s3://db/full.tar.gz' \
        '2026-07-01 03:00     8842112   s3://logs/access.log.gz' > "$f"
    assert_not_contains "$(_winner "$f")" "prefix-message" "timestamped grid is not a log"
    # sar-style columns under a time column
    printf '%s\n' '12:00:01 AM     CPU     %user     %nice   %system' \
        '12:10:01 AM     all      3.42      0.00      1.28' \
        '12:20:01 AM     all      4.11      0.00      1.90' > "$f"
    assert_not_contains "$(_winner "$f")" "prefix-message" "sar table is not a log"
    # distinct level-word labels are a key/value block
    printf '%s\n' 'Error: 0' 'Warning: 2' 'Info: none' > "$f"
    assert_not_contains "$(_winner "$f")" "prefix-message" "kv block of level words"
    # one bullet repeated is a list
    printf '%s\n' '* alpha one' '* beta two three' '* gamma' > "$f"
    assert_not_contains "$(_winner "$f")" "prefix-message" "bullet list"
    # lowercase prose words are not levels
    printf '%s\n' 'trace id 5f2a inet filter input packet: iif eth0' \
        'trace id 5f2a inet filter input rule accept' 'trace id b731 inet filter input verdict drop' > "$f"
    assert_not_contains "$(_winner "$f")" "prefix-message" "nft trace lines"
}

test_pm_leaves_syslog_and_bracket_log () {
    local f="$PM_TMP/syslog.txt"
    printf '%s\n' 'Oct 14 10:00:01 web01 sshd[2041]: Accepted publickey for root' \
        'Oct 14 10:00:02 web01 CRON[2050]: (root) CMD (run-parts /etc/cron.hourly)' \
        'Oct 14 10:00:03 web01 kernel: eth0: link up' > "$f"
    assert_eq "$(_winner "$f")" "syslog" "BSD syslog stays with syslog"
    printf '%s\n' '[WARNING] Could not fetch resource logo.png' '[INFO] Wrote output.pdf (442 KB)' \
        '[INFO] Done' > "$f"
    assert_eq "$(_winner "$f")" "bracket-log" "a lone [tag] prefix stays with bracket-log"
}

test_pm_big_input () {
    local f="$PM_TMP/big.log" i out
    {
        for ((i = 1; i <= 1500; i++)); do
            printf '2026-10-14 10:%02d:%02d,%03d INFO  [worker-%d] c.a.Svc - processed batch %d in %dms\n' \
                $((i / 60 % 60)) $((i % 60)) $((i % 1000)) $((i % 4)) "$i" $((i % 97))
            if (( i % 250 == 0 )); then
                printf '%s\n' 'java.lang.IllegalStateException: boom' '	at c.a.Svc.run(Svc.java:12)'
            fi
        done
    } > "$f"
    assert_eq "$(_winner "$f")" "prefix-message" "a >32 KB log still auto-detects (sample screen, full decide)"
    out=$(run_extract -r -s prefix-message "$f")
    assert_contains "$out" "entry250.detail java.lang.IllegalStateException: boom; at c.a.Svc.run(Svc.java:12)" "trace attached on the big path"
    assert_contains "$out" "total_entries 1500" "one row per record"
}

################################################################################
## help-columns
################################################################################

test_hc_docker_help () {
    local f="$SAMPLES_DIR/help-columns/basic.txt" out
    assert_eq "$(_winner "$f")" "help-columns" "docker --help auto-detects"
    out=$(_hc "$f")
    assert_contains "$out" "entry3.section Common Commands" "section title carried down"
    assert_contains "$out" "entry3.name run" "term"
    assert_contains "$out" "entry3.description Create and run a new container from an image" "description keeps its spaces"
    assert_contains "$out" "entry13.name -c, --context string" "option list with an argument is one term"
    assert_contains "$out" "entry1.description Usage:  docker [OPTIONS] COMMAND" "usage line kept as a row"
}

test_hc_wrapped_and_term_only () {
    local out
    out=$(_hc "$SAMPLES_DIR/help-columns/ls-help.txt")
    assert_contains "$out" "entry9.description with -l, scale sizes by SIZE when printing them; e.g., '--block-size=M'; see SIZE format below" "wrapped description joined"
    out=$(_hc "$SAMPLES_DIR/help-columns/npm-run.txt")
    assert_contains "$out" "entry1.section Lifecycle scripts included in web-shop@2.3.0" "npm section"
    assert_contains "$out" "entry1.name start" "term alone on its line"
    assert_contains "$out" "entry1.description node dist/server.js" "description on the next line"
    out=$(_hc "$SAMPLES_DIR/help-columns/rake-T.txt")
    assert_contains "$out" "entry4.name rake db:migrate" "rake -T term"
    assert_contains "$out" "entry4.description Migrate the database" "comment column without its #"
    out=$(_hc "$SAMPLES_DIR/help-columns/wget-help.txt")
    assert_contains "$out" "entry4.name -V, --version" "wget's gapped short option stays with its long form"
}

test_hc_declines_tables () {
    local f="$PM_TMP/tbl.txt"
    printf '%s\n' '  NAME        READY   STATUS    RESTARTS   AGE' \
        '  web-7d4b9   1/1     Running   0          2d' \
        '  db-0        1/1     Running   1          9d' \
        '  cache-x1    0/1     Pending   0          3m' > "$f"
    assert_not_contains "$(_winner "$f")" "help-columns" "indented table"
    printf '%s\n' 'rails (7.0.4)' '  actioncable (= 7.0.4)' '    actionpack (= 7.0.4)' \
        '      actionview (= 7.0.4)' '  activerecord (= 7.0.4)' '    activemodel (= 7.0.4)' > "$f"
    assert_not_contains "$(_winner "$f")" "help-columns" "dependency tree"
    printf '%s\n' 'cluster:' '    id:     a1b2c3d4' '    health: HEALTH_OK' 'services:' \
        '    mon: 3 daemons, quorum a,b,c' '    osd: 12 osds: 12 up, 12 in' > "$f"
    assert_not_contains "$(_winner "$f")" "help-columns" "indented key: value report"
}

run_test "prefix-message: gcc diagnostics + carets + context" test_pm_gcc
run_test "prefix-message: flake8 / shellcheck codes" test_pm_flake8_mypy_style
run_test "prefix-message: msbuild file(line,col)" test_pm_msbuild_paren_location
run_test "prefix-message: rustc location under the headline" test_pm_rustc_location_under_headline
run_test "prefix-message: log4j-style log + stack trace" test_pm_log4j_stacktrace
run_test "prefix-message: python logging + traceback" test_pm_python_logging
run_test "prefix-message: nginx / journal / spring" test_pm_nginx_journal_spring
run_test "prefix-message: marker lines" test_pm_markers
run_test "prefix-message: declines tables, kv blocks, lists" test_pm_declines_tables_and_lists
run_test "prefix-message: leaves syslog and bracket-log inputs" test_pm_leaves_syslog_and_bracket_log
run_test "prefix-message: big input" test_pm_big_input
run_test "help-columns: docker --help" test_hc_docker_help
run_test "help-columns: wrapped / term-only / comment forms" test_hc_wrapped_and_term_only
run_test "help-columns: declines tables and trees" test_hc_declines_tables

print_summary
