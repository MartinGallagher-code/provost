#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# ENV-066: enforce that every lib/*.sh module declares the globals it touches
# in a `## Reads:` / `## Writes:` header block. The registry in _globals.sh
# remains authoritative; this static check keeps the headers and the registry
# in sync.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

LIB_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/lib"

# Modules that must declare their contract. _globals.sh is excluded — it IS
# the contract.
_lib_modules () {
    local f
    for f in "$LIB_DIR"/_*.sh; do
        [[ "$(basename "$f")" == "_globals.sh" ]] && continue
        printf '%s\n' "$f"
    done
}

# Collect "## Reads:" + "## Writes:" declared names for a module into a single
# whitespace-separated string. Handles multi-line blocks (continuation lines
# that don't start a new header). Strips trailing notes in parentheses.
_declared_globals () {
    local file="$1"
    awk '
        /^## Reads:/  { inblk=1; sub(/^## Reads:[[:space:]]*/, ""); print; next }
        /^## Writes:/ { inblk=1; sub(/^## Writes:[[:space:]]*/, ""); print; next }
        /^##[[:space:]]+[A-Za-z]/ { inblk=0; next }
        /^##[[:space:]]+[^[:space:]]/ && inblk {
            sub(/^##[[:space:]]+/, "")
            print
            next
        }
        /^##$/ || /^##[[:space:]]*$/ { inblk=0; next }
        /^[^#]/ { exit }
    ' "$file" | tr '()' '  ' | tr -s ' \n' ' '
}

# ENV-128: extract a single header section ("Reads", "Writes", or "Allowlist")
# from the top-of-file comment block, supporting multi-line continuations.
# Returns space-separated names with `(via FN)` annotations preserved so the
# caller can decide whether to accept indirection.
_extract_section () {
    local file="$1" section="$2"
    awk -v want="$section" '
        # Start the wanted section.
        $0 ~ "^## " want ":" {
            inblk=1
            sub("^## " want ":[[:space:]]*", "")
            print
            next
        }
        # Any other top-level header line ends the current block. The
        # `[A-Za-z][A-Za-z0-9_ -]*:` shape requires a trailing colon
        # so a continuation line like `##         COL_MEAN COL_STD`
        # is not mistaken for a new section header.
        /^## [A-Za-z][A-Za-z0-9_ -]*:/ { inblk=0; next }
        # Continuation: indented body line under the active section.
        /^##[[:space:]]+[^[:space:]]/ && inblk {
            sub(/^##[[:space:]]+/, "")
            print
            next
        }
        /^##$/ || /^##[[:space:]]*$/ { inblk=0; next }
        /^[^#]/ { exit }
    ' "$file"
}

# ENV-128: tokenise an `## Reads:` / `## Writes:` block into raw entries,
# preserving `(via FN)` annotations as `NAME(via=FN)`. Convention: a
# `(via FN)` clause applies to every name on the SAME LINE preceding it
# (e.g. `## Writes: ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)`
# tags all four). Names on continuation lines without an annotation are
# treated as direct.
_tokenise_section () {
    local file="$1" section="$2"
    _extract_section "$file" "$section" \
        | awk '
            {
                line = $0
                # First pass: collect names on this line, then look for a
                # `(via FN)` clause to retroactively tag them.
                line_names_n = 0
                tail = line
                while (tail != "") {
                    sub(/^[[:space:]]+/, "", tail)
                    if (tail == "") break
                    if (substr(tail, 1, 1) == "(") {
                        end = index(tail, ")")
                        if (end == 0) break
                        clause = substr(tail, 2, end - 2)
                        tail = substr(tail, end + 1)
                        # Anchor on `via FN` — other prose like
                        # "(function arguments only)" is dropped.
                        if (match(clause, /^[[:space:]]*via[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                            sub(/^[[:space:]]*via[[:space:]]+/, "", clause)
                            sub(/[[:space:]].*$/, "", clause)
                            for (i = 0; i < line_names_n; i++) {
                                line_names[i] = line_names[i] "(via=" clause ")"
                            }
                        }
                        continue
                    }
                    if (match(tail, /^[A-Za-z_][A-Za-z0-9_]*/)) {
                        name = substr(tail, RSTART, RLENGTH)
                        tail = substr(tail, RSTART + RLENGTH)
                        line_names[line_names_n++] = name
                        continue
                    }
                    tail = substr(tail, 2)
                }
                for (i = 0; i < line_names_n; i++) print line_names[i]
            }
        '
}

# ENV-128: extract names from a section, dropping any `(via FN)` annotation.
# Names like "function" or "arguments" that appear in prose like
# "(function arguments only)" still come through here as plain words; the
# caller filters them via _important_names_in_module / _is_important_name.
_section_names () {
    _tokenise_section "$1" "$2" | sed -E 's/\(via=[^)]+\)$//'
}

# ENV-128: look up the via-function for a tokenised name (returns empty if
# the entry has no `(via=FN)` annotation).
_section_via () {
    local entry="$1"
    [[ "$entry" == *"(via="* ]] || { echo ""; return; }
    local rest="${entry#*(via=}"
    echo "${rest%)}"
}

# ENV-128: filter a single name through the same `_important_names_in_module`
# regex so we only enforce the contract on names that look like cross-module
# globals. Names like "function" / "arguments" / "varies" / "none" — common
# inside parenthetical prose in the headers — are dropped here.
_is_important_name () {
    local n="$1"
    [[ "$n" =~ ^(COL_[A-Z_]+|CORR_[A-Z_]+|corr_[a-z_]+|ITEM_[A-Z_]+|NUM_COL_[A-Z_]+|CAT_COL_[A-Z_]+|MAX_[A-Z_]+|SPARK_[A-Z_]+|BENFORD_[A-Z_]+|COLOR_[A-Z_]+|SAMPLE_[A-Z_]+|AWK_[A-Z_]+|threshold_[a-z_]+|cleanup_files|dup_count|ROW_COUNT|COL_COUNT|input_file|delim|VERSION|_NUM_P05|_NUM_Q1|_NUM_P50|_NUM_Q3|_NUM_P95|_STRIP_BOM_RESULT|_CORR_PAIR_LINES|output_format|forced_delim|compare_files|kind_filter|analysis_list|summary_mode)$ ]]
}

# ENV-128: returns 0 if the module body references NAME as a read.
# Recognises:
#   * `$NAME`, `${NAME}`, `${NAME[…]}` — standard parameter expansion
#   * Bare `NAME` inside arithmetic contexts (`(( … ))`, `$(( … ))`,
#     array index `${arr[NAME]}`) — bash dereferences automatically there
#   * Bare `NAME` inside `[[ NAME -gt 0 ]]` and similar
# Excludes references on lines that are pure `local`/`declare` declarations.
_module_reads_name () {
    local file="$1" name="$2"
    # Strip pure local/declare lines first so a function-scoped
    # `local COL_MEAN=...` doesn't masquerade as a global read.
    local body
    body=$(grep -vE "^[[:space:]]*(local|declare|readonly)[[:space:]]+([^=]+[[:space:]])?${name}([[:space:]=]|$)" "$file")
    # Standard $NAME / ${NAME / ${NAME[ forms. Use an explicit boundary
    # class instead of `\b` (busybox grep -E does not support `\b`).
    grep -qE "(\\\$\\{?${name}([^A-Za-z0-9_]|\$)|\\\$\\{${name}\\[)" <<< "$body" && return 0
    # Arithmetic / test contexts where bare NAME is dereferenced. Match a
    # word-boundary occurrence on a line that contains `((` or `[[` to
    # keep the pattern conservative — line-of-code references to a bare
    # identifier elsewhere (e.g. as a command name) shouldn't count.
    # Bracket expressions (`[(]`, `[[]`) keep the line selector portable:
    # busybox grep -E treats `\(` as a group, not a literal paren. `[(][(]`
    # also covers the `((` inside `$((`.
    #
    # Materialise the selected lines into a variable instead of piping
    # `grep … | grep -q`: under `set -o pipefail` the pipe form fails
    # spuriously — `grep -q` exits 0 on first match, the upstream `grep`
    # is killed by SIGPIPE (141), pipefail surfaces 141, and `&& return 0`
    # is skipped, so a referenced name is mis-reported as unreferenced.
    # This is timing-dependent (early matches in long modules trigger it),
    # which made it flake intermittently on Alpine CI. Same fix as
    # _module_writes_name below.
    local arith
    arith=$(grep -E "[(][(]|[[][[]" <<< "$body")
    grep -qE "(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|$)" <<< "$arith" && return 0
    return 1
}

# ENV-128: returns 0 if the module body assigns NAME (`NAME=`, `NAME[…]=`,
# `NAME+=`). Excludes `local NAME=` and `declare NAME=` so function-local
# assignments don't count as global writes.
#
# Implementation note: we materialise the filtered body into a single
# variable before greping for the assignment, instead of `grep -v | grep
# -q`.  Under `set -o pipefail` the latter form FAILS spuriously: `grep
# -q` exits 0 on first match, the upstream `grep -v` is killed by
# SIGPIPE and reports exit 141, pipefail surfaces 141, and the helper
# returns "no assignment found" even when the assignment exists.  CI
# under mawk/bash hit this where local under gawk/bash didn't because
# of buffer-flush timing differences.
_module_writes_name () {
    local file="$1" name="$2" body
    body=$(grep -vE "^[[:space:]]*(local|declare|readonly)[[:space:]]" "$file")
    grep -qE "^[[:space:]]*${name}([[:space:]]*\\+?=|\\[)" <<<"$body"
}

# ENV-128: returns 0 if the module body calls FN (as command word).
_module_calls_fn () {
    local file="$1" fn="$2"
    grep -qE "(^|[[:space:]\\(])${fn}([[:space:]\\(]|$)" "$file"
}

# Names that look like cross-module globals. Non-exhaustive but covers the
# invariants the registry tracks: COL_*, CORR_*, corr_*, ITEM_*, NUM_COL_*,
# CAT_COL_*, MAX_*, SPARK_*, BENFORD_*, COLOR_*, SAMPLE_*, AWK_*,
# threshold_*, cleanup_files, dup_count, ROW_COUNT, COL_COUNT, add_item, input_file, delim, VERSION.
_important_names_in_module () {
    local file="$1"
    # Candidate names: references and assignments of interesting identifiers.
    local candidates
    candidates=$(awk 'body || /^[^#]/ { body=1; print }' "$file" | \
        grep -oE '(\$\{?[A-Za-z_][A-Za-z0-9_]*|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[+]?=|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*\[)' | \
        sed -E 's/^[[:space:]]*//; s/\$\{?//; s/[[:space:]]*\+?=$//; s/\[$//' | \
        grep -E '^(COL_[A-Z_]+|CORR_[A-Z_]+|corr_[a-z_]+|ITEM_[A-Z_]+|NUM_COL_[A-Z_]+|CAT_COL_[A-Z_]+|MAX_[A-Z_]+|SPARK_[A-Z_]+|BENFORD_[A-Z_]+|COLOR_[A-Z_]+|SAMPLE_[A-Z_]+|AWK_[A-Z_]+|threshold_[a-z_]+|cleanup_files|dup_count|ROW_COUNT|COL_COUNT|input_file|delim|VERSION|_NUM_P05|_NUM_Q1|_NUM_P50|_NUM_Q3|_NUM_P95|_STRIP_BOM_RESULT|_CORR_PAIR_LINES|output_format|forced_delim|compare_files)$' | \
        sort -u)
    # Filter out names that are declared `local` somewhere in the file — those
    # are function-scoped and not cross-module globals.
    local name
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if grep -qE "^[[:space:]]*local[[:space:]]+([^=]+[[:space:]])?${name}([[:space:]=]|$)" "$file"; then
            continue
        fi
        printf '%s\n' "$name"
    done <<< "$candidates"
}

# Registry of known cross-module names (authoritative).
_registry_names () {
    # Allowed because the registry explicitly documents them. A tiny permit list
    # to keep the static check from false-failing on things like `COL_UNIQUE`
    # being read inside a for-loop index (it IS declared).
    cat <<'EOF'
COL_TYPE COL_NUMERIC COL_TEXT COL_MEAN COL_STD COL_SKEW COL_KURT COL_MIN COL_MAX COL_UNIQUE COL_MISSING COL_NAMES COL_COUNT
CORR_VALUES corr_cols corr_names _CORR_PAIR_LINES
ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS
NUM_COL_INDEXES NUM_COL_NAMES CAT_COL_INDEXES CAT_COL_NAMES
MAX_CORR_COLS MAX_GROUP_UNIQUE MAX_GROUPS MAX_GROUP_NUM_COLS
SPARK_SAMPLES
BENFORD_CRIT BENFORD_ALPHA
COLOR_ENABLED
SAMPLE_NOTE
AWK_ISMISSING
threshold_specs threshold_exit_code
cleanup_files dup_count
ROW_COUNT input_file delim forced_delim output_format compare_files
VERSION
_NUM_P05 _NUM_Q1 _NUM_P50 _NUM_Q3 _NUM_P95
_STRIP_BOM_RESULT
add_item
EOF
}

test_each_module_has_contract_headers () {
    local f
    while IFS= read -r f; do
        if ! grep -q '^## Reads:' "$f"; then
            echo "  ASSERT FAILED: $(basename "$f") missing '## Reads:' header"
            return 1
        fi
        if ! grep -q '^## Writes:' "$f"; then
            echo "  ASSERT FAILED: $(basename "$f") missing '## Writes:' header"
            return 1
        fi
    done < <(_lib_modules)
}

test_all_referenced_globals_in_registry () {
    # For each module: everything it references (of the important-name class)
    # should appear in the module's own Reads/Writes OR the registry.
    local registry
    registry="$(_registry_names | tr '\n' ' ')"
    local f failures=0
    while IFS= read -r f; do
        local declared
        declared="$(_declared_globals "$f" | tr '()' '  ' | tr -s ' ')"
        local name
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            # Registry check (authoritative)
            if [[ " $registry " == *" $name "* ]]; then
                continue
            fi
            # Module-declared fallback
            if [[ " $declared " == *" $name "* ]]; then
                continue
            fi
            echo "  ASSERT FAILED: $(basename "$f") touches undeclared global '$name'"
            failures=$((failures+1))
        done < <(_important_names_in_module "$f")
    done < <(_lib_modules)
    [[ $failures -eq 0 ]] || return 1
}

# ENV-128: every name listed under `## Reads:` must actually be referenced
# in the module body. Catches stale entries and typos in the header (e.g.
# declared `COL_MEAN` while the body reads `COL_MEANS`).
test_declared_reads_referenced () {
    local f failures=0
    while IFS= read -r f; do
        local entry name via
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            name="${entry%%(*}"
            via=$(_section_via "$entry")
            _is_important_name "$name" || continue
            if [[ -n "$via" ]]; then
                # Annotated `(via FN)`: indirection is allowed iff the
                # module actually calls FN.
                if ! _module_calls_fn "$f" "$via"; then
                    echo "  ASSERT FAILED: $(basename "$f") declares '## Reads: $name (via $via)' but doesn't call $via"
                    failures=$((failures+1))
                fi
                continue
            fi
            if ! _module_reads_name "$f" "$name"; then
                echo "  ASSERT FAILED: $(basename "$f") declares '## Reads: $name' but doesn't reference \$$name"
                failures=$((failures+1))
            fi
        done < <(_tokenise_section "$f" "Reads")
    done < <(_lib_modules)
    [[ $failures -eq 0 ]] || return 1
}

# ENV-128: every name listed under `## Writes:` must actually be assigned in
# the module body, OR be reachable through a `(via FN)` indirection. Catches
# typos like `## Writes: dup_count` while the body writes to `dup_counts`.
test_declared_writes_assigned () {
    local f failures=0
    while IFS= read -r f; do
        local entry name via
        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue
            name="${entry%%(*}"
            via=$(_section_via "$entry")
            _is_important_name "$name" || continue
            if [[ -n "$via" ]]; then
                if ! _module_calls_fn "$f" "$via"; then
                    echo "  ASSERT FAILED: $(basename "$f") declares '## Writes: $name (via $via)' but doesn't call $via"
                    failures=$((failures+1))
                fi
                continue
            fi
            if ! _module_writes_name "$f" "$name"; then
                echo "  ASSERT FAILED: $(basename "$f") declares '## Writes: $name' but doesn't assign $name"
                failures=$((failures+1))
            fi
        done < <(_tokenise_section "$f" "Writes")
    done < <(_lib_modules)
    [[ $failures -eq 0 ]] || return 1
}

# ENV-128: union of all module Reads/Writes must be a subset of the registry
# in lib/_globals.sh. Adding a new cross-module global without registering
# it is now a hard failure.
test_registry_completeness () {
    local registry_text
    registry_text=$(< "$LIB_DIR/_globals.sh")
    local f entry name failures=0
    while IFS= read -r f; do
        local section
        for section in Reads Writes; do
            while IFS= read -r entry; do
                [[ -z "$entry" ]] && continue
                name="${entry%%(*}"
                _is_important_name "$name" || continue
                # The registry comments names like `# COL_MEAN=()` or
                # mentions them in prose. A simple word-boundary substring
                # check is enough — false matches against random comment
                # text cost nothing here.
                if ! grep -qE "(^|[^A-Za-z0-9_])${name}([^A-Za-z0-9_]|$)" "$LIB_DIR/_globals.sh"; then
                    echo "  ASSERT FAILED: $(basename "$f") $section: '$name' is not listed in lib/_globals.sh"
                    failures=$((failures+1))
                fi
            done < <(_tokenise_section "$f" "$section")
        done
    done < <(_lib_modules)
    [[ $failures -eq 0 ]] || return 1
}

# ENV-128 sabotage test: drop a copy of a real module into a tempdir with a
# deliberate Reads/Writes mismatch and confirm the new assertions fail with
# a useful message. Pins the contract end-to-end so a future `s/COL_MEAN/-/`
# refactor can't quietly weaken the check.
test_sabotage_typo_detected () {
    local tmpd
    tmpd=$(mktemp -d "${TMPDIR:-/tmp}/env128_sabotage.XXXXXX")
    # Use _correlation.sh as the victim — it has a rich Reads list with
    # COL_MEAN, so renaming it to COL_MEANS in the body simulates the
    # exact typo class the ticket calls out.
    cp "$LIB_DIR/_correlation.sh" "$tmpd/_correlation.sh"
    sed -i 's/\$COL_MEAN\b/$COL_MEANS/g; s/\${COL_MEAN\b/${COL_MEANS/g' "$tmpd/_correlation.sh"

    # Run the per-name read check against just the sabotaged copy. We
    # inline the loop body rather than override `_lib_modules` because
    # the existing function declarations are seen by the test runner's
    # subshell only after this test function definition was parsed —
    # function-level overrides in a subshell don't propagate across the
    # call boundary the way `local -n` would.
    local out=""
    local entry name via
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        name="${entry%%(*}"
        via=$(_section_via "$entry")
        _is_important_name "$name" || continue
        if [[ -n "$via" ]]; then
            _module_calls_fn "$tmpd/_correlation.sh" "$via" || \
                out+="declares '## Reads: $name (via $via)' but doesn't call $via in $tmpd/_correlation.sh"$'\n'
            continue
        fi
        if ! _module_reads_name "$tmpd/_correlation.sh" "$name"; then
            out+="$(basename "$tmpd/_correlation.sh") declares '## Reads: $name' but doesn't reference \$$name"$'\n'
        fi
    done < <(_tokenise_section "$tmpd/_correlation.sh" "Reads")

    rm -rf "$tmpd"

    if [[ "$out" != *"COL_MEAN"* ]]; then
        echo "  ASSERT FAILED: sabotage test did not flag the COL_MEAN/COL_MEANS swap"
        echo "    test output: $out"
        return 1
    fi
    if [[ "$out" != *"_correlation.sh"* ]]; then
        echo "  ASSERT FAILED: sabotage error message must name the offending file"
        echo "    test output: $out"
        return 1
    fi
}

test_registry_file_exists () {
    [[ -f "$LIB_DIR/_globals.sh" ]] || {
        echo "  ASSERT FAILED: _globals.sh missing"
        return 1
    }
    grep -q 'Global Variable Registry' "$LIB_DIR/_globals.sh" || {
        echo "  ASSERT FAILED: _globals.sh lacks registry header"
        return 1
    }
}

################################################################################
## ENV-123: standalone awk programs in lib/awk/ must pass `awk -W lint`
##
## The `_numeric_combined_awk` body was extracted to
## `lib/awk/numeric_combined.awk` so editors and lint can see it. This
## test gates the file against gawk's `--lint` so any future edit that
## introduces an uninitialized read or untyped for-loop is caught at CI
## time rather than on first column-with-no-data.
################################################################################

test_awk_files_pass_lint () {
    local awk_dir="$LIB_DIR/awk"
    if [[ ! -d "$awk_dir" ]]; then
        # No standalone awk programs yet — vacuously pass.
        return 0
    fi
    # gawk-only check; if /usr/bin/awk is mawk or similar, skip cleanly.
    # Materialised (no `| grep -q` under pipefail — see _module_reads_name).
    local awk_version
    awk_version=$(awk --version 2>&1 || true)
    if ! grep -qiE "^GNU Awk|^awk version.*GNU" <<< "$awk_version"; then
        echo "  (skipping: gawk not available — using ${awk_version%%$'\n'*})"
        return 0
    fi
    local f rc=0
    for f in "$awk_dir"/*.awk; do
        [[ -f "$f" ]] || continue
        local out
        # Pass dummy values for every -v that the program uses, so lint
        # doesn't flag the parameters as uninitialized. The program itself
        # is responsible for initialising any other variables in BEGIN.
        # Filter out gawk's `data file '-' is empty` notice — that warns
        # only that we passed `</dev/null` to satisfy the data-file slot,
        # which has no bearing on the script's lint-cleanliness.
        out=$(awk -W lint \
            -v col=1 -v mn=0 -v mx=1 -v mean=0 -v std=1 \
            -v skip=1 -v maxn=10 -v tmpfile=/dev/null \
            -v benford_crit=15.507 \
            -f "$f" </dev/null 2>&1 >/dev/null \
            | grep -vE "warning: data file \`-' is empty" || true)
        if [[ -n "$out" ]]; then
            echo "  ASSERT FAILED: $(basename "$f") emits lint warnings:"
            printf '    %s\n' "$out"
            rc=1
        fi
    done
    return $rc
}

run_test "ENV-066 every lib/*.sh has Reads:/Writes: header" test_each_module_has_contract_headers
run_test "ENV-066 referenced globals are in registry or declared" test_all_referenced_globals_in_registry
run_test "ENV-066 _globals.sh registry exists" test_registry_file_exists
run_test "ENV-128 declared Reads names are referenced in body" test_declared_reads_referenced
run_test "ENV-128 declared Writes names are assigned in body" test_declared_writes_assigned
run_test "ENV-128 module Reads/Writes are listed in lib/_globals.sh" test_registry_completeness
run_test "ENV-128 sabotage: COL_MEAN -> COL_MEANS typo detected" test_sabotage_typo_detected
run_test "ENV-123 standalone awk files pass gawk --lint" test_awk_files_pass_lint

print_summary
