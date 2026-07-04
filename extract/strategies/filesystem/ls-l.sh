#!/bin/bash
## Name: ls-l
## Description: Extract fields from `ls -l` / `ls -la` long-format listings
## Version: 1.0
## Priority: 21
## Sample: samples/ls-l/basic.txt

# `ls -l` lines look like:
#   -rw-r--r-- 1 root root 9337 Jul  1 19:51 ASSESSMENT.md
#   drwxrwxrwx+ 3 codespace codespace 4096 Jul  2 17:01 .
# i.e. perms[+@.] links owner group size <month> <day> <time|year> name...
# This differs from tar's `-v` output (parsed by the tar-listing strategy),
# whose second field is `owner/group` (contains a slash) with no link count.

# A permission string, optionally followed by an ACL/xattr/SELinux marker,
# then a numeric link count — the signature that distinguishes ls -l from tar.
_LSL_LINE_RE='^[-dlbcps][-rwxsStT]{9}[+@.]?[[:space:]]+[0-9]+[[:space:]]'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88

    _is_json "$text" && return 1

    local _match_count=0 _line
    while IFS= read -r _line; do
        [[ "$_line" =~ $_LSL_LINE_RE ]] && _match_count=$((_match_count + 1))
    done <<< "$text"

    [[ $_match_count -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    # Parse in awk: perms links owner group size, a three-token date
    # (month day time-or-year), then the name (joined, spaces -> _ to keep the
    # key/value output space-delimited like the other listing strategies).
    printf '%s\n' "$text" | awk '
        /^total[[:space:]]+[0-9]+[[:space:]]*$/ { next }
        /^[-dlbcps][-rwxsStT]{9}[+@.]?[[:space:]]+[0-9]+[[:space:]]/ {
            n++
            perms=$1; links=$2; owner=$3; group=$4; size=$5
            date=$6 "_" $7 "_" $8
            name=""
            for (i = 9; i <= NF; i++) name = name (name == "" ? "" : "_") $i
            printf "entry%d.permissions %s\n", n, perms
            printf "entry%d.links %s\n",       n, links
            printf "entry%d.owner %s\n",       n, owner
            printf "entry%d.group %s\n",       n, group
            printf "entry%d.size %s\n",        n, size
            printf "entry%d.date %s\n",        n, date
            printf "entry%d.name %s\n",        n, name
        }
        END { if (n > 0) printf "total_entries %d\n", n }
    '
}
