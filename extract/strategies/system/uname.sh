#!/bin/bash
## Name: uname
## Description: Single-line uname output (uname -a / -s -n -r -m -o)
## Version: 1.0
## Priority: 20
## Sample: samples/uname/basic.txt

# `uname -a` is a single freeform line: "<sysname> <nodename> <release>
# <version…> <machine> … <operating-system>". No generic structural parser fits
# a one-line positional format, so this pulls the stable fields.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Exactly one non-blank line.
    local nonblank=0 first="" _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        [[ -z "$first" ]] && first="$_l"
    done <<< "$text"
    [[ $nonblank -eq 1 ]] || return 1

    local toks; toks=(); read -ra toks <<< "$first"
    [[ ${#toks[@]} -ge 5 ]] || return 1
    case "${toks[0]}" in
        Linux|Darwin|FreeBSD|OpenBSD|NetBSD|DragonFly|SunOS|AIX|GNU) ;;
        *) return 1 ;;
    esac
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local first="" _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && { continue; }
        first="$_l"; break
    done <<< "$text"

    local toks; toks=(); read -ra toks <<< "$first"
    local n=${#toks[@]}
    local result=""
    result+="entry1.kernel_name ${toks[0]}"$'\n'
    result+="entry1.nodename ${toks[1]}"$'\n'
    result+="entry1.kernel_release ${toks[2]}"$'\n'
    # machine/arch: the token matching a known architecture
    local t arch=""
    for t in "${toks[@]}"; do
        [[ "$t" =~ ^(x86_64|amd64|aarch64|arm64|armv[0-9]+l?|i[3-6]86|ppc64le?|s390x|riscv64|mips[0-9]*el?)$ ]] && arch="$t"
    done
    [[ -n "$arch" ]] && result+="entry1.machine ${arch}"$'\n'
    result+="entry1.operating_system ${toks[$((n - 1))]}"$'\n'
    result+="total_entries 1"$'\n'
    echo "$result"
}
