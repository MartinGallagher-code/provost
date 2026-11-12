#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## The command's name (--command NAME, --batch-commands; PV-037)
##
## Detection is by content; the name of the command that printed the input
## only moves the RANK of what detected: a tool-specific strategy written for
## the command +15, one written for another command -20 (it wins only by a
## clear margin), generic parsers unmoved; a hints.tsv row for the command is
## preferred; a relay (cat, ssh, ...) is ignored. See extract/README.md "The
## command's name".
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Command Name Tests"
echo "========================================"

TMPDIR_C="$(mktemp -d "${TMPDIR:-/tmp}/command_tests.XXXXXX")"
CORPUS="$SCRIPT_DIR/../../tests/corpus/inputs"

# _winner ARGS... FILE — the --emit-meta winner name.
_winner () {
    run_extract --emit-meta -f tsv --max-strategies 1 "$@" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $2 }'
}

# _cmeta ARGS... FILE — the __COMMAND_META__ fields after the tag, tab-joined.
_cmeta () {
    run_extract --emit-meta -f tsv --max-strategies 1 "$@" 2>&1 >/dev/null \
        | awk -F'\t' '/^__COMMAND_META__/ { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }'
}

# _plugin DIR NAME CONF MARKER [COMMANDS] — a strategy that detects MARKER at
# confidence CONF and extracts one field. DIR's last component decides its
# kind: .../structured (or .../delimited) is generic, anything else is
# tool-specific. COMMANDS fills a `## Commands:` header.
_plugin () {
    local dir="$1" name="$2" conf="$3" marker="$4" cmds="${5:-}"
    mkdir -p "$dir"
    {
        printf '#!/bin/bash\n## Name: %s\n## Description: command test plugin %s\n## Version: 1.0\n## Priority: 50\n' "$name" "$name"
        [[ -n "$cmds" ]] && printf '## Commands: %s\n' "$cmds"
        cat <<STRAT

strategy_detect () {
    _STRATEGY_CONFIDENCE=${conf}
    [[ "\$1" == *'${marker}'* ]]
}

strategy_extract () {
    echo '${name//-/_}_key v'
}
STRAT
    } > "$dir/${name}.sh"
}

# One input, three candidates: a generic parser at 80, a tool-specific one
# written for `alpha` at 92, and one written for `beta` at 70 that also reads
# `gamma` (## Commands:).
_fixture () {
    local root="$TMPDIR_C/$1"
    rm -rf "$root"; mkdir -p "$root/plug/structured" "$root/plug/tools"
    _plugin "$root/plug/structured" cmdtest-generic 80 CMDMARK
    _plugin "$root/plug/tools" alpha-report 92 CMDMARK
    _plugin "$root/plug/tools" beta 70 CMDMARK "gamma, delta"
    printf 'CMDMARK one\nCMDMARK two\n' > "$root/in.txt"
}

# Two plugin dirs cannot be given; build one tree whose categories are the
# subdirectories (the engine reads one level of subdirectories).
_pd () { printf '%s' "$TMPDIR_C/$1/plug"; }

test_no_command_ranks_by_confidence () {
    _fixture none
    assert_eq "alpha-report" "$(_winner --plugin-dir "$(_pd none)" "$TMPDIR_C/none/in.txt")" "no name: the highest confidence wins"
    assert_eq "" "$(_cmeta --plugin-dir "$(_pd none)" "$TMPDIR_C/none/in.txt")" "no name: no __COMMAND_META__ line"
}

test_command_for_the_strategy_wins () {
    _fixture own
    local f="$TMPDIR_C/own/in.txt" pd; pd="$(_pd own)"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command beta "$f")" "written for the command: 70 + 15 beats 80"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command /usr/bin/beta "$f")" "a path is reduced to its basename"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command BETA "$f")" "names compare case-insensitively"
    assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command alpha "$f")" "COMMAND- prefix: alpha-report is written for alpha"
    assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command alpha_report "$f")" "_ reads as -"
}

test_commands_header_names_siblings () {
    _fixture sib
    local f="$TMPDIR_C/sib/in.txt" pd; pd="$(_pd sib)"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command gamma "$f")" "## Commands: lists gamma"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command delta "$f")" "## Commands: is comma- or space-separated"
    assert_eq "cmdtest-generic" "$(_winner --plugin-dir "$pd" --command gamma-x "$f")" "## Commands: entries match exactly, not by prefix"
}

# `## Commands: *`: a format many tools print (csvlook's Markdown tables) is
# never ranked lower by a name.
test_commands_wildcard_is_never_demoted () {
    _fixture wild
    local f="$TMPDIR_C/wild/in.txt" pd; pd="$(_pd wild)"
    sed -i 's/^## Commands: gamma, delta$/## Commands: gamma *, delta/' "$pd/tools/beta.sh"
    rm -f "$pd/tools/alpha-report.sh"
    sed -i 's/_STRATEGY_CONFIDENCE=70/_STRATEGY_CONFIDENCE=85/' "$pd/tools/beta.sh"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command zeta "$f")" "* : another command does not demote it (85 beats 80)"
    assert_eq "$(printf 'zeta\tused\tbeta\tbeta\tshared')" "$(_cmeta --plugin-dir "$pd" --command zeta "$f")" "meta: fit shared"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command gamma "$f")" "a named command still boosts it"
    # an unquoted * would glob: run from a directory full of files
    ( cd "$SCRIPT_DIR" && assert_eq "beta" "$(_winner --plugin-dir "$pd" --command zeta "$f")" "* does not glob" )
    assert_eq "csvlook" "$(_winner --command mytool "$CORPUS/quo-md-table-escaped-pipe.txt")" "csvlook keeps a Markdown table whatever printed it"
}

test_command_for_another_tool_needs_a_margin () {
    _fixture other
    local f="$TMPDIR_C/other/in.txt" pd; pd="$(_pd other)"
    # alpha-report 92 - 20 = 72 < 80: the generic parser wins
    assert_eq "cmdtest-generic" "$(_winner --plugin-dir "$pd" --command zeta "$f")" "another command: 92 - 20 loses to a generic 80"
    # with the generic parser at 70, 92 - 20 = 72 still wins by the margin
    sed -i 's/_STRATEGY_CONFIDENCE=80/_STRATEGY_CONFIDENCE=70/' "$pd/structured/cmdtest-generic.sh"
    assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command zeta "$f")" "another command: a clear margin still wins"
    # the reported confidence is the strategy's own, not the rank
    local conf
    conf="$(run_extract --plugin-dir "$pd" --command zeta --emit-meta -f tsv --max-strategies 1 "$f" 2>&1 >/dev/null \
        | awk -F'\t' '/^__EXTRACT_META__/ { print $3 }')"
    assert_eq "92" "$conf" "the confidence reported is unadjusted"
}

# --command-hint (provost's --name, a batch NAME): it boosts, never demotes.
test_command_hint_only_boosts () {
    _fixture hintonly
    local f="$TMPDIR_C/hintonly/in.txt" pd; pd="$(_pd hintonly)"
    # nothing is demoted: alpha-report (92, for alpha) still beats beta (70 + 15)
    assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command-hint beta "$f")" "a hint demotes no other tool's parser"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command beta "$f")" "...where a --command would"
    assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command-hint zeta "$f")" "a hint for nothing changes nothing"
    assert_eq "cmdtest-generic" "$(_winner --plugin-dir "$pd" --command zeta "$f")" "...where a --command demotes"
    assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command alpha --command-hint beta "$f")" "a real command wins over the hint"
    assert_eq "$(printf 'zeta\thint\talpha-report\talpha-report\tother')" "$(_cmeta --plugin-dir "$pd" --command-hint zeta "$f")" "meta: state hint, a winner written for another tool"
    # the boost: without alpha-report, beta (70 + 15) beats the generic 80
    rm -f "$pd/tools/alpha-report.sh"
    assert_eq "cmdtest-generic" "$(_winner --plugin-dir "$pd" "$f")" "no name: the generic 80 beats beta's 70"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command-hint beta "$f")" "a hint for the strategy boosts it"
    assert_eq "beta" "$(_winner --plugin-dir "$pd" --command cat --command-hint beta "$f")" "a relay command gives way to the hint"
    assert_eq "$(printf 'beta\thint\tbeta\tcmdtest-generic\tfor')" "$(_cmeta --plugin-dir "$pd" --command cat --command-hint beta "$f")" "meta: the hint changed the winner"
    _fixture hintonly
    local h="$TMPDIR_C/hintonly/hints.tsv"
    printf 'firsttool\tprefix\tCMDMARK\talpha-report\n' > "$h"
    assert_eq "firsttool" "$(PROVOST_HINTS_FILE="$h" _winner --plugin-dir "$pd" --command-hint zeta "$f")" "a hint passes no hint row over"
    local rc=0; run_extract --command-hint >/dev/null 2>&1 || rc=$?
    assert_exit_nonzero "$rc" "--command-hint needs a name"
}

test_relay_is_ignored () {
    _fixture relay
    local f="$TMPDIR_C/relay/in.txt" pd c; pd="$(_pd relay)"
    for c in cat ssh bash grep sort; do
        assert_eq "alpha-report" "$(_winner --plugin-dir "$pd" --command "$c" "$f")" "relay '$c' ranks as with no name"
    done
    assert_eq "$(printf 'cat\trelay\talpha-report\talpha-report\t-')" "$(_cmeta --plugin-dir "$pd" --command cat "$f")" "relay meta line"
}

test_command_meta_line () {
    _fixture meta
    local f="$TMPDIR_C/meta/in.txt" pd; pd="$(_pd meta)"
    assert_eq "$(printf 'beta\tused\tbeta\talpha-report\tfor')" "$(_cmeta --plugin-dir "$pd" --command beta "$f")" "name, used, first, first without it, fit"
    assert_eq "$(printf 'zeta\tused\tcmdtest-generic\talpha-report\tgeneric')" "$(_cmeta --plugin-dir "$pd" --command zeta "$f")" "a generic winner"
    assert_eq "$(printf 'alpha\tused\talpha-report\talpha-report\tfor')" "$(_cmeta --plugin-dir "$pd" --command alpha "$f")" "unchanged ranking"
    sed -i 's/_STRATEGY_CONFIDENCE=80/_STRATEGY_CONFIDENCE=60/' "$pd/structured/cmdtest-generic.sh"
    assert_eq "$(printf 'zeta\tused\talpha-report\talpha-report\tother')" "$(_cmeta --plugin-dir "$pd" --command zeta "$f")" "a winner written for another command"
}

# PRUNING stays exact under a command: the same winner as the unpruned pass,
# for every name.
test_pruning_exact_with_command () {
    _fixture prune
    local f="$TMPDIR_C/prune/in.txt" pd c; pd="$(_pd prune)"
    for c in "" alpha beta gamma zeta cat; do
        assert_eq "$(_EAS_NOPRUNE=1 _winner --plugin-dir "$pd" ${c:+--command "$c"} "$f")" \
            "$(_winner --plugin-dir "$pd" ${c:+--command "$c"} "$f")" "same winner pruned and unpruned (command '${c:-none}')"
    done
    for c in "" netstat ip poetry; do
        assert_eq "$(_EAS_NOPRUNE=1 _winner ${c:+--command "$c"} "$CORPUS/netstat-anp.txt")" \
            "$(_winner ${c:+--command "$c"} "$CORPUS/netstat-anp.txt")" "netstat-anp: same winner pruned and unpruned (command '${c:-none}')"
    done
}

# hints.tsv: a row for the command beats an earlier row for another tool; a
# row for another tool routing to a tool-specific strategy is passed over.
test_hint_rows_prefer_the_command () {
    _fixture hint
    local f="$TMPDIR_C/hint/in.txt" pd h="$TMPDIR_C/hint/hints.tsv"; pd="$(_pd hint)"
    printf 'firsttool\tprefix\tCMDMARK\ttext-lines\nsecondtool\tprefix\tCMDMARK\tline-records\n' > "$h"
    assert_eq "firsttool" "$(PROVOST_HINTS_FILE="$h" _winner --plugin-dir "$pd" "$f")" "no name: the first matching row"
    assert_eq "secondtool" "$(PROVOST_HINTS_FILE="$h" _winner --plugin-dir "$pd" --command secondtool "$f")" "the command's own row wins"
    assert_eq "firsttool" "$(PROVOST_HINTS_FILE="$h" _winner --plugin-dir "$pd" --command zeta "$f")" "no row for the command: the first row routing to a generic parser"
    printf 'firsttool\tprefix\tCMDMARK\talpha-report\n' > "$h"
    assert_eq "firsttool" "$(PROVOST_HINTS_FILE="$h" _winner --plugin-dir "$pd" "$f")" "no name: a bespoke routing row fires"
    assert_eq "cmdtest-generic" "$(PROVOST_HINTS_FILE="$h" _winner --plugin-dir "$pd" --command zeta "$f")" "another command: a bespoke routing row is passed over"
    assert_eq "$(printf 'zeta\tused\tcmdtest-generic\tfirsttool\tgeneric')" \
        "$(PROVOST_HINTS_FILE="$h" _cmeta --plugin-dir "$pd" --command zeta "$f")" "the passed-over row is what ranked first without the name"
}

test_batch_commands () {
    _fixture batch
    local pd out="$TMPDIR_C/batch/out"; pd="$(_pd batch)"
    cp "$TMPDIR_C/batch/in.txt" "$TMPDIR_C/batch/one.txt"
    cp "$TMPDIR_C/batch/in.txt" "$TMPDIR_C/batch/two.txt"
    cp "$TMPDIR_C/batch/in.txt" "$TMPDIR_C/batch/three.txt"
    printf '%s\tbeta\n%s\tzeta\n%s\n' "$TMPDIR_C/batch/one.txt" "$TMPDIR_C/batch/two.txt" "$TMPDIR_C/batch/three.txt" \
        | run_extract --plugin-dir "$pd" --batch --batch-commands --batch-out "$out" -f tsv --max-strategies 1 >/dev/null 2>&1
    assert_eq "beta" "$(awk -F'\t' '/^__EXTRACT_META__/ { print $2 }' "$out/one.meta")" "PATH<TAB>beta"
    assert_eq "cmdtest-generic" "$(awk -F'\t' '/^__EXTRACT_META__/ { print $2 }' "$out/two.meta")" "PATH<TAB>zeta"
    assert_eq "alpha-report" "$(awk -F'\t' '/^__EXTRACT_META__/ { print $2 }' "$out/three.meta")" "a line with no TAB has no name"
    assert_contains "$(cat "$out/one.meta")" "__COMMAND_META__" "the .meta file carries the command line"
    assert_not_contains "$(cat "$out/three.meta")" "__COMMAND_META__" "...not for an input with no name"
}

test_option_errors () {
    local rc=0
    run_extract --command >/dev/null 2>&1 || rc=$?
    assert_exit_nonzero "$rc" "--command needs a name"
    rc=0; printf 'x\n' | run_extract --batch-commands >/dev/null 2>&1 || rc=$?
    assert_exit_nonzero "$rc" "--batch-commands needs --batch"
    rc=0; printf 'x\n' | run_extract --batch --batch-commands --command x >/dev/null 2>&1 || rc=$?
    assert_exit_nonzero "$rc" "--batch-commands and --command conflict"
    assert_eq "aligned-columns" "$(_winner --command=netstat "$CORPUS/netstat-anp.txt")" "--command=NAME form"
}

test_explain_shows_the_command () {
    _fixture explain
    local f="$TMPDIR_C/explain/in.txt" pd out; pd="$(_pd explain)"
    out="$(run_extract explain --plugin-dir "$pd" --command beta "$f" 2>/dev/null)"
    assert_eq "beta" "$(printf '%s\n' "$out" | awk '$1 == "MATCH" { print $2; exit }')" "explain lists the command's ranking"
    assert_contains "$out" "written for 'beta'" "the boost is shown"
    assert_contains "$out" "written for another command" "the margin is shown"
    assert_contains "$out" "Command: 'beta'" "the summary names the command"
}

# PV-037's inputs: pkg-config's shape heuristic claimed these in full mode.
# Piped (no name) and with their command, none is pkg-config's now.
test_pkg_config_no_longer_claims_other_tools () {
    local n w c
    for n in netstat-anp netstat-tulpn ip-br-addr poetry-show gluster-volume-status emacs-version tox-list rabbitmqctl-list-exchanges retroarch-cores; do
        [[ -f "$CORPUS/$n.txt" ]] || { _assert_failed "missing corpus input $n"; continue; }
        w="$(_winner "$CORPUS/$n.txt")"
        assert_not_contains "$w" "pkg-config" "$n (piped): not pkg-config"
        assert_eq "$(_winner --generic "$CORPUS/$n.txt")" "$w" "$n (piped): full mode agrees with --generic"
        c="${n%%-*}"
        assert_not_contains "$(_winner --command "$c" "$CORPUS/$n.txt")" "pkg-config" "$n (--command $c): not pkg-config"
    done
    assert_eq "pkg-config" "$(_winner --no-hints "$SCRIPT_DIR/../samples/pkg-config/basic.txt")" "pkg-config still reads its own sample"
    # pkgconf pads keys to 30 columns: a longer key pushes its own line's second
    # field out of line by one space, and the listing is still pkg-config's
    printf '%s\n' \
        'zlib                           zlib - zlib compression library' \
        'gobject-introspection-no-export-1.0 GObject Introspection - Introspection for the GObject library (uninstalled)' \
        'openssl                        OpenSSL - Secure Sockets Layer and cryptography libraries and tools' \
        'libcurl                        libcurl - Library to transfer files' \
        'glib-2.0                       GLib - C Utility Library' > "$TMPDIR_C/pkgconf.txt"
    assert_eq "pkg-config" "$(_winner --no-hints "$TMPDIR_C/pkgconf.txt")" "pkgconf's layout, with a key longer than its pad"
    # ...but a first field holding a space starts its second word out of line
    printf '%s\n' 'Nestopia UE           Nintendo - NES' 'Snes9x                Nintendo - SNES' \
        'mGBA                  Nintendo - Game Boy Advance' > "$TMPDIR_C/cores.txt"
    assert_not_contains "$(_winner --no-hints "$TMPDIR_C/cores.txt")" "pkg-config" "a two-word first field is not a pkg-config key"
    # and the " - " join is required
    printf '%s\n' 'zlib       zlib compression library' 'openssl    Secure Sockets Layer' 'libcurl    Library to transfer files' > "$TMPDIR_C/nodash.txt"
    assert_not_contains "$(_winner --no-hints "$TMPDIR_C/nodash.txt")" "pkg-config" "no Name - Description join: not pkg-config"
    assert_eq "pkg-config" "$(_winner --no-hints --command pkg-config "$SCRIPT_DIR/../samples/pkg-config/basic.txt")" "...and with its own command"
}

run_test "command: no name ranks by confidence" test_no_command_ranks_by_confidence
run_test "command: a strategy written for the command wins" test_command_for_the_strategy_wins
run_test "command: ## Commands: names siblings" test_commands_header_names_siblings
run_test "command: ## Commands: * is never demoted" test_commands_wildcard_is_never_demoted
run_test "command: another command's strategy needs a margin" test_command_for_another_tool_needs_a_margin
run_test "command: --command-hint only boosts" test_command_hint_only_boosts
run_test "command: relays are ignored" test_relay_is_ignored
run_test "command: the __COMMAND_META__ line" test_command_meta_line
run_test "command: pruning stays exact" test_pruning_exact_with_command
run_test "command: hint rows prefer the command" test_hint_rows_prefer_the_command
run_test "command: --batch-commands" test_batch_commands
run_test "command: option errors" test_option_errors
run_test "command: explain shows the command" test_explain_shows_the_command
run_test "command: pkg-config no longer claims other tools" test_pkg_config_no_longer_claims_other_tools

rm -rf "$TMPDIR_C"
print_summary
