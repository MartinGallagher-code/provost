#!/bin/bash
## Name: mount
## Description: Extract mounted-filesystem rows from `mount` output
## Version: 1.0
## Priority: 12
## Sample: samples/mount/basic.txt

# Priority 12 (below csv/kv-pairs) because mount's options field contains commas
# ("rw,relatime"), which the generic csv strategy would otherwise grab. The
# detector below is highly specific ("<dev> on <mp> type <fs> (<opts>)"), so
# winning the tie early is safe.

# `mount` output looks like:
#   /dev/sda1 on / type ext4 (rw,relatime)
#   tmpfs on /dev/shm type tmpfs (rw,nosuid,nodev)
#   proc on /proc type proc (rw,nosuid,nodev,noexec)
# i.e. "<device> on <mount-point> type <fstype> (<options>)". Each line becomes
# an entry<N>.<field> group so the capture tidy melt renders one row per mount.

_MOUNT_LINE_RE='^.+ on .+ type [^ ]+ \(.*\)'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    _is_json "$text" && return 1

    local _match=0 _line
    while IFS= read -r _line; do
        [[ "$_line" =~ $_MOUNT_LINE_RE ]] && _match=$((_match + 1))
    done <<< "$text"

    [[ $_match -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    # Parsed with index()/substr() (no gawk-only 3-arg match) so it runs under
    # mawk too. Shape: "<device> on <mount_point> type <fstype> (<options>)".
    printf '%s\n' "$text" | awk '
        {
            ti = index($0, " type ")
            if (ti == 0) next
            left  = substr($0, 1, ti - 1)      # "device on mount_point"
            right = substr($0, ti + 6)         # "fstype (options)"
            oi = index(left, " on ")
            if (oi == 0) next
            dev = substr(left, 1, oi - 1)
            mp  = substr(left, oi + 4)
            pi = index(right, " (")
            if (pi == 0) { fstype = right; opts = "" }
            else { fstype = substr(right, 1, pi - 1); opts = substr(right, pi + 2); sub(/\)[ \t]*$/, "", opts) }
            gsub(/ /, "_", dev); gsub(/ /, "_", mp)
            n++
            printf "entry%d.device %s\n",      n, dev
            printf "entry%d.mount_point %s\n", n, mp
            printf "entry%d.fstype %s\n",      n, fstype
            printf "entry%d.options %s\n",     n, opts
        }
        END { if (n > 0) printf "total_entries %d\n", n }
    '
}
