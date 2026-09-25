#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: csv
## Description: Extract field names and values from CSV files (comma-delimited with header row)
## Version: 2.0
## Priority: 14
## Sample: samples/csv/basic.csv

# Split one CSV line into _CSV_FIELDS, RFC-4180-style. A double quote is
# STRUCTURAL only at field start (start of line, right after a comma, or after
# only spaces since the comma) — `3/4"` keeps its literal inch mark, while
# `"Cash, operating"` protects its comma. Inside a quoted field `""` is an
# escaped quote. Sets _CSV_OPEN=1 when the line ends inside an open quoted
# field (i.e. the logical record continues on the next physical line).
_strat_csv_split () {
    local line="$1" field="" in_quotes=0 at_start=1 i c
    _CSV_FIELDS=()
    _CSV_OPEN=0
    for ((i=0; i<${#line}; i++)); do
        c="${line:$i:1}"
        if [[ $in_quotes -eq 1 ]]; then
            if [[ "$c" == '"' ]]; then
                if [[ "${line:$((i+1)):1}" == '"' ]]; then
                    field+='"'
                    ((i++))
                else
                    in_quotes=0
                fi
            else
                field+="$c"
            fi
        elif [[ "$c" == '"' && $at_start -eq 1 ]]; then
            in_quotes=1
            at_start=0
        elif [[ "$c" == ',' ]]; then
            _CSV_FIELDS+=("$field")
            field=""
            at_start=1
        else
            field+="$c"
            [[ "$c" != " " ]] && at_start=0
        fi
    done
    _CSV_FIELDS+=("$field")
    _CSV_OPEN=$in_quotes
}

# mawk-safe twin of _strat_csv_split (byte-level: only the ASCII bytes `"`,
# `,` and space are structural, so a multibyte character is copied through
# exactly as the bash character loop copies it). Fills F[1..n], sets OPEN,
# returns n. A line with no `"` splits on every comma — the state machine
# can never enter a quoted field there, so that is the same result.
_STRAT_CSV_AWK_SPLIT='
function csvsplit(line,    n, i, L, c, field, inq, ats) {
    if (index(line, "\"") == 0) { OPEN = 0; return split(line, F, ",") }
    n = 0; field = ""; inq = 0; ats = 1; L = length(line)
    for (i = 1; i <= L; i++) {
        c = substr(line, i, 1)
        if (inq) {
            if (c == "\"") {
                if (substr(line, i + 1, 1) == "\"") { field = field "\""; i++ }
                else inq = 0
            } else field = field c
        } else if (c == "\"" && ats) { inq = 1; ats = 0 }
        else if (c == ",") { F[++n] = field; field = ""; ats = 1 }
        else { field = field c; if (c != " ") ats = 0 }
    }
    F[++n] = field; OPEN = inq
    return n
}'

# _strat_csv_join_awk TEXT — the multi-line-join + empty-line-drop pass of
# strategy_extract in one awk (BIG inputs, see _FR_BIG_BYTES): _CSV_CLEANED
# holds exactly the `_cleaned` string the bash loops build (each kept record
# newline-terminated).
_strat_csv_join_awk () {
    _CSV_CLEANED="$(cat <<< "$1" | awk "$_STRAT_CSV_AWK_SPLIT"'
    function out(s) { if (s != "") print s }
    {
        line = $0
        if (pending != "") {
            pending = pending " " line
            csvsplit(pending)
            if (!OPEN) { out(pending); pending = "" }
        } else {
            csvsplit(line)
            if (OPEN) pending = line; else out(line)
        }
    }
    END { if (pending != "") out(pending) }'; printf .)"
    _CSV_CLEANED="${_CSV_CLEANED%.}"
}

# _strat_csv_emit_awk HEADERLESS < cleaned-text — the row-emission loop of
# strategy_extract in one awk (BIG inputs). Header names arrive already
# trimmed, \034-joined, via ENVIRON; output is byte-identical to the bash
# loop's `result` (sans the trailing newlines $(…) drops anyway).
_strat_csv_emit_awk () {
    _CSV_HL="$1" awk "$_STRAT_CSV_AWK_SPLIT"'
    BEGIN {
        nh = split(ENVIRON["_CSV_HDRS"], H, "\034")
        if (ENVIRON["_CSV_HDRS"] == "") nh = 0
        for (j = 1; j <= nh; j++) {
            nm = H[j]
            gsub(/ /, "_", nm); gsub(/"/, "", nm)
            sub(/^_/, "", nm); sub(/_$/, "", nm)
            gsub(/\./, "_", nm)
            N[j] = nm
        }
        hl = ENVIRON["_CSV_HL"] + 0
    }
    {
        row++
        if (row == 1 && !hl) next
        if ($0 == "") next
        n = csvsplit($0)
        rec++
        for (j = 1; j <= nh; j++) {
            v = (j <= n) ? F[j] : ""
            sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
            if (N[j] == "" || v == "") continue
            printf "entry%d.%s %s\n", rec, N[j], v
        }
    }
    END { if (rec > 0) printf "total_entries %d\n", rec }'
}

# Drop THOUSANDS-SEPARATOR commas — a digit immediately before the comma and
# EXACTLY THREE digits immediately after (not a 4th) — from comma-counting
# only. The "exactly three, not a fourth" requirement is what makes this
# precise: it matches a true grouping comma ("1,234", apt's "[1,234 kB]", a
# status line's "2,341 kB/s") while correctly leaving alone a plain field
# separator that merely happens to sit between two digit-ish tokens, e.g. a
# region id ending in a digit followed by an ungrouped 6-digit count
# ("eu-west-1,881204" — "881" then a 4th digit "2" disqualifies it, so the
# comma stays a real separator). A genuine list/field separator followed by a
# space ("[mean, p95, p99]", "88201, 882.01") never matches at all. Sets
# _CSV_NOTH.
_csv_strip_thousands () {
    local s="$1" out="" i c prev grp after
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:$i:1}"
        if [[ "$c" == ',' ]]; then
            prev="${s:$((i - 1)):1}"
            grp="${s:$((i + 1)):3}"
            after="${s:$((i + 4)):1}"
            if [[ "$prev" =~ [0-9] && "$grp" =~ ^[0-9][0-9][0-9]$ && ! "$after" =~ [0-9] ]]; then
                continue
            fi
        fi
        out+="$c"
    done
    _CSV_NOTH="$out"
}

# RAW comma count of one line (quote-aware split, no paren/thousands
# adjustment) — used only to compare a candidate '#'-header line's shape
# against the data rows below it. Deliberately not run through the
# consistency scan's paren/thousands stripping: those exist to tolerate
# noisy DATA rows over a run of many lines, but would make an unrelated
# line with an incidental "NN,NNN"-shaped pair (e.g. two adjacent plain
# numeric fields) look like a false match against the header here.
_strat_csv_raw_commas () {
    _strat_csv_split "$1"
    printf '%s' "$(( ${#_CSV_FIELDS[@]} - 1 ))"
}

# Strip a leading run of '#'-prefixed comment/metadata lines — a common
# convention for CSV emitted by tools that annotate the file before the real
# header (e.g. `# generated-by ...`, `# tx_size=64 port=5300`). Only lines at
# the very start of the input are stripped; a '#' appearing once real rows
# have begun is left alone (it is data, not a header comment).
#
# haproxy's own CSV convention instead puts the REAL header row itself behind
# a leading '#' (`# pxname,svname,qcur,...`) — that line has the same shape
# (comma count) as the data rows that follow, unlike genuine prose metadata,
# so it is left untouched (kept as the header, '#' and all — the existing
# field-name sanitizer downstream turns it into `#_pxname` as it always has)
# rather than discarded.
#
# No-op (and no _strat_csv_split/shape-comma work at all) unless the input
# actually starts with '#' — every other CSV input takes the pre-existing
# path with zero extra global-state churn from the scan below.
_strat_csv_strip_comments () {
    local text="$1"
    [[ "$text" == \#* ]] || { printf '%s' "$text"; return; }

    local out="" started=0 line
    local first_data=""
    while IFS= read -r line; do
        [[ "$line" == \#* || -z "$line" ]] && continue
        first_data="$line"
        break
    done <<< "$text"
    local data_commas=-1
    [[ -n "$first_data" ]] && data_commas=$(_strat_csv_raw_commas "$first_data")

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Prometheus's own `# HELP ...` / `# TYPE ...` exposition-format
        # comment convention is left alone rather than stripped: the metric
        # lines that follow (`name{label="v",...} value`) have a uniform-
        # enough comma count (from the label list) to otherwise pass the
        # consistency scan below and get wrongly claimed as CSV — the
        # untouched '# HELP'/'# TYPE' line, like any other non-CSV-shaped
        # leading line, is what makes strategy_detect correctly decline.
        if [[ $started -eq 0 && "$line" =~ ^\#[[:space:]]*(HELP|TYPE)[[:space:]] ]]; then
            started=1
            out+="${line}"$'\n'
            continue
        fi
        if [[ $started -eq 0 && "$line" == \#* ]]; then
            if [[ $data_commas -ge 1 && "$(_strat_csv_raw_commas "$line")" -eq $data_commas ]]; then
                out+="${line}"$'\n'
                started=1
            fi
            continue
        fi
        started=1
        out+="${line}"$'\n'
    done
    line=""
    printf '%s' "$out"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _STRATEGY_CONFIDENCE_REASON="consistent comma count across lines"
    # BIG input: both checks below look at no more than the first 10
    # non-blank / 5 non-empty lines, and trailing newlines never reach them
    # (blank lines are skipped). Decide on a whole-line prefix of the text
    # when that prefix holds enough lines to reach every loop's end; the full
    # text only when it does not.
    if (( ${#text} > _FR_BIG_BYTES )) && [[ "$text" != \#* ]]; then
        local _cd_pre="${text:0:65536}" _cd_rc
        if [[ "$_cd_pre" == *$'\n'* ]]; then
            _cd_pre="${_cd_pre%$'\n'*}"
            _CSV_DET_DONE=0
            _strat_csv_detect_body "$_cd_pre" 1 && _cd_rc=0 || _cd_rc=$?
            [[ $_CSV_DET_DONE -eq 1 ]] && return $_cd_rc
        fi
    fi
    _strat_csv_detect_body "$text" 0
}

# The detection proper. With PREFIX=1 the text is a whole-line prefix of the
# input: _CSV_DET_DONE is set to 1 only when every decision was reached
# before the prefix ran out (so the full text would decide the same way).
_strat_csv_detect_body () {
    local text="$1" _cd_prefix="${2:-0}"
    # (no leading `#`: the helper just echoes the text back, so the capture
    # is the text minus trailing newlines — computed here without the fork)
    if [[ "$text" == \#* ]]; then
        text="$(_strat_csv_strip_comments "$text")"
    else
        text="${text%"${text##*[!$'\n']}"}"
    fi

    # TAB-dominant input is tsv's: `aws … --output text` emits TAB fields
    # whose VALUES contain commas ("my-logs, prod"). When every non-blank
    # line carries tabs and the tab count is uniform and >= the comma
    # count, the tabs are the real delimiter — decline so tsv claims it.
    local _td_l _td_n=0 _td_first=-1 _td_uniform=1 _td_tabs _td_commas=0 _td_brk=0
    _fr_lines "$text"
    for _td_l in "${_FR_LINES[@]}"; do
        [[ "${_td_l}" != *[![:space:]]* ]] && continue
        _td_n=$((_td_n + 1))
        local _td_only="${_td_l//[!$'\t']/}"
        _td_tabs=${#_td_only}
        local _td_conly="${_td_l//[!,]/}"
        [[ ${#_td_conly} -gt $_td_commas ]] && _td_commas=${#_td_conly}
        [[ $_td_first -lt 0 ]] && _td_first=$_td_tabs
        [[ $_td_tabs -ne $_td_first || $_td_tabs -eq 0 ]] && { _td_uniform=0; _td_brk=1; break; }
        [[ $_td_n -ge 10 ]] && { _td_brk=1; break; }
    done
    # (prefix run: a loop that ran out of lines might have seen more)
    [[ $_cd_prefix -eq 1 && $_td_brk -eq 0 ]] && return 1
    _CSV_DET_DONE=1
    if [[ $_td_n -ge 2 && $_td_uniform -eq 1 && $_td_first -ge 1 \
          && $_td_first -ge $_td_commas ]]; then
        return 1
    fi

    # Check first 5 non-empty lines for CSV characteristics
    local line_count=0 _cm_brk=0
    local header_commas=0
    local with_commas=0
    local matching=0
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ -z "$_line" ]] && continue
        # Ignore commas inside parenthesised groups — those are not CSV field
        # separators (`mount` options `(rw,nosuid,nodev)`). And ignore
        # THOUSANDS-SEPARATOR commas anywhere (apt's `[1,234 kB]`, a status
        # line's `2,341 kB/s`) — counting only real separator commas keeps
        # csv from claiming such lines just because embedded grouping
        # punctuation happens to produce a similar comma count line-to-line
        # (apt-get's download progress, whose only "consistency" came from
        # repeated `[N,NNN kB]` tags).
        local _sep="${_line//(*)/}"
        _csv_strip_thousands "$_sep"; _sep="$_CSV_NOTH"
        # A comma after a WEEKDAY abbreviation is date punctuation, not a
        # field separator: borg prints `Monday    Mon, 2016-02-15 19:15:11`
        # and that lone consistent comma made a two-column aligned table
        # detect as 2-field CSV at 90 — with the split landing INSIDE the
        # timestamp. Strip them for counting only; extract never runs when
        # detection declines.
        local _wd
        for _wd in Mon Tue Wed Thu Fri Sat Sun; do
            _sep="${_sep//"$_wd, "/$_wd }"
        done
        # Count only commas OUTSIDE quoted fields: a quoted value's embedded
        # commas ("1,234,567.89", "go,api,server") are data, not separators.
        # Without this, quoted CSV fails the consistency check below and falls
        # through to a worse parser.
        _strat_csv_split "$_sep"
        local c=$(( ${#_CSV_FIELDS[@]} - 1 ))
        if [[ $line_count -eq 0 ]]; then
            # First line must have commas
            [[ $c -eq 0 ]] && return 1
            # Decline colon-delimited "key: value" lines whose commas are just
            # prose inside the value (e.g. `file` output: "name: desc, more, ...").
            # A `: ` before the first comma means this belongs to colons, not csv.
            local _before="${_sep%%,*}"
            [[ "$_before" == *": "* ]] && return 1
            header_commas=$c
        fi
        if [[ $c -gt 0 ]]; then
            with_commas=$((with_commas + 1))
            local diff=$(( header_commas - c ))
            if [[ ${diff#-} -le 1 ]]; then
                matching=$((matching + 1))
            fi
        fi
        line_count=$((line_count + 1))
        [[ $line_count -ge 5 ]] && { _cm_brk=1; break; }
    done
    [[ $_cd_prefix -eq 1 && $_cm_brk -eq 0 ]] && { _CSV_DET_DONE=0; return 1; }
    [[ $line_count -lt 2 ]] && return 1

    # Real CSV: most lines should have commas (allow at most 1 without)
    [[ $with_commas -lt $((line_count - 1)) ]] && return 1

    # Of lines with commas, most should have consistent counts
    local threshold=3
    if [[ $with_commas -lt 3 ]]; then
        threshold=$with_commas
    fi
    [[ $matching -ge $threshold ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    # Strip UTF-8 BOM if present (EF BB BF)
    local bom
    bom=$'\xef\xbb\xbf'
    # (prefix test first: a non-matching `#"$bom"` scans every prefix — quadratic)
    if [[ "$text" == "$bom"* ]]; then text="${text#"$bom"}"; fi
    # (no leading `#`: the helper just echoes the text back, so the capture
    # is the text minus trailing newlines — computed here without the fork)
    if [[ "$text" == \#* ]]; then
        text="$(_strat_csv_strip_comments "$text")"
    else
        text="${text%"${text##*[!$'\n']}"}"
    fi

    # Pre-process: join multi-line quoted fields. A line whose RFC-4180 parse
    # ends inside an OPEN quoted field continues on the next physical line.
    # (Counting raw quote parity here would misfire on literal mid-field quotes
    # — `3/4",100` is a complete row, not a continuation.)
    local processed=""
    local pending=""
    local _csv_big=0
    (( ${#text} > _FR_BIG_BYTES )) && _csv_big=1
    if [[ $_csv_big -eq 1 ]]; then
        # BIG input: the join + empty-line pass below, in one awk
        _strat_csv_join_awk "$text"
        _FR_LINES=(); _FR_LINES_OK=0
    else
        _fr_lines "$text"
    fi
    for line in "${_FR_LINES[@]}"; do
        if [[ -n "$pending" ]]; then
            pending+=" ${line}"
            _strat_csv_split "$pending"
            if [[ $_CSV_OPEN -eq 0 ]]; then
                processed+="${pending}"$'\n'
                pending=""
            fi
        else
            _strat_csv_split "$line"
            if [[ $_CSV_OPEN -eq 1 ]]; then
                pending="$line"
            else
                processed+="${line}"$'\n'
            fi
        fi
    done
    line=""
    if [[ -n "$pending" ]]; then
        processed+="${pending}"$'\n'
    fi
    # Remove empty lines
    local _cleaned=""
    if [[ $_csv_big -eq 1 ]]; then
        _cleaned="$_CSV_CLEANED"; _CSV_CLEANED=""
    else
        _fr_lines "$processed"
        for _line in "${_FR_LINES[@]}"; do
            [[ -z "$_line" ]] && continue
            _cleaned+="$_line"$'\n'
        done
    fi
    _line=""
    text="$_cleaned"

    # Parse header row for field names
    local header=""
    # (the first line of `text` — the read-loop form re-read a here-string of
    # the whole input just to take line 1)
    header="${text%%$'\n'*}"

    # Split header quote-aware too — `"Last, First",Dept` is two columns, and a
    # naive IFS=',' split would misalign every data row against it.
    local headers; headers=()
    _strat_csv_split "$header"
    headers=("${_CSV_FIELDS[@]}")

    # Headerless numeric CSV — data loggers (fio --write_bw_log / --write_iops_log,
    # `sar -o` CSV, collectd) emit raw rows with no header. If the FIRST row's
    # fields are all numeric, there is no header (a real header carries
    # non-numeric column names): synthesise A,B,C… and keep row 1 as data.
    local _headerless=1
    [[ ${#headers[@]} -lt 2 ]] && _headerless=0
    local _hf
    for _hf in "${headers[@]}"; do
        _hf="${_hf#"${_hf%%[![:space:]]*}"}"; _hf="${_hf%"${_hf##*[![:space:]]}"}"
        [[ -z "$_hf" || "$_hf" =~ ^-?[0-9]+([.][0-9]+)?%?$ ]] || { _headerless=0; break; }
    done
    # DUAL-ROW SHAPE test — a header names its columns, so somewhere row 1
    # must be LABEL-shaped over a differently-shaped value (`age` over `30`).
    # When every column has the SAME shape in rows 1 and 2 (both numeric /
    # both IP-ish / both long mixed strings) AND at least one column is
    # value-shaped, row 1 is data (`Simple mixer control 'Master',0` over
    # `…'Headphone',0` — amixer). Pure label-over-label tables (all-text,
    # no value shapes anywhere) keep their header.
    if [[ $_headerless -eq 0 && ${#headers[@]} -ge 2 ]]; then
        local _dr2="" _dri=0 _drl
        # `text` holds only non-empty, newline-terminated lines, so the second
        # non-empty line is simply line 2.
        if [[ "$text" == *$'\n'?* ]]; then
            _dr2="${text#*$'\n'}"; _dr2="${_dr2%%$'\n'*}"
        fi
        if [[ -n "$_dr2" ]]; then
            _strat_csv_split "$_dr2"
            local _drv=("${_CSV_FIELDS[@]}")
            _csv_shape () {
                local v="$1"
                v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
                if [[ "$v" =~ ^-?[0-9]+([.][0-9]+)?[a-zA-Z%]{0,4}$ ]]; then echo num
                elif [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo ip
                elif [[ "$v" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} || "$v" =~ ^[0-9]{1,2}:[0-9]{2} ]]; then echo date
                else echo str
                fi
            }
            if [[ ${#_drv[@]} -eq ${#headers[@]} ]]; then
                local _drj _drcontrast=0 _drvaluish=0 _drs1 _drs2
                for ((_drj = 0; _drj < ${#headers[@]}; _drj++)); do
                    _drs1="$(_csv_shape "${headers[$_drj]}")"
                    _drs2="$(_csv_shape "${_drv[$_drj]:-}")"
                    [[ "$_drs1" == str && "$_drs2" != str ]] && _drcontrast=1
                    [[ "$_drs1" != str ]] && _drvaluish=1
                done
                [[ $_drcontrast -eq 0 && $_drvaluish -eq 1 ]] && _headerless=1
            fi
        fi
    fi
    if [[ $_headerless -eq 1 ]]; then
        local _hn=${#headers[@]} _hk
        headers=()
        for ((_hk=1; _hk<=_hn; _hk++)); do headers+=("$(_col_letter "$_hk")"); done
    fi

    # Clean BOM and whitespace from header names
    local hi
    for ((hi=0; hi<${#headers[@]}; hi++)); do
        local _h="${headers[$hi]}"
        while [[ "$_h" == " "* || "$_h" == "	"* ]]; do _h="${_h#?}"; done
        while [[ "$_h" == *" " || "$_h" == *"	" ]]; do _h="${_h%?}"; done
        headers[$hi]="$_h"
    done

    # Process each data row. Each row is emitted as an indexed record group
    # (entry<N>.<column>) so the capture tidy melt renders one row per record
    # with shared columns — rather than welding every row's cells into a single
    # wide record with duplicate column names (where the format layer would even
    # drop a later row's field that repeats an earlier row's value).
    local result=""
    local row_num=0
    local rec=0
    if [[ $_csv_big -eq 1 ]]; then
        local _csv_hdrs _csv_h
        printf -v _csv_hdrs '%s\034' "${headers[@]}"
        _csv_hdrs="${_csv_hdrs%$'\034'}"
        # a \034 inside a header name would mis-split: keep the bash loop
        if [[ "${headers[*]}" != *$'\034'* ]]; then
            cat <<< "$text" | _CSV_HDRS="$_csv_hdrs" _strat_csv_emit_awk "$_headerless"
            return 0
        fi
    fi
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 && $_headerless -eq 0 ]] && continue  # skip header (unless headerless)
        [[ -z "$line" ]] && continue

        # Parse the line field by field (same RFC-4180 splitter as the header:
        # quotes structural only at field start, "" escapes, literal otherwise)
        local values; values=()
        _strat_csv_split "$line"
        values=("${_CSV_FIELDS[@]}")

        rec=$((rec + 1))
        local j
        for ((j=0; j<${#headers[@]}; j++)); do
            local name="${headers[$j]}"
            local value="${values[$j]:-}"
            # Clean up name and value
            name="${name// /_}"
            name="${name//\"/}"
            name="${name#_}"
            name="${name%_}"
            name="${name//./_}"   # '.' would break the tidy melt's group key split
            # NOTE: no blanket quote-strip on the value — the splitter already
            # consumed the structural quotes, so any quote still present is
            # literal data (3/4" inch marks, escaped "" quotes).
            # Trim leading/trailing whitespace (the header fields are trimmed the
            # same way above) so a ", value" delimiter's space isn't turned into a
            # leading underscore by the space->underscore step below.
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done
            [[ -z "$name" ]] && continue
            [[ -z "$value" ]] && continue
            result+="entry${rec}.${name} ${value}"$'\n'
        done
    done
    line=""

    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
