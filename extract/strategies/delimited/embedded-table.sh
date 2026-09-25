#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: embedded-table
## Description: Reports with one dominant aligned table amid prose/kv preamble and footnotes
## Version: 1.1
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

# Does a SHORT data row (fewer tokens than the header) still belong to this
# table? Only if every token positionally aligns to a distinct header column in
# increasing order — a genuine blank interior cell (bundle-outdated's sidekiq
# row with an empty `Requested`), not a prose footnote that merely has a digit.
# Column boundaries mirror the extractor's midpoint model. $1=header line,
# $2=data line. Returns 0 when aligned.
_et_row_aligns () {
    local hline="$1" dline="$2"
    # Header token start columns.
    local -a hs=() he=()
    local i c inw=-1 n=${#hline}
    for ((i = 0; i < n; i++)); do
        c="${hline:$i:1}"
        if [[ "$c" != ' ' && "$c" != $'\t' ]]; then
            [[ $inw -lt 0 ]] && { inw=$i; hs+=("$i"); }
        elif [[ $inw -ge 0 ]]; then he+=($((i - 1))); inw=-1; fi
    done
    [[ $inw -ge 0 ]] && he+=($((n - 1)))
    local ncols=${#hs[@]}
    [[ $ncols -lt 3 ]] && return 1
    # Midpoint boundary opening each column c (>=1); col 0 opens at 0.
    local -a bnd=(0)
    for ((i = 1; i < ncols; i++)); do
        bnd+=($(( (${he[$((i - 1))]} + ${hs[$i]} + 1) / 2 )))
    done
    # Bucket each data token's start into a column; require strictly increasing
    # distinct columns and a left-aligned first token (column 0).
    local dn=${#dline} prev=-1 tok=0 first=1
    inw=-1
    for ((i = 0; i <= dn; i++)); do
        c="${dline:$i:1}"
        if [[ $i -lt $dn && "$c" != ' ' && "$c" != $'\t' ]]; then
            if [[ $inw -lt 0 ]]; then
                inw=$i
                # column for a token starting at inw
                local col=0 k
                for ((k = 0; k < ncols; k++)); do
                    [[ $inw -ge ${bnd[$k]} ]] && col=$k
                done
                [[ $first -eq 1 && $col -ne 0 ]] && return 1
                first=0
                [[ $col -le $prev ]] && return 1
                prev=$col
                tok=$((tok + 1))
            fi
        else
            inw=-1
        fi
    done
    [[ $tok -ge 3 ]] || return 1
    return 0
}

# Find the best window. Sets _ET_START (header line index, 0-based over
# non-blank-preserved raw lines), _ET_LEN (data row count), _ET_COLS.
_et_scan () {
    local text="$1"
    local -a _lines=()
    local _l
    _fr_lines "$text"; _lines+=("${_FR_LINES[@]}"); _l=""
    _ET_START=-1; _ET_LEN=0; _ET_COLS=0
    # (a non-blank count used to be computed here and never read — dropped)
    local i j n=${#_lines[@]} nonblank=0
    for ((i = 0; i < n; i++)); do
        _l="${_lines[$i]}"
        [[ "${_l}" != *[![:space:]]* ]] && continue
        [[ "$_l" =~ [0-9] ]] && continue
        local -a hk=(); { _fr_tok "$_l"; hk=("${_FR_TOK[@]}"); }
        [[ ${#hk[@]} -lt 3 ]] && continue
        local t ok=1
        # a label: alphanumeric-bearing, starts alnum-or-bracket (a diff
        # hunk's `+use` line must not read as a header), no kv colon. An
        # optional leading `%` (or an escaped `\%`) is allowed too: iostat,
        # sar and pidstat name percentage columns `%util`, `%rrqm`, `%idle`.
        local _et_lead='^[%\]{0,2}[A-Za-z0-9[]'
        for t in "${hk[@]}"; do
            [[ "$t" =~ [A-Za-z0-9] && "$t" != *: && "$t" =~ $_et_lead ]] || { ok=0; break; }
        done
        [[ $ok -eq 0 ]] && continue
        # The header must open a section: preceded by a blank line, the start
        # of input, or a NARROWER line (a title, kv or section label — fewer
        # tokens). A same-or-wider data row directly above means this "header"
        # is really a row inside a bigger table (prlimit's all-caps rows).
        if [[ $i -gt 0 && "${_lines[$((i - 1))]}" == *[![:space:]]* ]]; then
            local -a pv=(); { _fr_tok "${_lines[$((i - 1))]}"; pv=("${_FR_TOK[@]}"); }
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
            [[ "${dl}" != *[![:space:]]* ]] && break
            local -a dk=(); { _fr_tok "$dl"; dk=("${_FR_TOK[@]}"); }
            # A row with fewer tokens than the header is admitted ONLY when its
            # tokens positionally align to distinct header columns — a blank
            # interior cell (bundle-outdated's sidekiq), not a prose footnote.
            # The FIRST row must be full-width, though: it anchors the window as
            # a genuine table. A header whose token count is inflated by
            # multi-word column labels (spec-cpu's doubled `Ref. Run Time Rate`)
            # makes EVERY data row "short" — that is aligned-columns' positional
            # multi-word-header case, not an embedded table.
            if [[ ${#dk[@]} -lt ${#hk[@]} ]]; then
                [[ $rows -eq 0 ]] && break
                _et_row_aligns "$_l" "$dl" || break
            fi
            [[ "$dl" =~ [0-9] ]] || break
            [[ "$dl" =~ \.$ ]] && break
            rows=$((rows + 1))
        done
        # The window must CLOSE the section too: the line after the last row
        # must be blank, EOF, or narrower. A same-width non-matching row right
        # after (a digit-free data row like `worker stopped - -`) means the
        # window TRUNCATED a bigger table — that table isn't ours.
        local nxt=$((i + rows + 1))
        if [[ $nxt -lt $n && "${_lines[$nxt]}" == *[![:space:]]* ]]; then
            local -a nk=(); { _fr_tok "${_lines[$nxt]}"; nk=("${_FR_TOK[@]}"); }
            [[ ${#nk[@]} -ge ${#hk[@]} ]] && continue
        fi
        # >=3 rows keeps prose from reading as a table — but a header line that
        # REPEATS verbatim elsewhere in the input has proven itself: interval
        # reports (`iostat -x 5`) reprint the same header per sample, often
        # with only a device or two beneath each. For those the floor drops to
        # 1; the extractor merges every same-header section's rows anyway.
        local need=3
        if [[ $rows -ge 1 && $rows -lt 3 ]]; then
            local reps=0 r2
            for ((r2 = 0; r2 < n; r2++)); do
                local -a rk2=(); { _fr_tok "${_lines[$r2]}"; rk2=("${_FR_TOK[@]}"); }
                [[ "${rk2[*]}" == "${hk[*]}" ]] && reps=$((reps + 1))
            done
            [[ $reps -ge 2 ]] && need=1
        fi
        if [[ $rows -ge $need && $rows -gt $_ET_LEN ]]; then
            _ET_START=$i; _ET_LEN=$rows; _ET_COLS=${#hk[@]}
        fi
    done
    [[ $_ET_START -lt 0 ]] && return 1
    return 0
}

# Detection POLICY over a found window — kept separate from _et_scan so a
# hints.tsv route (which bypasses strategy_detect, the hint row IS the
# detection) can extract any found window: iostat's chrome is a digit-bearing
# banner plus an `avg-cpu:` block, which the prose rule below rightly rejects
# for AUTO-detection but which the hint has already vouched for.
_et_policy () {
    local text="$1"
    local -a _lines=()
    local _l i
    _fr_lines "$text"; _lines+=("${_FR_LINES[@]}"); _l=""
    local n=${#_lines[@]} nonblank=0
    for ((i = 0; i < n; i++)); do
        [[ "${_lines[$i]}" == *[![:space:]]* ]] && nonblank=$((nonblank + 1))
    done
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
    local -a _hk2=(); { _fr_tok "${_lines[$_ET_START]}"; _hk2=("${_FR_TOK[@]}"); }
    local _hnorm="${_hk2[*]}"
    for ((i = 0; i < n; i++)); do
        [[ $i -ge $_ET_START && $i -le $((_ET_START + _ET_LEN)) ]] && continue
        _l="${_lines[$i]}"
        [[ "${_l}" != *[![:space:]]* ]] && continue
        local -a pk=(); { _fr_tok "$_l"; pk=("${_FR_TOK[@]}"); }
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
    _et_policy "$text" || return 1
    _STRATEGY_CONFIDENCE=76
    return 0
}

strategy_extract () {
    local text="$1"
    _et_scan "$text" || { echo ""; return 0; }
    local -a _lines=()
    local _l
    _fr_lines "$text"; _lines+=("${_FR_LINES[@]}"); _l=""

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

    # Rows to emit: the primary window, then — multi-sample reports like
    # `iostat -x 5` or `nstat`-wrapped iostat print the SAME table repeatedly,
    # one section per interval — the rows under every OTHER header line that is
    # token-identical to the primary's. Auto-detection still rejects repeated
    # sections (aligned-columns owns the bare multi-section case); this path is
    # reached via a hints.tsv route, and merging keeps every section's rows
    # instead of silently dropping all but the largest window.
    local -a row_idx=()
    local j
    for ((j = _ET_START + 1; j <= _ET_START + _ET_LEN; j++)); do row_idx+=("$j"); done
    local _hnorm k
    { local -a _hk3=(); { _fr_tok "$hline"; _hk3=("${_FR_TOK[@]}"); }; _hnorm="${_hk3[*]}"; }
    for ((k = 0; k < ${#_lines[@]}; k++)); do
        [[ $k -eq $_ET_START ]] && continue
        local -a _sk=(); { _fr_tok "${_lines[$k]}"; _sk=("${_FR_TOK[@]}"); }
        [[ "${_sk[*]}" == "$_hnorm" ]] || continue
        for ((j = k + 1; j < ${#_lines[@]}; j++)); do
            local dl="${_lines[$j]}"
            [[ "${dl}" != *[![:space:]]* ]] && break
            local -a dk2=(); { _fr_tok "$dl"; dk2=("${_FR_TOK[@]}"); }
            if [[ ${#dk2[@]} -lt $ncols ]]; then
                _et_row_aligns "$hline" "$dl" || break
            fi
            [[ "$dl" =~ [0-9] ]] || break
            [[ "$dl" =~ \.$ ]] && break
            row_idx+=("$j")
        done
    done

    local result="" entry=0
    for j in "${row_idx[@]}"; do
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
                # cut right to the token's end so the cell stays whole — EXCEPT
                # for a pure NUMBER nearer its own start. Numbers are printed
                # right-aligned, so one spilling LEFT of its label (iostat's
                # ` 10440.0` under a narrow wkB/s, sfdisk's wide sector counts)
                # belongs to the column ahead; welding it back would glue two
                # numeric cells. Text columns are left-aligned — for them the
                # old weld-right rule stays (dotnet's `> Newtonsoft.Json` under
                # a multi-word `Top-level Package` label must stay one cell).
                if [[ $b -gt 0 && $b -lt $rlen && "${row:$b:1}" != ' ' && "${row:$((b - 1)):1}" != ' ' ]]; then
                    local _ts=$b _te=$b
                    while [[ $_ts -gt 0 && "${row:$((_ts - 1)):1}" != ' ' ]]; do _ts=$((_ts - 1)); done
                    while [[ $_te -lt $rlen && "${row:$_te:1}" != ' ' ]]; do _te=$((_te + 1)); done
                    local _tok="${row:$_ts:$((_te - _ts))}"
                    if [[ "$_tok" =~ ^[0-9][0-9.,]*$ && $((b - _ts)) -lt $((_te - b)) && $_ts -gt $lo ]]; then
                        b=$_ts
                    else
                        b=$_te
                    fi
                fi
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
