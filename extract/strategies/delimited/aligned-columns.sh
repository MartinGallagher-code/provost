#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 3.1
## Priority: 55
## Technique: yes
## Sample: samples/aligned-columns/basic.txt

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

    # A leading `#`-comment block (conda list, opam list) mixes prose banners with
    # a commented column header on its last line. Drop the prose lines but keep
    # that last comment as the header, de-hashed — held here until the first data
    # line, so each new `#` line overwrites the previous candidate.
    local held=""
    while IFS= read -r _l; do
        if [[ $started -eq 0 && -n "${_l//[[:space:]]/}" ]]; then
            _tk=(); read -ra _tk <<< "$_l"
            [[ "$_l" =~ ^[[:space:]]*total[[:space:]]+[0-9]+[[:space:]]*$ ]] && continue
            if [[ "$_l" =~ ^[[:space:]]*# ]]; then
                # Strip the leading `#` (and one following space) — a candidate header.
                local _h="${_l#"${_l%%[!#[:space:]]*}"}"
                [[ -n "${_h//[[:space:]]/}" ]] && held="$_h"
                continue
            fi
            # A short word-like preamble line (e.g. `apt list`'s "Listing…") before
            # a real table — but NOT a `{`/`[`/`<` structural line (JSON/XML), which
            # must keep aligned-columns from matching those formats.
            [[ $has_table -eq 1 && ${#_tk[@]} -lt 2 && "$_l" =~ ^[[:space:]]*[A-Za-z] ]] && continue
            # First real line: emit the held commented header (if any) before it.
            [[ -n "$held" ]] && out+="$held"$'\n'
            started=1
        fi
        # A pure separator rule under the header (`---- -----`, dashes/spaces only,
        # ≥2 dashes) is not a data row — drop it wherever it appears.
        [[ "$_l" =~ ^[[:space:]]*-+([[:space:]]+-+)*[[:space:]]*$ ]] && continue
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
    local caps0=0; [[ ! "$first_line" =~ [a-z] ]] && caps0=1
    local v0=0 _t _t1arr; _t1arr=(); read -ra _t1arr <<< "$first_line"
    for _t in "${_t1arr[@]}"; do
        # value token = a number, optionally with a trailing unit (8.421s, 942ms,
        # 7.8Gi, 39%), or a time / IP / date. `1K-blocks` is NOT one (the hyphen),
        # so a df-T-style header label stays a header.
        [[ "$_t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_t" =~ ^[0-9]{1,2}:[0-9]{2} \
           || "$_t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && v0=$((v0 + 1))
    done
    local maxd=0 i
    for ((i = 1; i < nlines; i++)); do [[ ${dcount[$i]} -gt $maxd ]] && maxd=${dcount[$i]}; done
    if [[ $caps0 -eq 1 || ( $v0 -eq 0 && $maxd -gt ${dcount[0]} ) ]]; then
        printf 'HDR %s\n' "${counts[0]}"
        return 0
    fi

    # Headerless: require a modal column count (>=3) shared by most lines.
    local mode=0 best=0 c d k
    for c in "${counts[@]}"; do
        k=0
        for d in "${counts[@]}"; do [[ "$d" -eq "$c" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; mode=$c; }
    done
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

strategy_extract () {
    local text="$1"
    local shape; shape="$(_ac_shape "$text")" || { echo ""; return 0; }
    local mode="${shape%% *}" ncols="${shape##* }"

    # Collect non-blank lines (after dropping any `total <n>` preamble).
    local lines=() _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        lines+=("$_l")
    done <<< "$(_ac_body "$text")"

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
        local _maxd=0 _dli _darr
        for ((_dli = hidx + 1; _dli < ${#lines[@]}; _dli++)); do
            _darr=(); read -ra _darr <<< "${lines[$_dli]}"
            [[ ${#_darr[@]} -gt $_maxd ]] && _maxd=${#_darr[@]}
        done
        if [[ $_maxd -gt $_htok && "$(printf '%s' "$hd" | _ac_aligned)" == "1" ]]; then
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
