#!/bin/bash
## Name: mpi-ranklog
## Description: Extract structured data from multi-rank interleaved MPI output with rank prefixes
## Version: 1.0
## Priority: 20
## Sample: samples/mpi-ranklog/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    local rank_lines=0

    while IFS= read -r line; do
        # [0] message, [1] message
        if [[ "$line" =~ ^\[([0-9]+)\] ]]; then
            rank_lines=$((rank_lines + 1))
        # [rank 0] message
        elif [[ "$line" =~ ^\[rank[[:space:]]+([0-9]+)\] ]]; then
            rank_lines=$((rank_lines + 1))
        # [1,0] message (MPI grid notation)
        elif [[ "$line" =~ ^\[([0-9]+),([0-9]+)\] ]]; then
            rank_lines=$((rank_lines + 1))
        # Rank 0: message
        elif [[ "$line" =~ ^Rank[[:space:]]+([0-9]+)[[:space:]]*: ]]; then
            rank_lines=$((rank_lines + 1))
        fi
        # Early exit once we have enough evidence
        [[ $rank_lines -ge 3 ]] && break
    done <<< "$text"

    if [[ $rank_lines -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    elif [[ $rank_lines -ge 1 ]]; then
        _STRATEGY_CONFIDENCE=60
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local max_rank=-1
    local -A rank_lines
    local -A rank_errors
    local total_lines=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        total_lines=$((total_lines + 1))

        local rank=""
        local msg=""

        # [0] message
        if [[ "$line" =~ ^\[([0-9]+)\][[:space:]]*(.*) ]]; then
            rank="${BASH_REMATCH[1]}"
            msg="${BASH_REMATCH[2]}"
        # [rank 3] message
        elif [[ "$line" =~ ^\[rank[[:space:]]+([0-9]+)\][[:space:]]*(.*) ]]; then
            rank="${BASH_REMATCH[1]}"
            msg="${BASH_REMATCH[2]}"
        # [1,0] message (grid notation - use first index as rank)
        elif [[ "$line" =~ ^\[([0-9]+),([0-9]+)\][[:space:]]*(.*) ]]; then
            rank="${BASH_REMATCH[1]}"
            msg="${BASH_REMATCH[3]}"
        # Rank 0: message
        elif [[ "$line" =~ ^Rank[[:space:]]+([0-9]+)[[:space:]]*:[[:space:]]*(.*) ]]; then
            rank="${BASH_REMATCH[1]}"
            msg="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Track max rank
        if [[ $rank -gt $max_rank ]]; then
            max_rank=$rank
        fi

        # Count lines per rank
        rank_lines[$rank]=$(( ${rank_lines[$rank]:-0} + 1 ))

        # Detect errors per rank
        if _strat_mpi_ranklog_is_error "$msg"; then
            rank_errors[$rank]=$(( ${rank_errors[$rank]:-0} + 1 ))
        fi

    done <<< "$text"

    if [[ $max_rank -ge 0 ]]; then
        local num_ranks=$((max_rank + 1))
        result+="num_ranks ${num_ranks}"$'\n'
        result+="total_rank_lines ${total_lines}"$'\n'

        # Per-rank line counts
        local r
        for r in $(echo "${!rank_lines[@]}" | tr ' ' '\n' | sort -n); do
            result+="rank.${r}.lines ${rank_lines[$r]}"$'\n'
        done

        # Per-rank error counts
        for r in $(echo "${!rank_errors[@]}" | tr ' ' '\n' | sort -n); do
            result+="rank.${r}.errors ${rank_errors[$r]}"$'\n'
        done

        # Total errors
        local total_errors=0
        for r in "${!rank_errors[@]}"; do
            total_errors=$((total_errors + rank_errors[$r]))
        done
        if [[ $total_errors -gt 0 ]]; then
            result+="total_errors ${total_errors}"$'\n'
        fi
    fi

    echo "$result"
}

_strat_mpi_ranklog_is_error () {
    local msg="$1"
    if [[ "$msg" =~ [Ee][Rr][Rr][Oo][Rr] ]]; then
        return 0
    fi
    if [[ "$msg" =~ [Ff][Aa][Ii][Ll] ]]; then
        return 0
    fi
    if [[ "$msg" =~ [Aa][Bb][Oo][Rr][Tt] ]]; then
        return 0
    fi
    if [[ "$msg" =~ SIGSEGV|SIGBUS|SIGFPE|SIGKILL ]]; then
        return 0
    fi
    return 1
}
