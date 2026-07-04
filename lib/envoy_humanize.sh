#!/bin/bash
################################################################################
## Envoy Shared Humanization Helpers — envoy_humanize.sh  (ENV-144)
##
## Three pure-bash + awk helpers that render durations, byte sizes, and
## byte-rates in user-friendly form.  Sourcing is OPTIONAL — every tool can
## still run standalone if the file isn't on disk; callers that depend on the
## helpers should provide a no-op fallback (see the pattern used elsewhere in
## the suite for envoy_pager.sh / envoy_suggest.sh).
##
## Public API
## ----------
##   humanize_duration SECONDS      Echos "0s" / "0.5s" / "12s" / "1m 42s" /
##                                  "1h 3m" / "2d 4h".  Truncates fractions to
##                                  one decimal for sub-second values; integer
##                                  units beyond seconds (m/h/d) drop the
##                                  remainder.  Negative input -> "-<abs>".
##   humanize_bytes BYTES           Echos "0 B" / "512 B" / "1.5 KiB" /
##                                  "2.3 MiB" / "1.1 GiB" / "1.0 TiB".
##                                  Binary prefixes (1024).  Two significant
##                                  figures for fractional values; integers
##                                  for whole-byte counts.  Negative -> "-".
##   humanize_rate BYTES_PER_SEC    "<humanize_bytes value>/s".
##
## Conventions
## -----------
##   - Pure-bash arithmetic for duration thresholds; awk for the single
##     fractional-digit format.  One awk fork per call is fine for display
##     code, not for tight loops.
##   - Binary prefixes (KiB, MiB, GiB, TiB) match `du -h --apparent-size`
##     conventions and IEEE 1541 / IEC 60027-2.  We deliberately do not use
##     SI prefixes (KB, MB) — those would round 1024 -> "1.0 KB" misleadingly.
##   - Inputs are validated as integers (or numeric for sub-second).  An
##     empty / non-numeric input echoes the literal "0s" / "0 B" so callers
##     don't have to guard their own `$count` integers.
##
## Reads (env / globals): none
## Writes (globals):      none (pure)
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_HUMANIZE_LOADED:-}" ]] && return 0
_ENVOY_HUMANIZE_LOADED=1

################################################################################
## humanize_duration SECONDS
##
## Echos a compact human-readable elapsed time.
##
## Examples:
##   humanize_duration 0       -> "0s"
##   humanize_duration 0.5     -> "0.5s"
##   humanize_duration 12      -> "12s"
##   humanize_duration 90      -> "1m 30s"
##   humanize_duration 3661    -> "1h 1m"
##   humanize_duration 90061   -> "1d 1h"
##   humanize_duration -42     -> "-42s"
##
## Rounding rules:
##   - Sub-second values render with one decimal ("0.5s", "0.0s", "0.9s").
##   - Integer second values >= 1 render whole ("12s", not "12.0s").
##   - Composite forms (m+s, h+m, d+h) show two units max — leftover
##     finer-grained units are dropped to keep the string short.
################################################################################
humanize_duration() {
    local secs="${1:-0}"

    # Empty -> "0s".
    [[ -z "$secs" ]] && { printf '%s\n' "0s"; return 0; }

    # Negative: recurse on |x| and prepend "-". This keeps the rendering
    # logic in one place.
    if [[ "$secs" == -* ]]; then
        local abs="${secs#-}"
        # Use `--` so the leading dash isn't parsed as a printf flag.
        printf -- '-%s\n' "$(humanize_duration "$abs")"
        return 0
    fi

    # Reject anything that isn't a non-negative number.  Non-numeric ->
    # "0s" so callers can pass uninitialised counters without crashing.
    if ! [[ "$secs" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf '%s\n' "0s"
        return 0
    fi

    # Sub-second: one decimal digit, no extra units.
    if [[ "$secs" == *.* ]]; then
        # Floor to integer to compare against 1.  awk handles the rounding.
        local int_part="${secs%%.*}"
        if [[ "$int_part" == "0" ]]; then
            awk -v s="$secs" 'BEGIN { printf "%.1fs\n", s }'
            return 0
        fi
        # Non-zero integer part — drop fraction and fall through.
        secs="$int_part"
    fi

    # Integer seconds.  Compose at most two units.
    local s=$(( secs % 60 ))
    local m=$(( (secs / 60) % 60 ))
    local h=$(( (secs / 3600) % 24 ))
    local d=$(( secs / 86400 ))

    if   (( d > 0 )); then printf '%dd %dh\n' "$d" "$h"
    elif (( h > 0 )); then printf '%dh %dm\n' "$h" "$m"
    elif (( m > 0 )); then printf '%dm %ds\n' "$m" "$s"
    else                   printf '%ds\n'    "$s"
    fi
}

################################################################################
## humanize_bytes BYTES
##
## Echos a binary-prefix human-readable byte size.
##
## Examples:
##   humanize_bytes 0           -> "0 B"
##   humanize_bytes 512         -> "512 B"
##   humanize_bytes 1023        -> "1023 B"
##   humanize_bytes 1024        -> "1.0 KiB"
##   humanize_bytes 1536        -> "1.5 KiB"
##   humanize_bytes 1048576     -> "1.0 MiB"
##   humanize_bytes 1610612736  -> "1.5 GiB"
##   humanize_bytes -42         -> "-42 B"
##
## Rounding rules:
##   - Whole bytes (< 1024) render as integer + " B".
##   - Non-integer values render with one decimal digit.
##   - Scales up to EiB (covers the full 64-bit byte range).
################################################################################
humanize_bytes() {
    local bytes="${1:-0}"

    [[ -z "$bytes" ]] && { printf '%s\n' "0 B"; return 0; }

    if [[ "$bytes" == -* ]]; then
        local abs="${bytes#-}"
        printf -- '-%s\n' "$(humanize_bytes "$abs")"
        return 0
    fi

    # Reject non-integer.  Display code shouldn't crash on bad data.
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        printf '%s\n' "0 B"
        return 0
    fi

    # Whole-byte path stays in pure bash (no awk fork).
    if (( bytes < 1024 )); then
        printf '%d B\n' "$bytes"
        return 0
    fi

    # Use awk for the single-decimal format and unit selection.  One fork
    # per call is acceptable for display code.
    awk -v b="$bytes" '
        BEGIN {
            split("KiB MiB GiB TiB PiB EiB", units, " ");
            n = b / 1024;
            i = 1;
            while (n >= 1024 && i < 6) { n /= 1024; i++ }
            printf "%.1f %s\n", n, units[i];
        }'
}

################################################################################
## humanize_rate BYTES_PER_SEC
##
## Convenience wrapper: appends "/s" to humanize_bytes.  Defined separately
## so callers communicate intent at the call site.
################################################################################
humanize_rate() {
    local bps="${1:-0}"
    printf '%s/s\n' "$(humanize_bytes "$bps")"
}

################################################################################
## humanize_relative_date SECONDS_AGO  (ENV-148)
##
## Echos a short English phrase describing how long ago a moment was, given
## the difference (in seconds) between "now" and the target time. Negative
## inputs are clock-skew futures and emit `in N <unit>` rather than crashing.
##
## Boundary table (mirrors `git log --pretty='%cr'` / GitHub style):
##   < 0          -> "in N <unit>" (or "in a moment" for sub-minute futures)
##   < 60         -> "just now"
##   < 60*60      -> "<n> minutes ago" (1 -> "1 minute ago")
##   < 24*60*60   -> "<n> hours ago"
##   < 7*86400    -> "<n> days ago"   (1 -> "yesterday" / "tomorrow")
##   < 30*86400   -> "<n> weeks ago"
##   < 365*86400  -> "<n> months ago"
##   else         -> "<n> years ago"
##
## Pure-bash arithmetic; no awk fork. Locale-independent (English only) per
## project convention. Non-numeric input falls back to "just now".
################################################################################
humanize_relative_date() {
    local age="${1:-0}"
    if ! [[ "$age" =~ ^-?[0-9]+$ ]]; then
        echo "just now"
        return
    fi

    local future=0
    if (( age < 0 )); then
        future=1
        age=$(( -age ))
    fi

    local n unit
    if (( age < 60 )); then
        if (( future )); then echo "in a moment"; else echo "just now"; fi
        return
    elif (( age < 3600 )); then
        n=$(( age / 60 )); unit="minute"
    elif (( age < 86400 )); then
        n=$(( age / 3600 )); unit="hour"
    elif (( age < 7 * 86400 )); then
        n=$(( age / 86400 ))
        if (( n == 1 )); then
            (( future )) && echo "tomorrow" || echo "yesterday"
            return
        fi
        unit="day"
    elif (( age < 30 * 86400 )); then
        n=$(( age / (7 * 86400) )); unit="week"
    elif (( age < 365 * 86400 )); then
        n=$(( age / (30 * 86400) )); unit="month"
    else
        n=$(( age / (365 * 86400) )); unit="year"
    fi

    (( n != 1 )) && unit="${unit}s"
    if (( future )); then
        echo "in $n $unit"
    else
        echo "$n $unit ago"
    fi
}

################################################################################
## humanize_relative_iso ISO_TIMESTAMP  (ENV-148)
##
## Convenience wrapper that converts an ISO-8601 timestamp (or a
## capture-workspace-style `YYYY-MM-DD_HH-MM-SS`) into a relative phrase via
## humanize_relative_date. Echos empty when the timestamp cannot be parsed,
## so callers can append the result unconditionally.
################################################################################
humanize_relative_iso() {
    local iso="${1:-}"
    [[ -z "$iso" ]] && { echo ""; return; }
    # Capture-workspace timestamps are `YYYY-MM-DD_HH-MM-SS`. Convert to a
    # form GNU `date -d` accepts.
    if [[ "$iso" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
        local d="${iso%_*}"
        local t="${iso#*_}"
        t="${t//-/:}"
        iso="${d}T${t}"
    fi
    local epoch now age
    epoch=$(date -d "$iso" +%s 2>/dev/null) || { echo ""; return; }
    now=$(date +%s)
    age=$(( now - epoch ))
    humanize_relative_date "$age"
}
