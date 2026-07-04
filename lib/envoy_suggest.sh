#!/bin/bash
################################################################################
## envoy_suggest.sh — shared "did you mean" / typo helpers
##
## Centralizes typo-suggestion logic shared by active Envoy command-line tools. Sourced by tools that need to disambiguate
## between "this is a typo'd flag / subcommand" and "this is a real file
## that happens to be missing" (ENV-137).
##
## Public functions:
##   _ENVOY_SUGGEST(input, candidates...) → echoes near-matches one per line
##   _envoy_arg_looks_like_typo(arg)      → exit 0 if `arg` is plausibly a
##                                           typo'd token (not a path, no
##                                           extension, ≤30 chars, doesn't
##                                           exist). Suite-wide heuristic.
##
## All functions are pure bash, no forks.
################################################################################

# Echo candidates that "look like" the input, using:
#   1. Prefix match — input is prefix of candidate, or candidate is prefix of input
#   2. Anagram (same characters, any order) — catches transpositions
#   3. Hamming distance ≤ 1 — catches single-char typos
#
# Usage: _envoy_suggest "extrac" extract show list capture
#        → echoes "extract" (prefix match)
#
#        _envoy_suggest "--jsn" --json --json-lines --csv
#        → echoes "--json" (hamming distance 1)
_envoy_suggest () {
    local input="$1"
    shift
    local cand
    for cand in "$@"; do
        if _envoy_is_prefix_or_substring "$input" "$cand"; then
            echo "$cand"
        elif _envoy_is_anagram "$input" "$cand"; then
            echo "$cand"
        elif _envoy_hamming_le_1 "$input" "$cand"; then
            echo "$cand"
        fi
    done
}

# Returns 0 if `a` is a prefix of `b` OR vice versa, OR `b` contains `a`
# as a substring. Catches partial inputs like 'extrac' → 'extract' and
# 'json' → '--json'.
_envoy_is_prefix_or_substring () {
    local a="$1" b="$2"
    [[ -z "$a" || -z "$b" ]] && return 1
    [[ "$b" == "$a"* ]] && return 0
    [[ "$a" == "$b"* ]] && return 0
    [[ "$b" == *"$a"* ]] && return 0
    return 1
}

# Returns 0 if `a` and `b` are anagrams (same length, same character multiset).
# Pure bash — no fork to sort.
_envoy_is_anagram () {
    local a="$1" b="$2"
    [[ ${#a} -eq ${#b} ]] || return 1
    [[ ${#a} -lt 2 ]] && return 1  # too short to be a meaningful anagram
    [[ "$a" == "$b" ]] && return 1  # identical strings aren't typo'd anagrams
    # Sort each string's characters via simple bubble sort. Pure bash, set -u safe.
    local sorted_a sorted_b
    sorted_a="$(_envoy_sort_chars "$a")"
    sorted_b="$(_envoy_sort_chars "$b")"
    [[ "$sorted_a" == "$sorted_b" ]]
}

# Internal: echo the characters of $1 in sorted order (no separator).
# Pure bash, no forks, set -u safe.
_envoy_sort_chars () {
    local s="$1" n=${#1} i j ch
    [[ $n -eq 0 ]] && return 0
    local arr=()
    for ((i = 0; i < n; i++)); do
        arr+=("${s:$i:1}")
    done
    # Bubble sort
    local swapped=1
    local last=$((n - 1))
    while (( swapped )); do
        swapped=0
        for ((i = 0; i < last; i++)); do
            j=$((i + 1))
            if [[ "${arr[i]}" > "${arr[j]}" ]]; then
                ch="${arr[i]}"
                arr[i]="${arr[j]}"
                arr[j]="$ch"
                swapped=1
            fi
        done
        last=$((last - 1))
    done
    printf '%s' "${arr[@]}"
}

# Returns 0 if Hamming distance between `a` and `b` is ≤ 1. Same-length only.
_envoy_hamming_le_1 () {
    local a="$1" b="$2"
    [[ ${#a} -eq ${#b} ]] || return 1
    [[ ${#a} -lt 2 ]] && return 1
    local diff=0 i
    for ((i = 0; i < ${#a}; i++)); do
        if [[ "${a:$i:1}" != "${b:$i:1}" ]]; then
            diff=$((diff + 1))
            (( diff > 1 )) && return 1
        fi
    done
    return 0
}

# Returns 0 if `arg` plausibly is a typo'd token (vs a missing real file).
# Heuristic: doesn't start with `-`, doesn't contain `/` or `.`, ≤30 chars,
# does not exist on disk. Tools call this from their file-not-found paths to
# decide whether to print a typo hint or a plain "File not found".
_envoy_arg_looks_like_typo () {
    local arg="$1"
    [[ -z "$arg" ]] && return 1
    [[ "$arg" == -* ]] && return 1
    [[ "$arg" == */* ]] && return 1
    [[ "$arg" == *.* ]] && return 1
    [[ ${#arg} -le 30 ]] || return 1
    [[ -e "$arg" ]] && return 1
    return 0
}
