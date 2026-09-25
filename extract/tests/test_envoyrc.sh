#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Security tests: the .envoyrc config layer (lib/envoy_envoyrc.sh)
##
## A .envoyrc can sit in any checkout the user cds into, so the loader must
## treat it as untrusted: LD_PRELOAD (and friends) from a .envoyrc once reached
## every child process the engine spawned. These tests pin the fixes:
##   - only ENVOY_* / MFE_* / PROVOST_* keys are exported, a deny list wins;
##   - ENVOY_NO_RC=1 disables the layer;
##   - the upward walk never passes $HOME (outside $HOME: $PWD only);
##   - files not owned by the user, or group/world-writable, are skipped.
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

RC_LIB="$(cd "$SCRIPT_DIR/../.." && pwd)/lib/envoy_envoyrc.sh"

echo ""
echo "========================================"
echo "Security Tests: .envoyrc loader"
echo "========================================"

_RC_TMP="$(mktemp -d "${TMPDIR:-/tmp}/envoyrc-test.XXXXXX")"
trap 'rm -rf "$_RC_TMP"' EXIT

# _rc_env <home> <cwd> [VAR=val...] -> the environment a child process sees
# after envoy_envoyrc_load ran in <cwd> with HOME=<home>.
_rc_env () {
    local home="$1" cwd="$2"; shift 2
    ( cd "$cwd" && env -i PATH="$PATH" HOME="$home" XDG_CONFIG_HOME="$home/.config" "$@" \
        bash -c 'source "$1"; envoy_envoyrc_load; env' _ "$RC_LIB" 2>/dev/null )
}

_mkrc () { # <file> <content>
    mkdir -p "$(dirname "$1")"
    printf '%s\n' "$2" > "$1"
    chmod 600 "$1"
}

test_ld_preload_ignored () {
    local home="$_RC_TMP/h1" proj="$_RC_TMP/h1/proj"
    _mkrc "$proj/.envoyrc" 'LD_PRELOAD=/nonexistent/evil.so
LD_LIBRARY_PATH=/nonexistent
BASH_ENV=/nonexistent/evil.sh
PATH=/evil/bin
IFS=x
PS4=$(evil)
SHELLOPTS=xtrace
MFE_RC_TEST=allowed'
    local out; out="$(_rc_env "$home" "$proj")"
    assert_not_contains "$out" "LD_PRELOAD=" "LD_PRELOAD from .envoyrc must not reach children"
    assert_not_contains "$out" "LD_LIBRARY_PATH=" "LD_LIBRARY_PATH must be denied"
    assert_not_contains "$out" "BASH_ENV=" "BASH_ENV must be denied"
    assert_not_contains "$out" "PATH=/evil/bin" "PATH must be denied"
    assert_not_contains "$out" "SHELLOPTS=xtrace" "SHELLOPTS must be denied"
    assert_contains "$out" "MFE_RC_TEST=allowed" "an MFE_ key is still loaded"
}

test_ld_preload_ignored_by_engine () {
    # End to end: the engine run from inside the checkout must not hand
    # LD_PRELOAD to its children (the dynamic linker would complain on every
    # spawned process if it did).
    local home="$_RC_TMP/h2" proj="$_RC_TMP/h2/proj"
    _mkrc "$proj/.envoyrc" 'LD_PRELOAD=/nonexistent/evil-provost-test.so'
    printf 'a: 1\nb: 2\n' > "$proj/in.txt"
    local err
    err="$( cd "$proj" && HOME="$home" XDG_CONFIG_HOME="$home/.config" \
        bash "$MFE_SCRIPT" -f plain in.txt 2>&1 >/dev/null )"
    assert_not_contains "$err" "evil-provost-test.so" "engine children must not see LD_PRELOAD"
}

test_prefix_allow_list () {
    local home="$_RC_TMP/h3" proj="$_RC_TMP/h3/p"
    _mkrc "$proj/.envoyrc" 'ENVOY_RC_A=1
MFE_RC_B=2
PROVOST_RC_C=3
RANDOM_RC_D=4
EDITOR=evil'
    local out; out="$(_rc_env "$home" "$proj")"
    assert_contains "$out" "ENVOY_RC_A=1" "ENVOY_ prefix allowed"
    assert_contains "$out" "MFE_RC_B=2" "MFE_ prefix allowed"
    assert_contains "$out" "PROVOST_RC_C=3" "PROVOST_ prefix allowed"
    assert_not_contains "$out" "RANDOM_RC_D=" "unprefixed key rejected"
    assert_not_contains "$out" "EDITOR=evil" "unprefixed key rejected"
}

test_no_rc_opt_out () {
    local home="$_RC_TMP/h4" proj="$_RC_TMP/h4/p"
    _mkrc "$proj/.envoyrc" 'MFE_RC_OPTOUT=loaded'
    local out; out="$(_rc_env "$home" "$proj" ENVOY_NO_RC=1)"
    assert_not_contains "$out" "MFE_RC_OPTOUT=" "ENVOY_NO_RC=1 must skip every file"
}

test_writable_file_skipped () {
    local home="$_RC_TMP/h5" proj="$_RC_TMP/h5/p"
    _mkrc "$proj/.envoyrc" 'MFE_RC_WW=loaded'
    chmod 666 "$proj/.envoyrc"
    local out; out="$(_rc_env "$home" "$proj")"
    assert_not_contains "$out" "MFE_RC_WW=" "a world-writable .envoyrc is skipped"
    chmod 620 "$proj/.envoyrc"
    out="$(_rc_env "$home" "$proj")"
    assert_not_contains "$out" "MFE_RC_WW=" "a group-writable .envoyrc is skipped"
    chmod 600 "$proj/.envoyrc"
    out="$(_rc_env "$home" "$proj")"
    assert_contains "$out" "MFE_RC_WW=loaded" "a private .envoyrc is loaded"
}

test_walk_stops_at_home () {
    # A .envoyrc ABOVE $HOME is never read; one between $PWD and $HOME is.
    local top="$_RC_TMP/w" home="$_RC_TMP/w/home" proj="$_RC_TMP/w/home/a/b"
    _mkrc "$top/.envoyrc" 'MFE_RC_ABOVE=leaked'
    _mkrc "$home/a/.envoyrc" 'MFE_RC_BETWEEN=ok'
    mkdir -p "$proj"
    local out; out="$(_rc_env "$home" "$proj")"
    assert_not_contains "$out" "MFE_RC_ABOVE=" "walk must not pass \$HOME"
    assert_contains "$out" "MFE_RC_BETWEEN=ok" "ancestors below \$HOME are read"
}

test_outside_home_pwd_only () {
    # Outside $HOME there is no boundary: only $PWD/.envoyrc is considered.
    local home="$_RC_TMP/o/home" parent="$_RC_TMP/o/srv" proj="$_RC_TMP/o/srv/repo"
    mkdir -p "$home"
    _mkrc "$parent/.envoyrc" 'MFE_RC_PARENT=leaked'
    _mkrc "$proj/.envoyrc" 'MFE_RC_HERE=ok'
    local out; out="$(_rc_env "$home" "$proj")"
    assert_not_contains "$out" "MFE_RC_PARENT=" "outside \$HOME, parents are not walked"
    assert_contains "$out" "MFE_RC_HERE=ok" "outside \$HOME, \$PWD/.envoyrc still applies"
}

run_test "envoyrc: LD_PRELOAD and other dangerous keys are ignored" test_ld_preload_ignored
run_test "envoyrc: engine children never see LD_PRELOAD from .envoyrc" test_ld_preload_ignored_by_engine
run_test "envoyrc: only ENVOY_/MFE_/PROVOST_ keys are exported" test_prefix_allow_list
run_test "envoyrc: ENVOY_NO_RC=1 disables the layer" test_no_rc_opt_out
run_test "envoyrc: group/world-writable files are skipped" test_writable_file_skipped
run_test "envoyrc: upward walk stops at \$HOME" test_walk_stops_at_home
run_test "envoyrc: outside \$HOME only \$PWD/.envoyrc is read" test_outside_home_pwd_only

print_summary
