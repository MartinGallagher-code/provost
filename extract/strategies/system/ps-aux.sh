#!/bin/bash
## Name: ps-aux
## Description: Extract per-process rows from `ps aux` output
## Version: 1.0
## Priority: 22
## Sample: samples/ps-aux/basic.txt

# `ps aux` output looks like:
#   USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
#   root         1  0.0  0.1 169404 11512 ?        Ss   Jun30   0:12 /sbin/init
#   www-data  1234  2.5  1.3 987654 54321 ?        S    10:01   1:02 nginx: worker
# The header's USER/PID/%CPU/%MEM/COMMAND ordering is the signature. Each data
# row becomes an entry<N>.<field> group; COMMAND (which contains spaces) is the
# joined remainder. Limitation: only the BSD `ps aux` column layout is parsed
# (the `ps -ef` UID/PPID/STIME layout is a separate shape).

_PSAUX_HEADER_RE='^USER[[:space:]]+PID[[:space:]]+%CPU[[:space:]]+%MEM[[:space:]]+VSZ[[:space:]]+RSS'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    _is_json "$text" && return 1

    local _has_header=0 _line
    while IFS= read -r _line; do
        [[ "$_line" =~ $_PSAUX_HEADER_RE ]] && { _has_header=1; break; }
    done <<< "$text"

    [[ $_has_header -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    printf '%s\n' "$text" | awk '
        $0 ~ /^USER[[:space:]]+PID[[:space:]]+%CPU[[:space:]]+%MEM/ { next }
        NF >= 11 && $2 ~ /^[0-9]+$/ {
            n++
            cmd=$11; for (i = 12; i <= NF; i++) cmd = cmd "_" $i
            printf "entry%d.user %s\n",    n, $1
            printf "entry%d.pid %s\n",     n, $2
            printf "entry%d.cpu_pct %s\n", n, $3
            printf "entry%d.mem_pct %s\n", n, $4
            printf "entry%d.vsz %s\n",     n, $5
            printf "entry%d.rss %s\n",     n, $6
            printf "entry%d.tty %s\n",     n, $7
            printf "entry%d.stat %s\n",    n, $8
            printf "entry%d.start %s\n",   n, $9
            printf "entry%d.time %s\n",    n, $10
            printf "entry%d.command %s\n", n, cmd
        }
        END { if (n > 0) printf "total_entries %d\n", n }
    '
}
