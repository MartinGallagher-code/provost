#!/bin/bash
## Name: embedded-table
## Description: Reports with one dominant aligned table amid prose/kv preamble and footnotes
## Version: 1.0
## Priority: 37
## Sample: samples/embedded-table/basic.txt

# The REPORT shape: free prose or `Key: value` preamble, ONE dominant
# whitespace-aligned table (labelly header + consistent data rows), optional
# trailing footnotes/kv — smartctl -a, mdadm --detail, benchmark write-ups,
# backup job reports:
#
#   Backup Job Report
#   Job Name:   nightly-full
#
#   Volume       Files      Size       Status
#   vol-daily    122045     18.4 GB    OK
#   ...
#
#   Elapsed:    01:42:18
#
# aligned-columns can't take these (the preamble defeats its banner rules and
# block-records claims the blank-separated blocks first, welding everything
# into kv mush). This strategy finds the LARGEST table window and extracts
# only it; everything outside the window is report chrome.
#
# A table window: a HEADER line — >=3 tokens, digit-free, every token
# alphanumeric-bearing, none ending in ':' (a kv label) — followed by >=3
# consecutive non-blank lines each with >= the header's token count and >=1
# digit-bearing token (data, not prose). And the window must be EMBEDDED:
# >=2 non-blank lines outside it — a bare table stays with aligned-columns.

# Find the best window. Sets _ET_START (header line index, 0-based over
# non-blank-preserved raw lines), _ET_LEN (data row count), _ET_COLS.
_et_scan () {
    local text="$1"
    local -a _lines=()
    local _l
    while IFS= read -r _l; do _lines+=("$_l"); done <<< "$text"
    _ET_START=-1; _ET_LEN=0; _ET_COLS=0
    local i j n=${#_lines[@]} nonblank=0
    for ((i = 0; i < n; i++)); do
        [[ -n "${_lines[$i]//[[:space:]]/}" ]] && nonblank=$((nonblank + 1))
    done
    for ((i = 0; i < n; i++)); do
        _l="${_lines[$i]}"
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        [[ "$_l" =~ [0-9] ]] && continue
        local -a hk=(); read -ra hk <<< "$_l"
        [[ ${#hk[@]} -lt 3 ]] && continue
        local t ok=1
        for t in "${hk[@]}"; do
            # a label: alphanumeric-bearing, starts alnum-or-bracket (a diff
            # hunk's `+use` line must not read as a header), no kv colon
            [[ "$t" =~ [A-Za-z0-9] && "$t" != *: && "$t" =~ ^[A-Za-z0-9\[] ]] || { ok=0; break; }
        done
        [[ $ok -eq 0 ]] && continue
        # The header must open a section: preceded by a blank line, the start
        # of input, or a NARROWER line (a title, kv or section label — fewer
        # tokens). A same-or-wider data row directly above means this "header"
        # is really a row inside a bigger table (prlimit's all-caps rows).
        if [[ $i -gt 0 && -n "${_lines[$((i - 1))]//[[:space:]]/}" ]]; then
            local -a pv=(); read -ra pv <<< "${_lines[$((i - 1))]}"
            if [[ ${#pv[@]} -ge ${#hk[@]} ]]; then
                # …unless that wider line is banner chrome, not a data row: a
                # data row's tokens all lead with alphanumerics, a `=== SECTION
                # ===` banner's don't.
                local _pvrow=1 t3
                for t3 in "${pv[@]}"; do [[ "$t3" =~ ^[A-Za-z0-9] ]] || { _pvrow=0; break; }; done
                [[ $_pvrow -eq 1 ]] && continue
            fi
        fi
        # count consecutive data rows: >= the header's token count, digit-
        # bearing (data, not prose), and not a SENTENCE (ends in '.')
        local rows=0
        for ((j = i + 1; j < n; j++)); do
            local dl="${_lines[$j]}"
            [[ -z "${dl//[[:space:]]/}" ]] && break
            local -a dk=(); read -ra dk <<< "$dl"
            [[ ${#dk[@]} -lt ${#hk[@]} ]] && break
            [[ "$dl" =~ [0-9] ]] || break
            [[ "$dl" =~ \.$ ]] && break
            rows=$((rows + 1))
        done
        # The window must CLOSE the section too: the line after the last row
        # must be blank, EOF, or narrower. A same-width non-matching row right
        # after (a digit-free data row like `worker stopped - -`) means the
        # window TRUNCATED a bigger table — that table isn't ours.
        local nxt=$((i + rows + 1))
        if [[ $nxt -lt $n && -n "${_lines[$nxt]//[[:space:]]/}" ]]; then
            local -a nk=(); read -ra nk <<< "${_lines[$nxt]}"
            [[ ${#nk[@]} -ge ${#hk[@]} ]] && continue
        fi
        if [[ $rows -ge 3 && $rows -gt $_ET_LEN ]]; then
            _ET_START=$i; _ET_LEN=$rows; _ET_COLS=${#hk[@]}
        fi
    done
    [[ $_ET_START -lt 0 ]] && return 1
    # Embedded means real chrome around it: >=2 non-blank lines OUTSIDE.
    [[ $(( nonblank - _ET_LEN - 1 )) -ge 2 ]] || return 1
    # And the chrome must contain at least one PROSE/banner line — >=3 tokens,
    # >=2 of them alphanumeric-bearing, and NOT `key: value`-shaped (no ` : `
    # and no colon-suffixed first token). A report whose chrome is ALL kv
    # (mdadm --detail's `Version : 1.2` block, nvidia-smi -q) is fully
    # representable by the kv-capable parsers (indented-hierarchy,
    # block-records) — table AND fields — and taking only the table would LOSE
    # the fields. Prose and footnotes, by contrast, no parser can use.
    local _pr=0
    local -a _hk2=(); read -ra _hk2 <<< "${_lines[$_ET_START]}"
    local _hnorm="${_hk2[*]}"
    for ((i = 0; i < n; i++)); do
        [[ $i -ge $_ET_START && $i -le $((_ET_START + _ET_LEN)) ]] && continue
        _l="${_lines[$i]}"
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        local -a pk=(); read -ra pk <<< "$_l"
        # A chrome line token-identical to the window's header is a SECTION
        # repeat — this is a multi-section table (faillock's per-user blocks,
        # ps/top page reprints) that aligned-columns' resume logic already
        # collects in full; taking one window would DROP the other sections.
        [[ "${pk[*]}" == "$_hnorm" ]] && return 1
        # …and a chrome line whose tokens are a SUBSET of the header's is a
        # sibling section's slightly-narrower header (yugabyte's Tablet
        # Servers table without the Role column) — same multi-section story.
        if [[ ${#pk[@]} -ge 3 && ${#pk[@]} -le ${#_hk2[@]} ]]; then
            local _sub=1 _st _st2 _hit2
            for _st in "${pk[@]}"; do
                _hit2=0
                for _st2 in "${_hk2[@]}"; do [[ "$_st" == "$_st2" ]] && { _hit2=1; break; }; done
                [[ $_hit2 -eq 0 ]] && { _sub=0; break; }
            done
            [[ $_sub -eq 1 ]] && return 1
        fi
        [[ "$_l" == *" : "* ]] && continue
        [[ ${#pk[@]} -lt 3 ]] && continue
        [[ "${pk[0]}" == *: ]] && continue
        # Prose is WORDS: digit-bearing chrome is data from another section
        # (faillock's second table, readelf's offset banner), and box-drawing
        # glyphs mark tree rows (findmnt submounts) — neither is the prose
        # preamble/footnote evidence this strategy exists for.
        [[ "$_l" =~ [0-9] ]] && continue
        [[ "$_l" == *$'\342\224'* || "$_l" == *$'\342\225'* ]] && continue
        local _pa=0 t2
        for t2 in "${pk[@]}"; do [[ "$t2" =~ [A-Za-z0-9] ]] && _pa=$((_pa + 1)); done
        [[ $_pa -ge 2 ]] && { _pr=1; break; }
    done
    [[ $_pr -eq 1 ]] || return 1
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="report with one dominant embedded aligned table"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    _et_scan "$text" || return 1
    _STRATEGY_CONFIDENCE=76
    return 0
}

strategy_extract () {
    local text="$1"
    _et_scan "$text" || { echo ""; return 0; }
    local -a _lines=()
    local _l
    while IFS= read -r _l; do _lines+=("$_l"); done <<< "$text"

    # Column boundaries from the header's printed token positions, split at the
    # MIDPOINT of each inter-label gap (the vertical-line treatment) — so a
    # multi-word cell anywhere in the row (`18.4 GB` under Size, `active sync`
    # under State) stays in ITS column instead of shifting everything after it,
    # and right-aligned numbers that start left of their label still land home.
    local hline="${_lines[$_ET_START]}"
    local -a headers=() h_start=() h_end=()
    local i c in_word=-1 n=${#hline}
    for ((i = 0; i < n; i++)); do
        c="${hline:$i:1}"
        if [[ "$c" != ' ' && "$c" != '	' ]]; then
            [[ $in_word -lt 0 ]] && { in_word=$i; h_start+=("$i"); }
        elif [[ $in_word -ge 0 ]]; then
            h_end+=($((i - 1))); headers+=("${hline:$in_word:$((i - in_word))}"); in_word=-1
        fi
    done
    [[ $in_word -ge 0 ]] && { h_end+=($((n - 1))); headers+=("${hline:$in_word:$((n - in_word))}"); }
    local ncols=${#headers[@]}
    for ((i = 0; i < ncols; i++)); do headers[$i]="${headers[$i]//./_}"; done
    local -a col_lo=(0) col_hi=()
    for ((i = 1; i < ncols; i++)); do
        local b=$(( (${h_end[$((i - 1))]} + ${h_start[$i]} + 1) / 2 ))
        col_hi+=("$b"); col_lo+=("$b")
    done
    col_hi+=(99999)

    local result="" entry=0 j
    for ((j = _ET_START + 1; j <= _ET_START + _ET_LEN; j++)); do
        local row="${_lines[$j]}"
        local rlen=${#row}
        entry=$((entry + 1))
        local lo=0 b
        for ((i = 0; i < ncols; i++)); do
            if [[ $i -lt $((ncols - 1)) ]]; then
                b=${col_hi[$i]}
                # A boundary landing INSIDE a token means that cell overflows
                # its printed column (`zstd-19` under a 4-char `Tool` label,
                # `Reallocated_Sector_Ct` past ATTRIBUTE_NAME's span): snap the
                # cut right to the token's end so the cell stays whole.
                while [[ $b -gt 0 && $b -lt $rlen && "${row:$b:1}" != ' ' && "${row:$((b - 1)):1}" != ' ' ]]; do
                    b=$((b + 1))
                done
            else
                b=$rlen
            fi
            [[ $lo -ge $rlen ]] && break
            [[ $b -gt $rlen ]] && b=$rlen
            local value="${row:$lo:$((b - lo))}"
            lo=$b
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            # collapse inner alignment padding runs to one space
            while [[ "$value" == *'  '* ]]; do value="${value//  / }"; done
            [[ -z "$value" ]] && continue
            result+="entry${entry}.${headers[$i]} ${value}"$'\n'
        done
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
