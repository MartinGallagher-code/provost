#!/bin/bash
## Name: yaml
## Description: Extract key/value pairs from YAML, flattening nested keys with dot notation
## Version: 1.1
## Priority: 12
## Sample: samples/yaml/basic.yaml

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _STRATEGY_CONFIDENCE_REASON="key: value pattern with indented sub-keys"

    # Must have YAML key pattern: lines starting with word chars followed by colon
    [[ "$text" =~ (^|$'\n')[a-zA-Z][a-zA-Z0-9_-]*: ]] || return 1

    # Must NOT look like JSON (starts with { or [)
    _is_json "$1" && return 1

    # Repeated top-level keys mean a multi-record output, not a single YAML
    # mapping — leave it to the dedicated record strategy (see _has_repeated_top_keys).
    _has_repeated_top_keys "$text" && return 1

    # Require a strong majority of non-blank lines to be YAML-shaped — a `key:`
    # mapping, a `- ` list item, or a `---` document marker. This stops yaml from
    # claiming whitespace-columnar output that merely happens to have a
    # colon-bearing line (e.g. `free` with its `Mem:`/`Swap:` rows, or `sensors`
    # with an `Adapter:` line), which it would otherwise collapse to one record.
    local nonblank=0 yamlish=0 _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        # A key must start with a LETTER, matching the overall gate above — a
        # purely-numeric label before the colon (`/proc/interrupts`' IRQ rows:
        # `0:`, `16:`) is a table row label, not a YAML key, and would otherwise
        # inflate the yamlish ratio enough to hijack non-YAML numeric tables.
        if [[ "$_l" =~ ^[[:space:]]*[A-Za-z][A-Za-z0-9_.-]*:([[:space:]]|$) ]] \
           || [[ "$_l" =~ ^[[:space:]]*-[[:space:]] ]] \
           || [[ "$_l" == "---"* ]]; then
            yamlish=$((yamlish + 1))
        fi
    done <<< "$text"
    [[ $nonblank -eq 0 ]] && return 1
    [[ $(( yamlish * 100 / nonblank )) -ge 80 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    local result=""
    # Key stack as indexed array
    local stack_keys=""
    local stack_size=0
    # Array index tracking: stack of counters per depth
    local array_counters=""
    local prev_depth=-1

    # Block scalar state
    local in_block=0
    local block_key=""
    local block_style=""
    local block_min_indent=0
    local block_val=""

    while IFS= read -r line; do
        # Handle block scalar accumulation
        if [[ $in_block -eq 1 ]]; then
            # Empty lines are part of the block (literal style preserves them)
            if [[ -z "$line" ]]; then
                if [[ "$block_style" == "|"* ]]; then
                    block_val+="_"
                fi
                continue
            fi

            # Calculate line indent
            local bl_stripped
            bl_stripped="${line#"${line%%[! ]*}"}"
            local bl_indent=${#line}
            bl_indent=$((bl_indent - ${#bl_stripped}))

            if [[ $bl_indent -ge $block_min_indent ]]; then
                # Still in block - accumulate
                local bl_content="$bl_stripped"
                while [[ "$bl_content" == " "* || "$bl_content" == "	"* ]]; do bl_content="${bl_content#?}"; done
                while [[ "$bl_content" == *" " || "$bl_content" == *"	" ]]; do bl_content="${bl_content%?}"; done
                if [[ -n "$block_val" ]]; then
                    if [[ "$block_style" == "|"* ]]; then
                        # Literal: join with underscores (representing newlines)
                        block_val+="_${bl_content}"
                    else
                        # Folded: join with spaces (then underscores for storage)
                        block_val+="_${bl_content}"
                    fi
                else
                    block_val="$bl_content"
                fi
                continue
            fi

            # Block ended - emit accumulated value
            if [[ -n "$block_val" ]]; then
                result+="${block_key} ${block_val}"$'\n'
            fi
            in_block=0
            block_val=""
            # Fall through to process current line normally
        fi

        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines
        case "$line" in
            '#'*) continue ;;
        esac

        # Skip document markers
        [[ "$line" == "---" ]] && continue
        [[ "$line" == "..." ]] && continue

        # Calculate indentation depth (each level = 2 spaces)
        local stripped
        stripped="${line#"${line%%[! ]*}"}"
        local indent=${#line}
        indent=$((indent - ${#stripped}))
        local depth=$((indent / 2))

        # Check if this is an array entry (- item)
        local is_array=0
        local array_value=""
        if [[ "$stripped" == "- "* || "$stripped" == "-	"* ]]; then
            is_array=1
            array_value="${stripped#- }"
            if [[ "$array_value" == "$stripped" ]]; then
                array_value="${stripped#-	}"
            fi
        fi

        if [[ $is_array -eq 1 ]]; then
            # Array entry: use parent key with numeric index
            local counter
            _strat_yaml_get_counter "$depth"
            local counter="$_YAML_COUNTER"
            _strat_yaml_set_counter "$depth" $((counter + 1))

            local full_key
            _strat_yaml_build_key "$depth"
            full_key="${_YAML_KEY}.${counter}"

            local clean_val="$array_value"
            while [[ "$clean_val" == " "* || "$clean_val" == "	"* ]]; do clean_val="${clean_val#?}"; done
            while [[ "$clean_val" == *" " || "$clean_val" == *"	" ]]; do clean_val="${clean_val%?}"; done
            if [[ -n "$clean_val" ]]; then
                result+="${full_key} ${clean_val}"$'\n'
            fi
            continue
        fi

        # Check for key: value or bare key:
        local key value
        if [[ "$stripped" =~ ^[a-zA-Z][a-zA-Z0-9_-]*: ]]; then
            key="${stripped%%:*}"
            # Get everything after "key:"
            local after_colon="${stripped#*:}"
            if [[ -z "$after_colon" ]]; then
                value=""
            else
                # Trim leading whitespace
                while [[ "$after_colon" == " "* || "$after_colon" == "	"* ]]; do after_colon="${after_colon#?}"; done
                value="$after_colon"
            fi
        else
            continue
        fi

        # Update the key stack: trim stack to current depth
        _strat_yaml_set_stack "$depth" "$key"

        # Reset array counters for deeper levels when we move to a new key
        _strat_yaml_reset_counters_above "$depth"

        if [[ "$value" == "|" || "$value" == ">" || "$value" == "|+" || "$value" == ">+" || "$value" == "|-" || "$value" == ">-" ]]; then
            # Block scalar: start collecting subsequent indented lines
            in_block=1
            block_style="$value"
            block_min_indent=$((indent + 2))
            block_val=""

            local full_key
            _strat_yaml_build_key "$((depth + 1))"
            full_key="$_YAML_KEY"
            block_key="${full_key// /_}"
        elif [[ -n "$value" ]]; then
            # Emit the full dotted key path with value
            local full_key
            _strat_yaml_build_key "$((depth + 1))"
            full_key="$_YAML_KEY"
            local clean_val="$value"
            while [[ "$clean_val" == " "* || "$clean_val" == "	"* ]]; do clean_val="${clean_val#?}"; done
            while [[ "$clean_val" == *" " || "$clean_val" == *"	" ]]; do clean_val="${clean_val%?}"; done
            local clean_key="${full_key// /_}"
            result+="${clean_key} ${clean_val}"$'\n'
        fi

        prev_depth=$depth
    done <<< "$text"

    # Emit any remaining block scalar
    if [[ $in_block -eq 1 && -n "$block_val" ]]; then
        result+="${block_key} ${block_val}"$'\n'
    fi

    # A single indexed list-of-records (amtool `Peers`, avro-style `fields`)
    # explodes to one tidy row per element with the scalar keys repeated.
    printf '%s' "$result" | _list_explode
}

# Helper: get array counter for a given depth. Result in _YAML_COUNTER.
_strat_yaml_get_counter () {
    local depth="$1"
    local i=0
    local val=""
    local IFS_OLD="$IFS"
    IFS="|"
    for val in $array_counters; do
        if [[ $i -eq $depth ]]; then
            IFS="$IFS_OLD"
            _YAML_COUNTER="${val:-0}"
            return
        fi
        i=$((i + 1))
    done
    IFS="$IFS_OLD"
    _YAML_COUNTER="0"
}

# Helper: set array counter for a given depth
_strat_yaml_set_counter () {
    local depth="$1"
    local new_val="$2"
    local new_counters=""
    local i=0
    local IFS_OLD="$IFS"

    # Ensure we have enough slots
    local max=$((depth + 1))
    local current_size=0
    IFS="|"
    for val in $array_counters; do
        current_size=$((current_size + 1))
    done
    IFS="$IFS_OLD"

    # Rebuild with updated value
    IFS="|"
    local found=0
    i=0
    for val in $array_counters; do
        if [[ $i -eq $depth ]]; then
            val="$new_val"
            found=1
        fi
        if [[ -z "$new_counters" ]]; then
            new_counters="$val"
        else
            new_counters="${new_counters}|${val}"
        fi
        i=$((i + 1))
    done
    IFS="$IFS_OLD"

    # If depth wasn't reached, pad with zeros and add
    while [[ $i -lt $depth ]]; do
        if [[ -z "$new_counters" ]]; then
            new_counters="0"
        else
            new_counters="${new_counters}|0"
        fi
        i=$((i + 1))
    done
    if [[ $found -eq 0 ]]; then
        if [[ -z "$new_counters" ]]; then
            new_counters="$new_val"
        else
            new_counters="${new_counters}|${new_val}"
        fi
    fi

    array_counters="$new_counters"
}

# Helper: reset array counters above a given depth
_strat_yaml_reset_counters_above () {
    local depth="$1"
    local new_counters=""
    local i=0
    local IFS_OLD="$IFS"
    IFS="|"
    for val in $array_counters; do
        if [[ $i -gt $depth ]]; then
            val="0"
        fi
        if [[ -z "$new_counters" ]]; then
            new_counters="$val"
        else
            new_counters="${new_counters}|${val}"
        fi
        i=$((i + 1))
    done
    IFS="$IFS_OLD"
    array_counters="$new_counters"
}

# Helper: set stack key at a given depth, truncating deeper entries
_strat_yaml_set_stack () {
    local depth="$1"
    local key="$2"
    local new_stack=""
    local i=0
    local IFS_OLD="$IFS"

    # Copy existing entries up to depth
    IFS="|"
    for val in $stack_keys; do
        if [[ $i -ge $depth ]]; then
            break
        fi
        if [[ -z "$new_stack" ]]; then
            new_stack="$val"
        else
            new_stack="${new_stack}|${val}"
        fi
        i=$((i + 1))
    done
    IFS="$IFS_OLD"

    # Pad with empty entries if needed
    while [[ $i -lt $depth ]]; do
        if [[ -z "$new_stack" ]]; then
            new_stack="_"
        else
            new_stack="${new_stack}|_"
        fi
        i=$((i + 1))
    done

    # Add the new key at this depth
    if [[ -z "$new_stack" ]]; then
        new_stack="$key"
    else
        new_stack="${new_stack}|${key}"
    fi

    stack_keys="$new_stack"
    stack_size=$((depth + 1))
}

# Helper: build dotted key path from stack up to given depth. Result in _YAML_KEY.
_strat_yaml_build_key () {
    local up_to="$1"
    _YAML_KEY=""
    local i=0
    local IFS_OLD="$IFS"
    IFS="|"
    for val in $stack_keys; do
        if [[ $i -ge $up_to ]]; then
            break
        fi
        if [[ -z "$_YAML_KEY" ]]; then
            _YAML_KEY="$val"
        else
            _YAML_KEY="${_YAML_KEY}.${val}"
        fi
        i=$((i + 1))
    done
    IFS="$IFS_OLD"
}
