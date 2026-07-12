#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 3.1
## Priority: 55
## Sample: samples/aligned-columns/basic.txt

# Count a line's 2-space-gap segments — the columns a fixed-width header defines
# (a multi-word cell like "Best Rate MB/s" is ONE segment; only a >=2-space gap
# starts a new one).
_ac_seg () {
    local l="$1" n=0 i=0 L
    l="${l#"${l%%[![:space:]]*}"}"; L=${#l}
    while (( i < L )); do
        while (( i < L )) && [[ "${l:i:1}" == " " ]]; do ((i++)); done
        (( i >= L )) && break
        ((n++))
        while (( i < L )) && ! { [[ "${l:i:1}" == " " ]] && [[ "${l:i+1:1}" == " " ]]; }; do ((i++)); done
    done
    printf '%s' "$n"
}

# Is the token a value (number/size/%/time/version — anything starting with a
# digit)? A header label never does.
_ac_is_value () { [[ "$1" =~ ^[0-9] ]]; }

# Echo the block with leading preamble removed: an `ls -l` "total <n>" line, or
# short banner/preamble lines with <2 columns (e.g. `apt list`'s "Listing…"),
# but only when a real (>=2 column) table follows.
_ac_body () {
    local text="$1" _l _tk out="" started=0 has_table=0
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        _tk=(); read -ra _tk <<< "$_l"
        [[ ${#_tk[@]} -ge 2 ]] && { has_table=1; break; }
    done <<< "$text"

    # The modal (most common) token count of the block — used to spot leading
    # banner lines that are much wider than the table that follows (`w`'s
    # load-average line, numastat's title). Only lines wider by >=3 tokens are
    # banners; a leading line with FEWER tokens can be a group-header row
    # (vmstat) and must stay.
    local _modal=0
    if [[ $has_table -eq 1 ]]; then
        local _mc=() _mn=0
        while IFS= read -r _l; do
            [[ -z "${_l//[[:space:]]/}" ]] && continue
            _tk=(); read -ra _tk <<< "$_l"
            _mc+=("${#_tk[@]}"); _mn=$((_mn + 1)); [[ $_mn -ge 40 ]] && break
        done <<< "$text"
        local _a _b _k _best=0
        for _a in "${_mc[@]}"; do
            _k=0; for _b in "${_mc[@]}"; do [[ "$_b" -eq "$_a" ]] && _k=$((_k + 1)); done
            [[ $_k -gt $_best ]] && { _best=$_k; _modal=$_a; }
        done
        # A banner is only recognisable against a real consensus: most of the
        # block (>=65%) must share the modal count, or a wide first line is
        # just one more ragged row (samtools flagstat), not chrome.
        [[ $_best -lt 2 || $(( _best * 100 / _mn )) -lt 65 ]] && _modal=0
    fi

    # A section title — the FIRST line, ending with `:`, set off by a blank
    # line before the table ("Current machine states:", `vagrant status`) —
    # is chrome, not data. Identified by lookahead here, dropped in the loop.
    local _title="" _prev="" _seenfirst=0
    if [[ $has_table -eq 1 ]]; then
        while IFS= read -r _l; do
            if [[ $_seenfirst -eq 0 ]]; then
                [[ -z "${_l//[[:space:]]/}" ]] && continue
                _seenfirst=1; _prev="$_l"; continue
            fi
            [[ -z "${_l//[[:space:]]/}" && "$_prev" =~ :[[:space:]]*$ ]] && _title="$_prev"
            break
        done <<< "$text"
    fi

    # A title banner in front of a FIXED-WIDTH table (STREAM's "STREAM version
    # 5.10", blender's "Blender 4.2.0 Benchmark", kdiskmark's "KDiskMark 3.1.4")
    # — a leading single-column line (seg<2) or decorated rule, followed by an
    # ALL-LABEL header over NUMERIC data. Both the all-label header and the
    # numeric data are required so this never eats a real header that happens to
    # be single-segment ("Installed Packages" over version rows — dnf-list) or a
    # word-data list ("web  running (virtualbox)" — vagrant).
    local _fwbanner=""
    if [[ $has_table -eq 1 ]]; then
        local _fl=() _fx
        while IFS= read -r _fx; do
            [[ -z "${_fx//[[:space:]]/}" ]] && continue
            [[ "$_fx" =~ ^[[:space:]]*[=-]+([[:space:]]+[=-]+)*[[:space:]]*$ ]] && continue
            _fl+=("$_fx"); [[ ${#_fl[@]} -ge 3 ]] && break
        done <<< "$text"
        if [[ ${#_fl[@]} -ge 3 ]]; then
            local _b0="${_fl[0]}" _h1="${_fl[1]}" _d2="${_fl[2]}"
            local _b0seg; _b0seg="$(_ac_seg "$_b0")"
            if [[ ( $_b0seg -lt 2 || "$_b0" == *-----* ) && ! "$_b0" =~ ^[[:space:]]*[{[\<] ]]; then
                # header all-label AND genuinely multi-COLUMN (>=2 two-space
                # segments)? A kv line ("Revision a1b2c3d4", "Author: Name") has
                # one segment and must never count as a fixed-width header.
                local _hlab=1 _ht; _ht=(); read -ra _ht <<< "$_h1"
                [[ ${#_ht[@]} -ge 2 ]] || _hlab=0
                [[ "$(_ac_seg "$_h1")" -ge 2 ]] || _hlab=0
                # every header token must be a real label: contains a letter and
                # is not a value ("========================" in mpirun's decorated
                # "==== JOB MAP ====" row is neither).
                local _t
                for _t in "${_ht[@]}"; do
                    if _ac_is_value "$_t" || [[ ! "$_t" =~ [A-Za-z] ]]; then _hlab=0; break; fi
                done
                # data numeric?
                local _dnum=0 _dt; _dt=(); read -ra _dt <<< "$_d2"
                for _t in "${_dt[@]}"; do _ac_is_value "$_t" && { _dnum=1; break; }; done
                # header and first data row must start at the SAME column — else
                # the header has no column for a data-row label ("Read (MB/s)"
                # indented over unindented "SEQ1M Q8T1 …" — kdiskmark's headerless
                # first column), which positional assignment can only garble.
                local _hind="${_h1%%[![:space:]]*}" _dind="${_d2%%[![:space:]]*}"
                [[ $_hlab -eq 1 && $_dnum -eq 1 && ${#_hind} -eq ${#_dind} ]] && _fwbanner="$_b0"
            fi
        fi
    fi

    # A leading `#`-comment block (conda list, opam list) mixes prose banners with
    # a commented column header. Collect the candidates and, at the first data
    # line, prefer the one whose token count matches the data row and whose
    # tokens are unique (nvidia-smi dmon's `# gpu sm mem …` over its units row
    # `# Idx % % …`); otherwise keep the last (conda's header is last).
    local held=() banner_budget=2
    while IFS= read -r _l; do
        # Drop a pure separator rule up top so a LEADING rule (STREAM /
        # pytest-benchmark bracket their header in rules) doesn't flip `started`
        # and get mistaken for the first table line.
        [[ "$_l" =~ ^[[:space:]]*[=-]+([[:space:]]+[=-]+)*[[:space:]]*$ ]] && continue
        if [[ $started -eq 0 && -n "${_l//[[:space:]]/}" ]]; then
            _tk=(); read -ra _tk <<< "$_l"
            [[ "$_l" =~ ^[[:space:]]*total[[:space:]]+[0-9]+[[:space:]]*$ ]] && continue
            [[ -n "$_fwbanner" && "$_l" == "$_fwbanner" ]] && { _fwbanner=""; continue; }
            [[ -n "$_title" && "$_l" == "$_title" ]] && { _title=""; continue; }
            if [[ "$_l" =~ ^[[:space:]]*# ]]; then
                # Strip the leading `#` (and one following space) — a candidate header.
                local _h="${_l#"${_l%%[!#[:space:]]*}"}"
                [[ -n "${_h//[[:space:]]/}" ]] && held+=("$_h")
                continue
            fi
            # A short word-like preamble line (e.g. `apt list`'s "Listing…") before
            # a real table — but NOT a `{`/`[`/`<` structural line (JSON/XML), which
            # must keep aligned-columns from matching those formats.
            [[ $has_table -eq 1 && ${#_tk[@]} -lt 2 && "$_l" =~ ^[[:space:]]*[A-Za-z] ]] && continue
            # A leading progress line — any token ending in an ellipsis
            # ("Listing... Done") — is chrome before the table, not data.
            [[ $has_table -eq 1 && "$_l" =~ \.\.\.([[:space:]]|$) && ${#_tk[@]} -le 3 ]] && continue
            # A leading banner line much WIDER than the table (>=3 tokens over
            # the modal count): drop it (max 2 such lines). Chrome carries
            # numbers (`w`'s uptime/load line, numastat's PID title), so the
            # line must hold a VALUE token — a wide all-label header row
            # (kubectl get pv) never does. Chrome is also not: a `label :
            # value` line (in `chage -l` a wide pair is data), a line ending
            # in a period (prose data — poetry's root-package row), or a line
            # OPENING WITH THE SAME TOKEN as a table row (telegraf's log
            # stream — same-shaped lines are the table itself).
            if [[ $banner_budget -gt 0 && $_modal -ge 2 && ${#_tk[@]} -ge $((_modal + 3)) \
                  && "$_l" =~ ^[[:space:]]*[A-Za-z0-9] && ! "$_l" =~ \.[[:space:]]*$ \
                  && ! "$_l" =~ ^[[:space:]]*[A-Za-z][^:=]*:[[:space:]] ]]; then
                local _bt _bv=0 _bsame=0 _bl2 _bt2
                for _bt in "${_tk[@]}"; do
                    [[ "$_bt" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_bt" =~ ^[0-9]{1,2}:[0-9]{2} \
                       || "$_bt" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_bt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && { _bv=1; break; }
                done
                if [[ $_bv -eq 1 ]]; then
                    while IFS= read -r _bl2; do
                        [[ -z "${_bl2//[[:space:]]/}" || "$_bl2" == "$_l" ]] && continue
                        _bt2=(); read -ra _bt2 <<< "$_bl2"
                        [[ "${_bt2[0]:-}" == "${_tk[0]}" ]] && { _bsame=1; break; }
                    done <<< "$text"
                    if [[ $_bsame -eq 0 ]]; then
                        banner_budget=$((banner_budget - 1))
                        continue
                    fi
                fi
            fi
            # First real line: emit the best held commented header (if any) —
            # but only a candidate whose token count fits the data (exact, or
            # one under for a trailing multi-word label). A lone `# <path>`
            # provenance comment (ansible-galaxy) fits nothing and is dropped.
            if [[ ${#held[@]} -gt 0 ]]; then
                local _pick="" _c _ct _u _t2
                for _c in "${held[@]}"; do
                    _ct=(); read -ra _ct <<< "$_c"
                    [[ ${#_ct[@]} -ne ${#_tk[@]} ]] && continue
                    _u=1; local -A _seen_tok=()
                    for _t2 in "${_ct[@]}"; do [[ -n "${_seen_tok[$_t2]:-}" ]] && { _u=0; break; }; _seen_tok[$_t2]=1; done
                    [[ $_u -eq 1 ]] && { _pick="$_c"; break; }
                done
                [[ -z "$_pick" ]] && _pick="${held[${#held[@]}-1]}"
                [[ -n "$_pick" ]] && out+="$_pick"$'\n'
            fi
            started=1
        fi
        out+="$_l"$'\n'
    done <<< "$text"

    # Drop a trailing summary line like "4 sessions listed." / "5 loaded units
    # listed." so it isn't counted as a data row.
    local body="${out%$'\n'}" last
    last="${body##*$'\n'}"
    if [[ "$body" == *$'\n'* \
          && "$last" =~ ^[[:space:]]*[0-9]+[[:space:]]+([A-Za-z]+[[:space:]]+)*(listed|shown|found)\.?[[:space:]]*$ ]]; then
        out="${body%$'\n'*}"$'\n'
    fi
    printf '%s' "$out"
}

# Analyse a block as a whitespace-columnar table. Prints "<mode> <ncols>":
#   HDR  n — first non-blank line is a label header (n columns)
#   HDR2 n — two-line header (group row + field row); field row has n columns
#   HL   n — headerless table (synthesise c1..cN); n = modal column count
# Prints nothing (returns 1) if the block isn't a consistent columnar table.
#
# Header vs headerless: a header row is labels; data rows carry more pure-numeric
# tokens (counts, sizes, percentages) than the header. So the block has a header
# when row 2 has more pure-numeric tokens than row 1 — this correctly treats
# `df -T` (whose header label `1K-blocks` merely contains a digit) as having a
# header, while `who`/`mount` (no numeric columns) stay headerless. Headerless
# needs >=3 consistent columns so it can't swallow 2-column key/value input.
_ac_shape () {
    local text; text="$(_ac_body "$1")"
    local counts=() dcount=() idx=0 _line first_line=""
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        [[ $idx -eq 1 ]] && first_line="$_line"
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        counts+=("${#_tk[@]}")
        local d=0 t
        for t in "${_tk[@]}"; do [[ "$t" =~ [0-9] ]] && d=$((d + 1)); done
        dcount+=("$d")
        [[ $idx -ge 40 ]] && break
    done <<< "$text"

    local nlines=${#counts[@]}
    [[ $nlines -lt 2 ]] && return 1
    [[ ${counts[0]} -lt 2 ]] && return 1

    # Two-line header: rows 1-2 are label rows (no digit tokens), the field row has
    # more columns, and numeric data starts on row 3 — vmstat, some sar layouts.
    if [[ $nlines -ge 3 && ${dcount[0]} -eq 0 && ${dcount[1]} -eq 0 \
          && ${dcount[2]} -gt 0 && ${counts[1]} -gt ${counts[0]} ]]; then
        printf 'HDR2 %s\n' "${counts[1]}"
        return 0
    fi

    # Header detection. Row 1 is a label header when either:
    #   (a) it is an ALL-CAPS label row (systemctl/kubectl/ps — all-text tables), or
    #   (b) it contains no *value* token (a bare number, time, IP or date) while the
    #       data rows are more numeric than it. This treats df-T (header label
    #       `1K-blocks` is not a value) and free-h (unit values `7.8Gi`) as headed,
    #       but keeps log/record blocks headerless (who, mount, ip route, journalctl,
    #       last — whose first line already carries times/IPs/counts).
    # ALL-CAPS needs a letter: a purely numeric first row (`redis-cli --latency
    # -history`'s "1751880000 2") has no lowercase but is data, not a header.
    local caps0=0; [[ ! "$first_line" =~ [a-z] && "$first_line" =~ [A-Z] ]] && caps0=1
    local v0=0 _t _t1arr; _t1arr=(); read -ra _t1arr <<< "$first_line"
    for _t in "${_t1arr[@]}"; do
        # value token = a number, optionally with a trailing unit (8.421s, 942ms,
        # 7.8Gi, 39%), or a time / IP / date. `1K-blocks` is NOT one (the hyphen),
        # so a df-T-style header label stays a header.
        [[ "$_t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_t" =~ ^[0-9]{1,2}:[0-9]{2} \
           || "$_t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && v0=$((v0 + 1))
    done
    # Row 1 is a header when it is a pure label row (zero digit tokens) over
    # data that carries digits anywhere (az/aws listings — one digit-bearing
    # row is enough); when it is digit-free of VALUE tokens while most data
    # rows carry one (a number, time, IP or date — `multipass list`, whose
    # header label IPv4 merely contains a digit); or — when row 1 itself has
    # digit tokens (`1K-blocks`) — when MOST data rows are more numeric than
    # it. The majority requirements stop a headerless log (`git log
    # --oneline`) from having its first commit promoted just because one
    # later row carries an extra digit token (CVE-2026-1101).
    local moren=0 maxd=0 vrows=0 i
    local _dl _dt _dtk
    i=0
    while IFS= read -r _dl; do
        [[ -z "${_dl//[[:space:]]/}" ]] && continue
        i=$((i + 1))
        [[ $i -eq 1 ]] && continue
        _dtk=(); read -ra _dtk <<< "$_dl"
        for _dt in "${_dtk[@]}"; do
            if [[ "$_dt" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_dt" =~ ^[0-9]{1,2}:[0-9]{2} \
                 || "$_dt" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_dt" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
                vrows=$((vrows + 1)); break
            fi
        done
        [[ $i -ge 40 ]] && break
    done <<< "$(_ac_body "$1")"
    for ((i = 1; i < nlines; i++)); do
        [[ ${dcount[$i]} -gt ${dcount[0]} ]] && moren=$((moren + 1))
        [[ ${dcount[$i]} -gt $maxd ]] && maxd=${dcount[$i]}
    done
    # All promotion paths also demand the row LOOKS like labels: every token
    # carries an alphanumeric (not `----`), none is bracketed (`[Hardware`,
    # `event]` — perf-list data), and none ends in `.` (prose — "…sysfs.").
    # Header labels with `:`/`(`/`#`/`%` (ss's Address:Port, vgs's #PV,
    # kubectl's CPU(cores)) all pass.
    # Bare single-char separators inside a header (`database | user`,
    # `# reqs`, `Total / Used`) are skipped — they are layout, not content.
    local labelly=1 _lbl_seen=0
    for _t in "${_t1arr[@]}"; do
        [[ "$_t" =~ ^[\|#/%+-]$ ]] && continue
        _lbl_seen=1
        [[ "$_t" =~ [A-Za-z0-9] && ! "$_t" =~ ^\[ && ! "$_t" =~ \]$ && ! "$_t" =~ \.$ ]] || { labelly=0; break; }
    done
    [[ $_lbl_seen -eq 0 ]] && labelly=0
    if [[ $caps0 -eq 1 || ( $v0 -eq 0 && ${dcount[0]} -eq 0 && $labelly -eq 1 && $maxd -gt 0 ) \
          || ( $v0 -eq 0 && $labelly -eq 1 && $vrows -gt 0 && $vrows -eq $((nlines - 1)) ) \
          || ( $v0 -eq 0 && $labelly -eq 1 && $(( moren * 2 )) -gt $((nlines - 1)) ) ]]; then
        printf 'HDR %s\n' "${counts[0]}"
        return 0
    fi

    # All-text table (no digits anywhere): numeric contrast can't identify the
    # header, but wording can — row 1 is a header when every token is a bare
    # word (letters only, no path/host/option punctuation) and none of them
    # recurs in row 2 (labels don't repeat as values). This promotes
    # `Package Ecosystem Severity State` / `database tableName isTemporary`
    # while `mount`/`retroarch`-style all-text records (slashes, dashes,
    # repeated words) stay headerless.
    local alltext=1
    for ((i = 0; i < nlines; i++)); do [[ ${dcount[$i]} -gt 0 ]] && { alltext=0; break; }; done
    if [[ $v0 -eq 0 && $alltext -eq 1 && $nlines -ge 3 ]]; then
        local wordy=1 styled=0
        for _t in "${_t1arr[@]}"; do [[ "$_t" =~ ^[A-Za-z][A-Za-z0-9_%]*$ ]] || { wordy=0; break; }; done
        # Labels are STYLED words — Titlecase (`Package`) or camelCase
        # (`tableName`); an all-lowercase row (`sqlite3 .tables` name grid)
        # is data, not a header.
        for _t in "${_t1arr[@]}"; do [[ "$_t" =~ ^[A-Z][a-z] || "$_t" =~ [a-z][A-Z] ]] && { styled=1; break; }; done
        # And the data under it must be TABLE-shaped: a modal column count
        # covering >=60% of the data rows, within 1 of the header's own count
        # (multi-word labels run one over). Ragged prose (`dolt status`,
        # whose "On branch main" is a sentence) fails this.
        local shaped=0
        if [[ $wordy -eq 1 && $styled -eq 1 ]]; then
            local _dm=0 _db=0 _da _dbn
            for ((i = 1; i < nlines; i++)); do
                _dbn=0
                for ((_da = 1; _da < nlines; _da++)); do [[ ${counts[$_da]} -eq ${counts[$i]} ]] && _dbn=$((_dbn + 1)); done
                [[ $_dbn -gt $_db ]] && { _db=$_dbn; _dm=${counts[$i]}; }
            done
            local _hd=$(( counts[0] - _dm )); [[ $_hd -lt 0 ]] && _hd=$(( -_hd ))
            [[ $(( _db * 100 / (nlines - 1) )) -ge 60 && $_hd -le 1 ]] && shaped=1
            # `Name Description` over wider free-text rows (spin templates):
            # a 2-label header with a consistent, much wider body is the
            # name+description family — positional assignment reunites the
            # description column downstream.
            [[ $(( _db * 100 / (nlines - 1) )) -ge 60 && ${counts[0]} -eq 2 && $_dm -ge 4 ]] && shaped=1
        fi
        if [[ $shaped -eq 1 ]]; then
            local second_line="" idx2=0
            while IFS= read -r _line; do
                [[ -z "${_line//[[:space:]]/}" ]] && continue
                idx2=$((idx2 + 1)); [[ $idx2 -eq 2 ]] && { second_line="$_line"; break; }
            done <<< "$text"
            local overlap=0 _t2 _t2arr; _t2arr=(); read -ra _t2arr <<< "$second_line"
            for _t in "${_t1arr[@]}"; do
                for _t2 in "${_t2arr[@]}"; do [[ "$_t" == "$_t2" ]] && { overlap=1; break 2; }; done
            done
            [[ $overlap -eq 0 ]] && { printf 'HDR %s\n' "${counts[0]}"; return 0; }
        fi
    fi

    # Headerless: require a modal column count (>=3) shared by most lines.
    local mode=0 best=0 c d k
    for c in "${counts[@]}"; do
        k=0
        for d in "${counts[@]}"; do [[ "$d" -eq "$c" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; mode=$c; }
    done
    if [[ $mode -eq 2 && $nlines -ge 3 && $(( best * 100 / nlines )) -ge 60 ]]; then
        # A strict 2-column block is a table (not prose / key-value) only when
        # its tokens are VALUES: pure numbers or strings carrying separator
        # punctuation (paths, module@version, timestamps) — `go mod graph`,
        # redis latency history. Prose and `Key value` snapshots don't qualify.
        local vlike=0 tot=0 _ln
        while IFS= read -r _ln; do
            [[ -z "${_ln//[[:space:]]/}" ]] && continue
            _t1arr=(); read -ra _t1arr <<< "$_ln"
            for _t in "${_t1arr[@]}"; do
                tot=$((tot + 1))
                [[ "$_t" =~ ^[0-9][0-9.,:%-]*$ || "$_t" == */* || "$_t" == *@* || "$_t" == *:* ]] && vlike=$((vlike + 1))
            done
        done <<< "$text"
        [[ $tot -gt 0 && $(( vlike * 100 / tot )) -ge 75 ]] && { printf 'HL 2\n'; return 0; }
    fi
    [[ $mode -lt 3 ]] && return 1
    [[ $(( best * 100 / ${#counts[@]} )) -lt 60 ]] && return 1
    printf 'HL %s\n' "$mode"
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Decline space-padded assignment blocks — `KEY = value`, `KEY(ctx) = value`
    # (e.g. `ansible-config dump`). The ` = ` is a separator, not a data column;
    # aligned-columns would split it into a bogus middle column and mangle any
    # value with inner spaces. The equals parser tidies these to one field per key.
    local _eq=0 _et=0 _el
    while IFS= read -r _el; do
        [[ -z "${_el//[[:space:]]/}" ]] && continue
        _et=$((_et + 1))
        [[ "$_el" == *" = "* ]] && _eq=$((_eq + 1))
    done <<< "$text"
    [[ $_et -ge 2 && $(( _eq * 100 / _et )) -ge 80 ]] && return 1

    # Decline pure key/value blocks — `label : value` / `label: value` (e.g.
    # `pacman -Qi`, `rpm -qi`) or `Key=Value` (e.g. `systemctl show`). These are
    # single-record snapshots the colons/equals parsers tidy to one wide row;
    # aligned-columns would wrongly split them into a ragged 2-column table.
    # But a consistent multi-column table whose rows happen to end in a `label:`
    # (e.g. `/proc/softirqs` "HI:  0 0 0", `lsusb` "… Device 002: ID …") is a real
    # table — so only decline when the block is RAGGED (no dominant column count),
    # which is what a genuine key/value block looks like.
    local _nb=0 _kv=0 _cl _cc=() _ct
    while IFS= read -r _cl; do
        [[ -z "${_cl//[[:space:]]/}" ]] && continue
        _nb=$((_nb + 1))
        if [[ "$_cl" =~ ^[[:space:]]*[A-Za-z][^:=]*:[[:space:]] \
              || "$_cl" =~ ^[[:space:]]*[A-Za-z][A-Za-z0-9_]*= ]]; then
            _kv=$((_kv + 1))
        fi
        _ct=(); read -ra _ct <<< "$_cl"; _cc+=("${#_ct[@]}")
    done <<< "$text"
    if [[ $_nb -ge 2 && $(( _kv * 100 / _nb )) -ge 80 ]]; then
        # Modal column count: a strong, consistent ≥3-column shape means a table,
        # not a kv block — keep it with aligned-columns.
        local _m=0 _best=0 _a _b _k
        for _a in "${_cc[@]}"; do
            _k=0; for _b in "${_cc[@]}"; do [[ "$_b" -eq "$_a" ]] && _k=$((_k + 1)); done
            [[ $_k -gt $_best ]] && { _best=$_k; _m=$_a; }
        done
        [[ $_m -ge 3 && $(( _best * 100 / _nb )) -ge 60 ]] || return 1
    fi

    # Structural detection: a header row (or a headerless block) of columns with
    # a consistent count. Recognises the whole class of whitespace-columnar tool
    # output (ps, df, ss, iostat, netstat, top, lsblk, systemctl, mount, who,
    # vmstat, ls -l …) without a per-tool rule. Confidence scales with column
    # consistency so a clean table outranks the key/value parsers.
    local shape; shape="$(_ac_shape "$text")" || return 1
    local mode="${shape%% *}" n_h="${shape##* }"
    local hdr_lines=1
    case "$mode" in HL) hdr_lines=0 ;; HDR) hdr_lines=1 ;; HDR2) hdr_lines=2 ;; esac

    local idx=0 data_rows=0 consistent=0 header_caps=1 _line
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        local n=${#_tk[@]}
        if [[ $idx -le $hdr_lines ]]; then
            if [[ $idx -eq $hdr_lines ]]; then
                local t
                for t in "${_tk[@]}"; do [[ "$t" =~ [a-z] ]] && header_caps=0; done
            fi
            continue    # header row(s) are not data rows
        fi
        [[ $n -ge 2 ]] && data_rows=$((data_rows + 1))
        [[ $n -ge $((n_h - 1)) ]] && consistent=$((consistent + 1))
        [[ $idx -ge 40 ]] && break
    done <<< "$(_ac_body "$text")"
    [[ "$mode" == HL ]] && header_caps=0

    [[ $data_rows -lt 1 ]] && return 1

    local conf=40
    [[ $data_rows -ge 2 ]] && conf=$((conf + 10))
    conf=$((conf + consistent * 20 / data_rows))   # column-consistency bonus (0..20)
    [[ $header_caps -eq 1 ]] && conf=$((conf + 5))  # ALL-CAPS header (ps/df/ss style)
    [[ "$mode" == HL ]] && conf=$((conf - 10))      # headerless is a weaker signal
    [[ $conf -gt 75 ]] && conf=75
    [[ $conf -lt 1 ]] && conf=1
    _STRATEGY_CONFIDENCE=$conf
    return 0
}

# Is the block cleanly column-aligned to its header? (first input line = header).
# A data row is aligned when the character just before each header column start
# is whitespace — i.e. no value bleeds across a header column boundary. Prints
# "1" when >=80% of data rows are aligned and the header has >=2 columns, else
# "0". Only cleanly-aligned tables (docker/kubectl/helm) get positional parsing;
# irregular / right-aligned-overflow tables (ps/df/vmstat) stay on tokenization.
_ac_aligned () {
    awk '
    NR==1 {
        hl=$0; L=length(hl); i=1; nc=0
        while (i<=L) {
            while (i<=L && substr(hl,i,1)==" ") i++
            if (i>L) break
            nc++; cstart[nc]=i
            while (i<=L && !(substr(hl,i,1)==" " && substr(hl,i+1,1)==" ")) i++
        }
        next
    }
    {
        ndata++; ok=1
        for (c=2;c<=nc;c++) {
            ch=substr($0,cstart[c]-1,1)
            if (ch!="" && ch!=" ") { ok=0; break }
        }
        if (ok) aligned++
    }
    END {
        if (nc<2 || ndata==0) { print "0"; exit }
        if (aligned*100/ndata >= 80) print "1"; else print "0"
    }'
}

# Positional token assignment for a cleanly-aligned block. First input line is the
# header; its 2+-space fields define column start positions. Each line's tokens
# are assigned to the column region [cstart_i, cstart_{i+1}) their start falls in,
# so a multi-word cell ("2 weeks ago" under CREATED) is rejoined and a multi-word
# header ("IMAGE ID") names a single column. Emits TAB-separated cells per line.
_ac_assign () {
    awk '
    NR==1 {
        hl=$0; L=length(hl); i=1; nc=0
        while (i<=L) {
            while (i<=L && substr(hl,i,1)==" ") i++
            if (i>L) break
            nc++; cstart[nc]=i
            while (i<=L && !(substr(hl,i,1)==" " && substr(hl,i+1,1)==" ")) i++
        }
        cstart[nc+1]=1000000
    }
    {
        line=$0; L=length(line); i=1
        for (c=1;c<=nc;c++) cell[c]=""
        while (i<=L) {
            while (i<=L && substr(line,i,1)==" ") i++
            if (i>L) break
            ts=i; tok=""
            while (i<=L && substr(line,i,1)!=" ") { tok=tok substr(line,i,1); i++ }
            col=1
            for (c=1;c<=nc;c++) { if (cstart[c]<=ts) col=c; else break }
            if (cell[col]=="") cell[col]=tok; else cell[col]=cell[col] " " tok
        }
        out=cell[1]
        for (c=2;c<=nc;c++) out=out "\t" cell[c]
        print out
    }'
}

# Split a line into cells at runs of >=2 spaces (the same column boundary a
# fixed-width table uses), keeping a single-spaced multi-word cell intact ("1.0
# TiB", "RAW USE", "pid 8821, uptime 2:14:08"). Emits TAB-separated cells. This
# is `_ac_seg` as a splitter — used for right-aligned numeric tables whose values
# carry inner spaces, which positional (start-of-column) assignment can't align.
_ac_split () {
    awk '{
      line=$0; L=length(line); i=1; nc=0; out=""; cur=""
      while(i<=L && substr(line,i,1)==" ") i++
      while(i<=L){
        if(substr(line,i,1)==" " && substr(line,i+1,1)==" "){
          out=(nc==0?cur:out"\t"cur); nc++; cur=""
          while(i<=L && substr(line,i,1)==" ") i++
        } else { cur=cur substr(line,i,1); i++ }
      }
      if(cur!=""){ out=(nc==0?cur:out"\t"cur); nc++ }
      print out
    }'
}

strategy_extract () {
    local text="$1"
    local shape; shape="$(_ac_shape "$text")" || { echo ""; return 0; }
    local mode="${shape%% *}" ncols="${shape##* }"

    # Collect non-blank lines (after dropping any `total <n>` preamble).
    # For a HEADED table, a blank line after the header + at least one data
    # row ends the table WHEN a footer legend follows — the next non-blank
    # line is a "KEY = explanation" definition (`systemctl --failed` prints
    # "LOAD = …" lines after a blank). A table that resumes after the blank
    # (faillock's per-user sections) keeps collecting.
    local _raw=() lines=() _l _li
    while IFS= read -r _l; do _raw+=("$_l"); done <<< "$(_ac_body "$text")"
    for ((_li = 0; _li < ${#_raw[@]}; _li++)); do
        _l="${_raw[$_li]}"
        if [[ -z "${_l//[[:space:]]/}" ]]; then
            if [[ ( "$mode" == HDR && ${#lines[@]} -ge 2 ) || ( "$mode" == HDR2 && ${#lines[@]} -ge 3 ) ]]; then
                local _peek="" _pi
                for ((_pi = _li + 1; _pi < ${#_raw[@]}; _pi++)); do
                    [[ -n "${_raw[$_pi]//[[:space:]]/}" ]] && { _peek="${_raw[$_pi]}"; break; }
                done
                [[ "$_peek" == *" = "* ]] && break
            fi
            continue
        fi
        lines+=("$_l")
    done

    # Table chrome, not data — drop it here so both the positional and the
    # tokenized paths below see only real rows:
    #   * mid-table HEADER REPEATS (watch/top/vmstat/sar re-print the header
    #     every page/interval) — any later line token-identical to the header,
    #     but only when the header is DIGIT-FREE, the mark of a label row: a
    #     legitimately repeated log/data line ("[app] listening on :8080")
    #     almost always carries a digit and must survive;
    #   * a UNITS ROW printed directly under the header ("(C)  (RPM)  (V)",
    #     "MHz  dBm  dB") — recognised only in that one position, and only when
    #     it has fewer tokens than the header, no digit anywhere, a deeper
    #     indent (its first column is blank), and EVERY token short (≤6 chars)
    #     the way unit labels are. Real data rows carry digits, fill the first
    #     column, or have long values (paths, service names).
    if [[ "$mode" == HDR || "$mode" == HDR2 ]] && [[ ${#lines[@]} -ge 3 ]]; then
        local _fhidx=0; [[ "$mode" == HDR2 ]] && _fhidx=1
        local _fharr=(); read -ra _fharr <<< "${lines[$_fhidx]}"
        local _fhnorm="${_fharr[*]}"
        local _fhind="${lines[$_fhidx]%%[![:space:]]*}"
        # repeat-drop only for a real label row: >=3 tokens (a 2-token log line
        # mistaken for a header must not eat its own repeats) and digit-free
        local _fhdrfree=1
        [[ "${lines[$_fhidx]}" =~ [0-9] || ${#_fharr[@]} -lt 3 ]] && _fhdrfree=0
        local _fout=() _fi _farr _fnorm _fdind _ft _ftok
        for ((_fi = 0; _fi < ${#lines[@]}; _fi++)); do
            if [[ $_fi -gt $_fhidx ]]; then
                _farr=(); read -ra _farr <<< "${lines[$_fi]}"
                _fnorm="${_farr[*]}"
                [[ $_fhdrfree -eq 1 && "$_fnorm" == "$_fhnorm" ]] && continue
                if [[ $_fi -eq $((_fhidx + 1)) && ${#_farr[@]} -lt ${#_fharr[@]} \
                      && ${#_farr[@]} -ge 2 && ! "${lines[$_fi]}" =~ [0-9] ]]; then
                    _fdind="${lines[$_fi]%%[![:space:]]*}"
                    if [[ ${#_fdind} -gt ${#_fhind} ]]; then
                        # every token must LOOK like a unit label: parenthesized
                        # ("(C)", "(RPM)") or case-mixed the way unit symbols are
                        # ("MHz", "dBm", "GiB") — an all-lowercase data row with an
                        # empty first cell ("web  db  allow") is data, not units
                        _ft=1
                        for _ftok in "${_farr[@]}"; do
                            [[ ${#_ftok} -gt 6 ]] && { _ft=0; break; }
                            if [[ "$_ftok" == "("*")" ]]; then continue; fi
                            [[ "$_ftok" == *[A-Z]* && "$_ftok" == *[a-z]* ]] || { _ft=0; break; }
                        done
                        [[ $_ft -eq 1 ]] && continue
                    fi
                fi
            fi
            _fout+=("${lines[$_fi]}")
        done
        lines=("${_fout[@]}")
    fi

    # For a cleanly-aligned HDR/HDR2 table, use positional token assignment so
    # multi-word headers/values (docker `IMAGE ID` / `2 weeks ago`, kubectl PORTS
    # `80, 443`) survive. Everything else keeps whitespace tokenization.
    if [[ "$mode" == HDR || "$mode" == HDR2 ]]; then
        local hidx=0; [[ "$mode" == HDR2 ]] && hidx=1
        local hd; hd="$(printf '%s\n' "${lines[@]:$hidx}")"
        # Positional assignment only helps when a data cell is multi-word (docker
        # "2 hours ago", helm's timestamp) — i.e. data rows carry MORE whitespace
        # tokens than the header has labels. When every cell is a single token
        # (df, lsblk, ss, elasticsearch), the header's 2-space segmentation can
        # UNDER-count columns (single-spaced labels like df's "Used Avail Use%"),
        # so positional would cram them; whitespace tokenization is correct there.
        local _htok _harr; _harr=(); read -ra _harr <<< "${lines[$hidx]}"; _htok=${#_harr[@]}
        local _maxd=0 _dli _darr _dcnt=()
        for ((_dli = hidx + 1; _dli < ${#lines[@]}; _dli++)); do
            _darr=(); read -ra _darr <<< "${lines[$_dli]}"
            [[ ${#_darr[@]} -gt $_maxd ]] && _maxd=${#_darr[@]}
            _dcnt+=("${#_darr[@]}")
        done
        # Modal data-row token count.
        local _moded=0 _mda _mdb _mdk _mdbest=0
        for _mda in "${_dcnt[@]}"; do
            _mdk=0; for _mdb in "${_dcnt[@]}"; do [[ "$_mdb" -eq "$_mda" ]] && _mdk=$((_mdk + 1)); done
            [[ $_mdk -gt $_mdbest ]] && { _mdbest=$_mdk; _moded=$_mda; }
        done
        # In an ALL-TEXT table (no digits anywhere) the reverse mismatch also
        # wants positional assignment: a header with MORE tokens than the data
        # rows means multi-word labels (`Service Name`), which 2-space
        # segmentation names as one column. Numeric tables keep tokenization
        # (their single-spaced labels under-segment) UNLESS the header's own
        # 2-space segmentation collapses EXACTLY to the data column count — a
        # genuine multi-word-header table (STREAM's "Best Rate MB/s", docker's
        # "IMAGE ID"). That equality is the safety: single-spaced labels (df's
        # "Used Avail Use%") under-segment and so never match.
        local _use_pos=0
        if [[ $_maxd -gt $_htok ]]; then _use_pos=1
        elif [[ $_htok -gt $_maxd ]]; then
            if [[ ! "$(printf '%s\n' "${lines[@]}")" =~ [0-9] ]]; then _use_pos=1
            else
                local _hseg; _hseg="$(_ac_seg "${lines[$hidx]}")"
                [[ $_hseg -ge 2 && $_hseg -eq $_moded ]] && _use_pos=1
            fi
        fi
        if [[ $_use_pos -eq 1 && "$(printf '%s' "$hd" | _ac_aligned)" == "1" ]]; then
            local gridrows=() _g
            while IFS= read -r _g; do gridrows+=("$_g"); done < <(printf '%s' "$hd" | _ac_assign)
            if [[ ${#gridrows[@]} -ge 2 ]]; then
                local headers=() result="" entry=0 li i
                IFS=$'\t' read -ra headers <<< "${gridrows[0]}"
                for ((i = 0; i < ${#headers[@]}; i++)); do
                    local h="${headers[$i]//./_}"; h="${h// /_}"
                    while [[ "$h" == *__* ]]; do h="${h//__/_}"; done
                    h="${h#_}"; h="${h%_}"; [[ -z "$h" ]] && h="$(_col_letter $((i + 1)))"
                    headers[$i]="$h"
                done
                for ((li = 1; li < ${#gridrows[@]}; li++)); do
                    local values; values=(); IFS=$'\t' read -ra values <<< "${gridrows[$li]}"
                    local nonempty=0 v
                    for v in "${values[@]}"; do [[ -n "${v//[[:space:]]/}" ]] && { nonempty=1; break; }; done
                    [[ $nonempty -eq 0 ]] && continue
                    entry=$((entry + 1))
                    for ((i = 0; i < ${#headers[@]}; i++)); do
                        local name="${headers[$i]}" value="${values[$i]:-}"
                        [[ -z "$value" ]] && continue
                        result+="entry${entry}.${name} ${value}"$'\n'
                    done
                done
                [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
                echo "$result"; return 0
            fi
        fi
    fi

    # Segment-split fallback for right-aligned space-in-value tables (ceph osd df's
    # "1.0 TiB" under a "RAW USE" multi-word header; supervisorctl's "pid 8821,
    # uptime 2:14:08"). Positional assignment above couldn't align these (their
    # values are right-justified, so a value's start falls under the WRONG header
    # column). Splitting on >=2-space gaps instead keeps each multi-word cell whole.
    # Fires only for a PERFECTLY regular segmentation table (every non-blank line
    # has the same >=2 segment count) that actually carries a multi-word cell
    # (some row's whitespace-token count exceeds the segment count) — so a normal
    # single-token table, already correct via tokenization, is never touched.
    # HDR-only: a headed table's header row fixes the true column count, so
    # rejoining segments is unambiguous. Headerless log records (who/last, whose
    # "date time (host)" trailing field the established tidy splits into columns)
    # are deliberately excluded — there is no header to say the field is one cell.
    if [[ "$mode" == HDR ]] && [[ ${#lines[@]} -ge 2 ]]; then
        local _sS="" _sok=1 _si _sarr _ss _sw _shw=0 _sdw=()
        for ((_si = 0; _si < ${#lines[@]}; _si++)); do
            _ss="$(_ac_seg "${lines[$_si]}")"
            _sarr=(); read -ra _sarr <<< "${lines[$_si]}"; _sw=${#_sarr[@]}
            [[ $_si -eq 0 ]] && _shw=$_sw || _sdw+=("$_sw")
            [[ -z "$_sS" ]] && _sS="$_ss"
            [[ "$_ss" -ne "$_sS" ]] && { _sok=0; break; }
        done
        # Modal (not max) data-row whitespace-token count: robust to a single
        # ragged row. seg-split is right ONLY when data cells carry inner spaces —
        # i.e. the typical data row has MORE whitespace tokens than the header has
        # labels ("1.0 TiB" is 2 tokens in 1 column). When they're EQUAL, the
        # columns are single-token and tokenization is already correct, even if a
        # header label happens to be single-spaced (ps -ef's "C STIME TTY" — three
        # narrow columns, not one multi-word cell). That equality is the guard that
        # keeps single-space-delimited fixed tables on tokenization.
        local _smod=0 _sa _sb _sk _sbest=0
        for _sa in "${_sdw[@]}"; do
            _sk=0; for _sb in "${_sdw[@]}"; do [[ "$_sb" -eq "$_sa" ]] && _sk=$((_sk + 1)); done
            [[ $_sk -gt $_sbest ]] && { _sbest=$_sk; _smod=$_sa; }
        done
        if [[ $_sok -eq 1 && $_sS -ge 2 && $_smod -gt $_shw ]]; then
            # mode==HDR guarantees a header row: split it on the same >=2-space
            # boundaries and use its cells as column names ("RAW USE" -> RAW_USE).
            local _sgrid=() _sg
            while IFS= read -r _sg; do _sgrid+=("$_sg"); done < <(printf '%s\n' "${lines[@]}" | _ac_split)
            local _sheaders=() _sstart=1
            IFS=$'\t' read -ra _sheaders <<< "${_sgrid[0]}"
            for ((_si = 0; _si < ${#_sheaders[@]}; _si++)); do
                local _sh="${_sheaders[$_si]//./_}"; _sh="${_sh// /_}"
                while [[ "$_sh" == *__* ]]; do _sh="${_sh//__/_}"; done
                _sh="${_sh#_}"; _sh="${_sh%_}"; [[ -z "$_sh" ]] && _sh="$(_col_letter $((_si + 1)))"
                _sheaders[$_si]="$_sh"
            done
            local _sresult="" _sentry=0 _sli
            for ((_sli = _sstart; _sli < ${#_sgrid[@]}; _sli++)); do
                local _svals=(); IFS=$'\t' read -ra _svals <<< "${_sgrid[$_sli]}"
                local _sne=0 _sv
                for _sv in "${_svals[@]}"; do [[ -n "${_sv//[[:space:]]/}" ]] && { _sne=1; break; }; done
                [[ $_sne -eq 0 ]] && continue
                _sentry=$((_sentry + 1))
                for ((_si = 0; _si < ${#_sheaders[@]}; _si++)); do
                    local _sname="${_sheaders[$_si]}" _sval="${_svals[$_si]:-}"
                    [[ -z "$_sval" ]] && continue
                    _sresult+="entry${_sentry}.${_sname} ${_sval}"$'\n'
                done
            done
            if [[ $_sentry -gt 0 ]]; then
                _sresult+="total_entries ${_sentry}"$'\n'
                echo "$_sresult"; return 0
            fi
        fi
    fi

    # Header names: the header line's tokens (HDR/HDR2), or synthetic c1..cN (HL).
    local headers=() startidx=0 i
    case "$mode" in
        HDR)  read -ra headers <<< "${lines[0]}"; startidx=1 ;;
        HDR2) read -ra headers <<< "${lines[1]}"; startidx=2 ;;
        HL)   for ((i = 1; i <= ncols; i++)); do headers+=("$(_col_letter "$i")"); done; startidx=0 ;;
    esac
    # Field names must not contain '.' (the tidy melt splits entry<N>.<field> on
    # the first dot).
    for ((i = 0; i < ${#headers[@]}; i++)); do headers[$i]="${headers[$i]//./_}"; done

    # Emit each data line as an indexed group (entry<N>.<field>) so the tidy melt
    # renders one row per line with shared columns.
    local result="" entry=0 li
    for ((li = startidx; li < ${#lines[@]}; li++)); do
        local values; values=(); read -ra values <<< "${lines[$li]}"
        entry=$((entry + 1))
        for ((i = 0; i < ${#headers[@]}; i++)); do
            local name="${headers[$i]}" value="${values[$i]:-}"
            [[ -z "$value" ]] && continue
            # Last column absorbs any extra trailing tokens.
            if [[ $i -eq $((${#headers[@]} - 1)) && ${#values[@]} -gt ${#headers[@]} ]]; then
                local j
                for ((j = i + 1; j < ${#values[@]}; j++)); do value+="_${values[$j]}"; done
            fi
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
