#!/bin/bash
## Name: sqlite-output
## Description: Extract field names and values from SQLite CLI output (pipe-delimited or column mode)
## Version: 1.0
## Priority: 22
## Sample: samples/sqlite-output/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Reject JSON
    _is_json "$1" && return 1

    # Decline `+---+` box tables — psql-table's box parser owns those (it strips
    # outer borders / title banners that this flatten-parser drops a column on).
    local _bxl
    while IFS= read -r _bxl; do
        [[ "$_bxl" == *"+"* && "$_bxl" == *"---"* ]] || continue
        [[ "$_bxl" =~ ^[[:space:]]*[-+[:space:]]+$ ]] && return 1
    done <<< "$text"

    # Detect pipe-delimited mode: at least 2 lines with same number of pipe chars
    # OR column mode: header line followed by a line of dashes+spaces
    # OR sqlite> prompt or .mode/.headers commands

    local line_num=0
    local first_pipe_count=-1
    local pipe_lines=0
    local found_dash_separator=0
    local found_prompt=0
    local prev_line=""

    while IFS= read -r _line; do
        line_num=$((line_num + 1))
        [[ -z "$_line" ]] && continue

        # Check for sqlite> prompt
        if [[ "$_line" == "sqlite>"* ]]; then
            found_prompt=1
        fi

        # Check for .mode or .headers commands
        if [[ "$_line" == ".mode "* || "$_line" == ".headers "* ]]; then
            found_prompt=1
        fi

        # Count pipes in line — but ignore ASCII tree glyphs (`|__`, `|--` in
        # lsusb -t / pstree), whose `|` is a drawing character, not a column
        # delimiter. A real sqlite pipe row has content, not `_`/`-`, after `|`.
        local pc=0
        if [[ "$_line" != *'|_'* && "$_line" != *'|-'* ]]; then
            local stripped="${_line//[^|]/}"
            pc=${#stripped}
        fi

        if [[ $pc -ge 1 ]]; then
            if [[ $first_pipe_count -eq -1 ]]; then
                first_pipe_count=$pc
                pipe_lines=1
            elif [[ $pc -eq $first_pipe_count ]]; then
                pipe_lines=$((pipe_lines + 1))
            fi
        fi

        # Check for column-mode dash separator: line of --- and spaces. It must be
        # SEGMENTED (>=2 space-separated dash groups, `--- ----- ---`), the way
        # sqlite `.mode column` prints it — that segmentation is what defines the
        # columns. A single solid rule (`--------`, jmap-histo / gpg key banners) is
        # not a column separator; it carries no column boundaries, so decline it and
        # let aligned-columns parse the real header + rows.
        local _re_dash='^[-]+[ ]*[-]*'
        if [[ "$_line" =~ $_re_dash ]]; then
            # Must be mostly dashes and spaces
            local nodash="${_line//[-]/}"
            nodash="${nodash// /}"
            if [[ ${#nodash} -eq 0 && ${#_line} -ge 5 ]]; then
                # Count dash groups: segmented separators have an inner space.
                local _dg; _dg="$(printf '%s' "$_line" | tr -s ' ' '\n' | grep -c '^-\+$')"
                [[ "$_dg" -ge 2 ]] && found_dash_separator=1
            fi
        fi

        prev_line="$_line"
    done <<< "$text"

    # Pipe-delimited mode: at least 2 lines with consistent pipe count
    if [[ $pipe_lines -ge 2 && $first_pipe_count -ge 1 ]]; then
        return 0
    fi

    # Column mode with dash separator (sqlite `.mode column`: header / --- ----- /
    # rows). Tools that share this shape but have a better home (e.g. `vault
    # status`) win via a lower-priority-number bespoke strategy ahead of this one.
    if [[ $found_dash_separator -eq 1 ]]; then
        return 0
    fi

    # Prompt or command detected
    if [[ $found_prompt -eq 1 ]]; then
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Determine mode: pipe-delimited or column
    local first_data_line=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        first_data_line="$_line"
        break
    done <<< "$text"

    if [[ "$first_data_line" == *"|"* ]]; then
        _strat_sqlite_extract_pipe "$text"
    else
        _strat_sqlite_extract_column "$text"
    fi
}

_strat_sqlite_extract_pipe () {
    local text="$1"
    local result=""
    local header_line=""
    local line_num=0
    local row_num=0

    # First line is header, rest are data
    local headers=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip a pure dash/space rule under the header (dnf history's
        # `------------`): it is a separator, not a data row.
        local _nd="${line//[-]/}"; _nd="${_nd// /}"
        [[ -z "$_nd" && "$line" == *"-"* ]] && continue
        line_num=$((line_num + 1))

        if [[ $line_num -eq 1 ]]; then
            # Parse header names from pipe-delimited
            local remaining="$line"
            while [[ -n "$remaining" ]]; do
                local field="${remaining%%|*}"
                # Trim whitespace
                while [[ "$field" == " "* ]]; do field="${field# }"; done
                while [[ "$field" == *" " ]]; do field="${field% }"; done
                headers+=("$field")
                if [[ "$remaining" == *"|"* ]]; then
                    remaining="${remaining#*|}"
                else
                    break
                fi
            done
            continue
        fi

        # Data row
        row_num=$((row_num + 1))
        local prefix="row${row_num}"
        local col_idx=0
        local remaining="$line"

        while [[ -n "$remaining" ]]; do
            local val="${remaining%%|*}"
            # Trim whitespace
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done

            if [[ $col_idx -lt ${#headers[@]} ]]; then
                local col_name="${headers[$col_idx]}"
                # Normalize to lowercase; spaces to `_` so a multi-word header
                # (`Command line`, `Date and time`) is one field name — the tidy
                # melt splits `entryN.field value` on the FIRST space.
                col_name=$(echo "$col_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
                [[ -n "$val" ]] && result+="${prefix}.${col_name} ${val}"$'\n'
            fi

            col_idx=$((col_idx + 1))
            if [[ "$remaining" == *"|"* ]]; then
                remaining="${remaining#*|}"
            else
                break
            fi
        done
    done <<< "$text"

    echo "$result"
}

_strat_sqlite_extract_column () {
    local text="$1"
    local result=""

    # Get header line and dash separator, then data
    local header_line=""
    local dash_line=""
    local line_num=0
    local headers=()
    local col_starts=()
    local col_ends=()

    # Find header and dash lines
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        line_num=$((line_num + 1))
        if [[ $line_num -eq 1 ]]; then
            header_line="$_line"
        elif [[ $line_num -eq 2 ]]; then
            dash_line="$_line"
            break
        fi
    done <<< "$text"

    [[ -z "$header_line" || -z "$dash_line" ]] && return

    # Parse column positions from dash separator
    # Dashes indicate column spans, spaces separate columns
    local i=0
    local in_dash=0
    local col_start=0
    local col_idx=0

    for ((i=0; i<${#dash_line}; i++)); do
        local c="${dash_line:$i:1}"
        if [[ "$c" == "-" ]]; then
            if [[ $in_dash -eq 0 ]]; then
                col_start=$i
                in_dash=1
            fi
        else
            if [[ $in_dash -eq 1 ]]; then
                col_starts+=("$col_start")
                col_ends+=("$i")
                in_dash=0
            fi
        fi
    done
    # Handle last column
    if [[ $in_dash -eq 1 ]]; then
        col_starts+=("$col_start")
        col_ends+=("$((${#dash_line}))")
    fi

    # Extract header names using column positions
    for ((i=0; i<${#col_starts[@]}; i++)); do
        local s=${col_starts[$i]}
        local e=${col_ends[$i]}
        local len=$((e - s))
        local name="${header_line:$s:$len}"
        # Trim whitespace
        while [[ "$name" == " "* ]]; do name="${name# }"; done
        while [[ "$name" == *" " ]]; do name="${name% }"; done
        # Normalize to lowercase; spaces to `_` (multi-word header = one field).
        name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
        headers+=("$name")
    done

    # Process data rows (skip header and dash lines)
    local row_num=0
    line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        [[ $line_num -le 2 ]] && continue  # skip header and dashes
        [[ -z "$line" ]] && continue

        row_num=$((row_num + 1))
        local prefix="row${row_num}"

        for ((i=0; i<${#col_starts[@]}; i++)); do
            local s=${col_starts[$i]}
            local e=${col_ends[$i]}
            local len=$((e - s))
            # For last column, take rest of line
            local val
            if [[ $((i + 1)) -eq ${#col_starts[@]} ]]; then
                val="${line:$s}"
            else
                val="${line:$s:$len}"
            fi
            # Trim whitespace
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            [[ -z "$val" ]] && continue

            local col_name="${headers[$i]}"
            [[ -n "$col_name" ]] && result+="${prefix}.${col_name} ${val}"$'\n'
        done
    done <<< "$text"

    echo "$result"
}
