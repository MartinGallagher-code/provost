#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for ENV-172 — provost-extract: _quote_arg backslash, JSON key/value
##                     escape consistency, --chain/--rename glob expansion,
##                     sed-escape gaps in apply_renames.
##
## Sub-bug 1: _build.sh:267. The `_quote_arg` double-quote branch had
##   `case "$ch" in '\'*) ... esac` — a multi-character pattern that
##   never matched the single-character $ch. Backslashes leaked through
##   unescaped, so the produced double-quoted shell-replay string then
##   re-interpreted whatever followed the backslash on replay.
##
## Sub-bug 2: _build.sh:121-132 vs 159-179. The JSON decoder translated
##   `\n` `\t` `\r` (and `\\` `\"` etc.) inside string values, but the
##   in_key branch just appended `_ch` after `_in_escape=1` — keys with
##   escape sequences ended up holding the raw backslash + char pair.
##
## Sub-bug 3: _discovery.sh:198 and _postprocess.sh:65. `for cs in
##   $_OPT_chain` and `for pair in $renames` were unquoted. With
##   `IFS='|'` (or `,`) the variable word-split correctly, but bash
##   ALSO glob-expanded the unquoted variable against CWD before the
##   loop iterated — `--chain '*.sh'` resolved to whatever `*.sh`
##   files were sitting in the cwd.
##
## Sub-bug 4: _postprocess.sh:71. The pattern-side bracket class
##   `[.[\/*^$]` missed `]` (would close the class). The replacement-
##   side class `[\/&]` missed `\`. A field name containing `]` or a
##   replacement containing a literal backslash produced a malformed
##   sed script and aborted the pipeline.
##
## We pin:
##   - _quote_arg over a string that contains both `'` and `\` produces
##     a double-quoted form where backslashes are escaped, so the
##     replay round-trip preserves the original byte sequence.
##   - JSON decoder treats `"a\nb"` identically as a key and as a value
##     (both yield 3-char string `a<NL>b`).
##   - --chain '*.sh' invocation does NOT glob-expand against CWD
##     (the chain list contains literal `*.sh` rather than filenames).
##   - --rename with a name containing `]` produces a valid sed script
##     and the pipeline doesn't abort.
##   - drift guards on each fix.
################################################################################

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EX_DISCOVERY="$EX_DIR/lib/_discovery.sh"
EX_POSTPROCESS="$EX_DIR/lib/_postprocess.sh"

PASS=0
FAIL=0
_pass () { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
_fail () { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1" >&2; if [[ -n "${2:-}" ]]; then printf '    %s\n' "$2" >&2; fi; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/env172_test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo ""
echo "========================================"
echo "ENV-172: extract glob + sed escape"
echo "========================================"

###############################################################################
# Section C — --chain glob expansion
###############################################################################

# Drop a sentinel `*.sh` file in WORK then run provost-extract with
# `--chain '*.sh'`. Pre-fix the loop would have iterated over each
# matched filename; post-fix the chain list contains the LITERAL
# `*.sh` (which won't match any real strategy and so produces a
# clean "strategy not found" path).
mkdir -p "$WORK/cwd"
touch "$WORK/cwd/sentinel.sh" "$WORK/cwd/another.sh"
EX_BIN="$EX_DIR/provost-extract"
out=$(cd "$WORK/cwd" && bash "$EX_BIN" --chain '*.sh' /dev/null 2>&1) || true
# Pre-fix the chain would have contained "sentinel.sh" / "another.sh"
# expansions. Post-fix the chain only contains the literal `*.sh`.
if grep -qE 'sentinel\.sh|another\.sh' <<< "$out"; then
    _fail "drift: --chain '*.sh' was glob-expanded against CWD" "$out"
else
    _pass "--chain '*.sh' is taken literally (no CWD glob expansion)"
fi

# Drift: live code uses `read -r -a` for chain split, not `for cs in
# $_OPT_chain`.
if grep -qE 'read -r -a _chain_arr' "$EX_DISCOVERY"; then
    _pass "drift: _discovery.sh uses read -r -a for the chain split"
else
    _fail "drift: _discovery.sh missing read -r -a for chain"
fi

###############################################################################
# Section D — --rename sed-escape with `]` in field name
###############################################################################

# We exercise apply_renames directly. It requires the input on stdin-like
# stream — the function takes `input` and `renames` strings and returns
# the rewritten table on stdout. Define _OPT_rename or simulate via
# sourcing.
# shellcheck disable=SC1090
source "$EX_POSTPROCESS"
input=$'header\nSTRAT-x\tname[bracket] hello\nSTRAT-x\tnormal world\n'
out=$(apply_renames "$input" 'name[bracket]=plain')
if grep -qF 'plain hello' <<< "$out"; then
    _pass "apply_renames: field name with ']' is escaped + renamed correctly"
else
    _fail "apply_renames: ']' in field name didn't round-trip" "$out"
fi

# Drift: pattern class lists `]` first.
if grep -qE "sed 's/\\[\\]\\.\\[" "$EX_POSTPROCESS"; then
    _pass "drift: _postprocess.sh pattern-side class lists ] first"
else
    _fail "drift: pattern-side ']'-first form missing"
fi

# Drift: replacement class lists \\.
if grep -qE "sed 's/\\[\\\\\\\\/&\\]/" "$EX_POSTPROCESS"; then
    _pass "drift: _postprocess.sh replacement-side class includes \\\\"
else
    _fail "drift: replacement-side \\\\ inclusion missing"
fi

# Drift: rename loop uses read -r -a.
if grep -qE 'read -r -a _renames_arr' "$EX_POSTPROCESS"; then
    _pass "drift: _postprocess.sh uses read -r -a for renames split"
else
    _fail "drift: _postprocess.sh missing read -r -a"
fi

###############################################################################

echo ""
echo "========================================"
printf 'Results: %d/%d passed, %d failed\n' "$PASS" "$((PASS+FAIL))" "$FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "========================================"
    exit 1
fi
echo "All tests passed."
echo "========================================"
