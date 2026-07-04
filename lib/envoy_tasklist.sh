#!/bin/bash
################################################################################
## Envoy Shared Tasklist Parser — envoy_tasklist.sh
##
## Provides core parsing and manipulation functions for .tasklist files.
## These helpers preserve the historical .tasklist data format for tools or
## scenarios that still need to read existing tasklist files.
##
## Sourcing this file is OPTIONAL — every tool can still run standalone.
##
## Requires bash 4.0+.
##
## Tasklist format (v1):
##   - First line:    ## ENVOY:TASKLIST v1
##   - Headers:       ## key<TAB>value  (name, created, author, description)
##   - Params:        ## param<TAB>KEY=VALUE
##   - Separator:     ##
##   - Fields line:   ## Fields: order<TAB>status<TAB>type<TAB>command<TAB>target<TAB>description<TAB>params
##   - Data lines:    7 tab-delimited fields per row
##
## Usage:
##   source "$(dirname "$0")/../lib/envoy_tasklist.sh"
##
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_TASKLIST_LOADED:-}" ]] && return 0
_ENVOY_TASKLIST_LOADED=1

################################################################################
## Constants
################################################################################

readonly _TL_FORMAT_ID="## ENVOY:TASKLIST"
readonly _TL_FORMAT_VERSION="v1"
readonly _TL_FIELD_COUNT=7
readonly _TL_TAB=$'\t'

################################################################################
## read_tasklist
##
## Parses a .tasklist file and populates shell variables describing its
## contents.  After calling, the following variables are set:
##
##   _TL_NAME        — tasklist name
##   _TL_CREATED     — creation timestamp
##   _TL_AUTHOR      — author string
##   _TL_DESCRIPTION — description string
##   _TL_PARAMS      — newline-separated KEY=VALUE param lines
##   _TL_ITEM_COUNT  — number of data items
##   _TL_ITEMS       — newline-separated raw item lines (tab-delimited)
##
## @param  $1  string  Path to .tasklist file
## @return 0 on success, 1 on error
################################################################################

read_tasklist() {
    local file="$1"
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        printf '%s\n' "ERROR: File not found: ${file:-<empty>}" >&2
        return 1
    fi

    # Reset all output variables
    _TL_NAME=""
    _TL_CREATED=""
    _TL_AUTHOR=""
    _TL_DESCRIPTION=""
    _TL_PARAMS=""
    _TL_ITEM_COUNT=0
    _TL_ITEMS=""

    local line first_line_checked=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Verify format identifier on the first line
        if [[ "$first_line_checked" -eq 0 ]]; then
            first_line_checked=1
            if [[ "$line" != "${_TL_FORMAT_ID} ${_TL_FORMAT_VERSION}" ]]; then
                printf '%s\n' "ERROR: Invalid format identifier in $file" >&2
                return 1
            fi
            continue
        fi

        # Skip blank lines
        [[ -z "$line" ]] && continue

        # Parse header lines
        if [[ "$line" == "##"* ]]; then
            # Strip leading "## "
            local hdr="${line#\#\# }"
            # Pure comment separator "##"
            [[ "$hdr" == "$line" ]] && continue
            [[ -z "$hdr" ]] && continue

            # Extract key (everything before first tab)
            local key="${hdr%%${_TL_TAB}*}"
            local val="${hdr#*${_TL_TAB}}"
            # If there was no tab, val == key — treat as no value
            [[ "$val" == "$hdr" ]] && val=""

            case "$key" in
                name)        _TL_NAME="$val" ;;
                created)     _TL_CREATED="$val" ;;
                author)      _TL_AUTHOR="$val" ;;
                description) _TL_DESCRIPTION="$val" ;;
                param)
                    if [[ -z "$_TL_PARAMS" ]]; then
                        _TL_PARAMS="$val"
                    else
                        _TL_PARAMS="${_TL_PARAMS}
${val}"
                    fi
                    ;;
                # Fields: header, other comments — skip
            esac
            continue
        fi

        # Data line
        if [[ -z "$_TL_ITEMS" ]]; then
            _TL_ITEMS="$line"
        else
            _TL_ITEMS="${_TL_ITEMS}
${line}"
        fi
        _TL_ITEM_COUNT=$((_TL_ITEM_COUNT + 1))
    done < "$file"

    return 0
}

################################################################################
## write_tasklist
##
## Writes the current _TL_* variables back to a .tasklist file.
##
## @param  $1  string  Output file path
## @return 0 on success, 1 on error
################################################################################

write_tasklist() {
    local file="$1"
    if [[ -z "$file" ]]; then
        printf '%s\n' "ERROR: Output file path required" >&2
        return 1
    fi

    {
        printf '%s %s\n' "$_TL_FORMAT_ID" "$_TL_FORMAT_VERSION"
        printf '## name\t%s\n' "$_TL_NAME"
        printf '## created\t%s\n' "$_TL_CREATED"
        [[ -n "$_TL_AUTHOR" ]] && printf '## author\t%s\n' "$_TL_AUTHOR"
        [[ -n "$_TL_DESCRIPTION" ]] && printf '## description\t%s\n' "$_TL_DESCRIPTION"

        # Write params
        if [[ -n "$_TL_PARAMS" ]]; then
            local pline
            while IFS= read -r pline; do
                [[ -z "$pline" ]] && continue
                printf '## param\t%s\n' "$pline"
            done <<< "$_TL_PARAMS"
        fi

        printf '##\n'
        printf '## Fields: order\tstatus\ttype\tcommand\ttarget\tdescription\tparams\n'

        # Write data lines
        if [[ -n "$_TL_ITEMS" ]]; then
            local item_line
            while IFS= read -r item_line; do
                [[ -z "$item_line" ]] && continue
                printf '%s\n' "$item_line"
            done <<< "$_TL_ITEMS"
        fi
    } > "$file"

    return 0
}

################################################################################
## expand_params
##
## Replaces ${KEY} template references in a string with values from the
## params section.  Supports multi-pass expansion for nested references.
##
## @param  $1  string  Input string
## @param  $2  string  Params (KEY=VALUE lines, newline-separated).
##                     Defaults to $_TL_PARAMS if omitted.
## @return void (prints expanded string to stdout)
################################################################################

expand_params() {
    local input="$1"
    local params="${2:-$_TL_PARAMS}"
    local result="$input"
    local prev_result line key val
    local max_passes=10
    local pass=0

    # ENV-174: replaced the legacy `sed s/${key}/${escaped_val}/g`
    # pipeline with bash-native string substitution. The previous form
    # interpolated `key` into a sed pattern unescaped, so a param key
    # containing regex metacharacters (`.`, `*`, `[`, `]`, …) corrupted
    # the substitution and could match unintended text. The
    # `escaped_val` pass only escaped `\`, `/`, `&` — newlines and the
    # `;` / `}` / `{` chars in values still broke the sed script.
    # `${result//\${key}/$val}` is a literal substring replacement; no
    # regex interpretation, no escape needed for either side. We still
    # validate `key` against `[A-Za-z_][A-Za-z0-9_]*` so a malformed
    # params line can't degrade into pattern-matching. Bash 5.2 turned
    # on `patsub_replacement` by default, which makes `&` in the
    # replacement expand to the matched substring (sed-style); turn it
    # off locally so values containing `&` remain literal.
    local _psr_was_on=0
    if shopt -q patsub_replacement 2>/dev/null; then
        _psr_was_on=1
        shopt -u patsub_replacement
    fi

    while [[ "$pass" -lt "$max_passes" ]]; do
        prev_result="$result"

        # Substitute from params
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            key="${line%%=*}"
            val="${line#*=}"
            # Reject malformed keys rather than letting them slip
            # through to a literal-matching substitution that may
            # accidentally hit unrelated text.
            if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                continue
            fi
            local needle='${'"$key"'}'
            result="${result//${needle}/$val}"
        done <<< "$params"

        [[ "$result" == "$prev_result" ]] && break
        pass=$((pass + 1))
    done

    [[ "$_psr_was_on" -eq 1 ]] && shopt -s patsub_replacement

    printf '%s\n' "$result"
}

################################################################################
## replace_status
##
## Updates the status field (field 2) of the item with order number N.
##
## @param  $1  string  Path to .tasklist file
## @param  $2  integer Order number of the item to update
## @param  $3  string  New status value
## @return 0 on success, 1 if item not found
################################################################################

replace_status() {
    local file="$1"
    local order="$2"
    local new_status="$3"

    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        printf '%s\n' "ERROR: File not found: ${file:-<empty>}" >&2
        return 1
    fi

    local tmpfile found=0
    tmpfile=$(mktemp "${TMPDIR:-/tmp}/envoy_tl.XXXXXXXXXX")

    while IFS= read -r line; do
        # Preserve comments and blanks
        if [[ "$line" == "#"* ]] || [[ -z "$line" ]]; then
            printf '%s\n' "$line" >> "$tmpfile"
            continue
        fi

        local item_order
        item_order="${line%%${_TL_TAB}*}"
        if [[ "$item_order" == "$order" ]]; then
            found=1
            local f1 f2 f3 f4 f5 f6 f7
            IFS=$'\t' read -r f1 f2 f3 f4 f5 f6 f7 <<< "$line"
            f2="$new_status"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f1" "$f2" "$f3" "$f4" "$f5" "$f6" "$f7" >> "$tmpfile"
        else
            printf '%s\n' "$line" >> "$tmpfile"
        fi
    done < "$file"

    if [[ "$found" -eq 0 ]]; then
        rm -f "$tmpfile"
        printf '%s\n' "ERROR: Item with order $order not found" >&2
        return 1
    fi

    mv "$tmpfile" "$file"
    return 0
}

################################################################################
## get_item_field
##
## Returns a specific field from the item with order number N.
##
## Field names: order(1), status(2), type(3), command(4), target(5),
##              description(6), params(7)
##
## @param  $1  string  Path to .tasklist file
## @param  $2  integer Order number
## @param  $3  string  Field name or number (1-7)
## @return void (prints field value to stdout)
################################################################################

get_item_field() {
    local file="$1"
    local order="$2"
    local field="$3"

    # Resolve field name to number
    local field_num
    case "$field" in
        order|1)       field_num=1 ;;
        status|2)      field_num=2 ;;
        type|3)        field_num=3 ;;
        command|4)     field_num=4 ;;
        target|5)      field_num=5 ;;
        description|6) field_num=6 ;;
        params|7)      field_num=7 ;;
        *)
            printf '%s\n' "ERROR: Unknown field: $field" >&2
            return 1
            ;;
    esac

    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        printf '%s\n' "ERROR: File not found: ${file:-<empty>}" >&2
        return 1
    fi

    local line item_order
    while IFS= read -r line; do
        [[ "$line" == "#"* ]] && continue
        [[ -z "$line" ]] && continue
        item_order="${line%%${_TL_TAB}*}"
        if [[ "$item_order" == "$order" ]]; then
            printf '%s' "$line" | cut -f"$field_num"
            return 0
        fi
    done < "$file"

    # Item not found
    return 1
}

################################################################################
## count_items
##
## Counts the number of data (non-comment, non-blank) lines in a
## .tasklist file.
##
## @param  $1  string  Path to .tasklist file
## @return void (prints integer count to stdout)
################################################################################

count_items() {
    local file="$1"
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        printf '%s\n' "0"
        return 1
    fi
    local count=0 line
    while IFS= read -r line; do
        [[ "$line" == "#"* ]] && continue
        [[ -z "$line" ]] && continue
        count=$((count + 1))
    done < "$file"
    printf '%s\n' "$count"
}
