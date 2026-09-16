#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

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

    # AUDIT-REPORT chrome (aureport family): `====` rule lines are never
    # data; a 1-2 token line DIRECTLY ABOVE a rule is the report title; a
    # single `# label label …` line among the first lines is the real
    # header wearing a comment marker — strip the marker. Sequentially
    # numbered `N.` first tokens on every data row are row numbers (the
    # melt's `n` column already carries that) — strip them.
    if [[ "$text" == *$'\n'====* ]]; then
        local _ar_lines=() _ar_i
        while IFS= read -r _l; do _ar_lines+=("$_l"); done <<< "$text"
        # drop rules + the title above the first rule
        local _ar_out=() _ar_hash=-1 _ar_hashes=0
        for ((_ar_i = 0; _ar_i < ${#_ar_lines[@]}; _ar_i++)); do
            _l="${_ar_lines[$_ar_i]}"
            if [[ "$_l" =~ ^[[:space:]]*={4,}[[:space:]]*$ ]]; then
                # title directly above the FIRST rule (<=2 tokens, no colon)
                if [[ ${#_ar_out[@]} -ge 1 ]]; then
                    local _ar_last="${_ar_out[$(( ${#_ar_out[@]} - 1 ))]}"
                    local _ar_lt=(); read -ra _ar_lt <<< "$_ar_last"
                    [[ ${#_ar_lt[@]} -le 2 && ! "$_ar_last" == *:* && "$_ar_last" =~ ^[A-Z] ]] && unset '_ar_out[$(( ${#_ar_out[@]} - 1 ))]'
                    _ar_out=("${_ar_out[@]}")
                fi
                continue
            fi
            [[ "$_l" == "# "* ]] && { _ar_hashes=$((_ar_hashes + 1)); _ar_hash=${#_ar_out[@]}; }
            _ar_out+=("$_l")
        done
        # exactly one `# …` line within the first 3 kept lines → header
        if [[ $_ar_hashes -eq 1 && $_ar_hash -ge 0 && $_ar_hash -le 2 ]]; then
            _ar_out[$_ar_hash]="${_ar_out[$_ar_hash]#\# }"
        fi
        # sequential `N.` first tokens on every line after the header
        local _ar_seq=1 _ar_want=1 _ar_started=0
        for ((_ar_i = _ar_hash >= 0 ? _ar_hash + 1 : 1; _ar_i < ${#_ar_out[@]}; _ar_i++)); do
            [[ -z "${_ar_out[$_ar_i]//[[:space:]]/}" ]] && continue
            _tk=(); read -ra _tk <<< "${_ar_out[$_ar_i]}"
            [[ "${_tk[0]:-}" == "${_ar_want}." ]] || { _ar_seq=0; break; }
            _ar_want=$((_ar_want + 1)); _ar_started=1
        done
        if [[ $_ar_seq -eq 1 && $_ar_started -eq 1 && $_ar_want -ge 3 ]]; then
            for ((_ar_i = _ar_hash >= 0 ? _ar_hash + 1 : 1; _ar_i < ${#_ar_out[@]}; _ar_i++)); do
                [[ -z "${_ar_out[$_ar_i]//[[:space:]]/}" ]] && continue
                local _ar_rest="${_ar_out[$_ar_i]#*.}"
                _ar_rest="${_ar_rest# }"
                _ar_out[$_ar_i]="$_ar_rest"
            done
        fi
        text="$(printf '%s\n' "${_ar_out[@]}")"
    fi

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
    # Track whether this block is dominantly a single-record COLON-KV
    # description (dpkg/apt `Package: foo` / `Status: install ok installed` /
    # `Header: family inet …`) rather than a real table — one field per line,
    # each field a DISTINCT label. That shape belongs to `colons`
    # (priority 60), which already renders it as one clean wide record; if
    # aligned-columns claims it first, row 1's two tokens ("Package:", "vim")
    # become literal COLUMN NAMES and every later field gets stuffed under
    # them, producing garbage. Declining here lets colons pick it up.
    local _kv_lines=0 _kv_dupe=0 _kvm_lines=0 _kvm_dupe=0
    local _kvm_tpl="" _kvm_tpl_same=1
    local -A _kv_seen=() _kvm_seen=()
    local _kvm_re='^[[:space:]]*([A-Za-z][A-Za-z0-9_()-]*([ ][A-Za-z0-9_()-]+)+):([[:space:]]|$)'
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        [[ $idx -eq 1 ]] && first_line="$_line"
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        counts+=("${#_tk[@]}")
        local d=0 t
        for t in "${_tk[@]}"; do [[ "$t" =~ [0-9] ]] && d=$((d + 1)); done
        dcount+=("$d")
        if [[ "${_tk[0]:-}" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]]; then
            _kv_lines=$((_kv_lines + 1))
            local _lab="${_tk[0]%:}"
            [[ -n "${_kv_seen[$_lab]:-}" ]] && _kv_dupe=1
            _kv_seen[$_lab]=1
        fi
        # MULTI-WORD colon labels ("Total package names: 88201 (1,764 k)"):
        # single-space tokenization shreds these, so they must go to `colons`.
        # Track the label's digit-TEMPLATE too (digits collapsed to #): when
        # every label is the SAME template ("Bus ### Device ###" — lsusb),
        # the "labels" are really table rows and the veto must not fire.
        if [[ "$_line" =~ $_kvm_re ]]; then
            _kvm_lines=$((_kvm_lines + 1))
            local _mlab="${BASH_REMATCH[1]}"
            [[ -n "${_kvm_seen[$_mlab]:-}" ]] && _kvm_dupe=1
            _kvm_seen[$_mlab]=1
            local _mtpl="${_mlab//[0-9]/#}"
            while [[ "$_mtpl" == *"##"* ]]; do _mtpl="${_mtpl//##/#}"; done
            if [[ -z "$_kvm_tpl" ]]; then _kvm_tpl="$_mtpl"
            elif [[ "$_mtpl" != "$_kvm_tpl" ]]; then _kvm_tpl_same=0
            fi
        fi
        [[ $idx -ge 40 ]] && break
    done <<< "$text"
    # Also require ROW 1 ITSELF to be a colon-kv label line. Without this, a
    # real table whose first COLUMN happens to be colon-suffixed labels
    # (/proc/interrupts-style `HI:  TIMER:  NET_TX:  …` per-row counter names
    # under a `CPU0 CPU1 CPU2 CPU3` header) satisfies "distinct label per
    # line, majority of rows" just as well as a genuine kv description does —
    # but there row 1 is the real header (no colon), not a field, so it fails
    # this check and the table stays with aligned-columns where it belongs.
    local _first_tok="${first_line%%[[:space:]]*}"
    if [[ $idx -ge 8 && $_kv_dupe -eq 0 && $((_kv_lines * 2)) -ge $idx \
          && "$_first_tok" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]]; then
        return 1
    fi
    # EVERY line a distinct multi-word colon label => a colon-kv description
    # ("Total package names: …"), never a table. The multi-word requirement
    # keeps single-token label columns (/proc/interrupts' `HI:`) out of this
    # veto — those stay with the row-1-label check above. Labels that all
    # share one digit-template ("Bus ### Device ###" — lsusb) are table rows
    # wearing colons, not field names: the veto stands down.
    if [[ $idx -ge 3 && $_kvm_dupe -eq 0 && $_kvm_lines -eq $idx \
          && ! ( $_kvm_tpl_same -eq 1 && "$_kvm_tpl" == *"#"* ) ]]; then
        return 1
    fi
    # MIXED-label colon-kv block. The two vetoes above each have a blind spot
    # the reviewer hit three times in one round: single- and multi-word labels
    # MIXED in one block (`Queue running: 1` + `VRAM: 8201/24564 MiB` —
    # comfyui), blocks SHORTER than 3 multi-word lines (cups-lpstat's two
    # `device for X: uri` lines), and a same-template run broken by one odd
    # label (e2fsck's `Pass N:` ×4 + `/dev/sda2:` — the lsusb exemption stood
    # down on the Pass template alone). This veto takes the union: EVERY line
    # is `label: value` (label single-spaced — no 2+-space run, so a table
    # cell before a later colon never counts — and colon-free), labels are
    # DISTINCT, at least one label holds a space or `/` (pure single-token
    # label columns still belong to the row-1 check), and the labels do NOT
    # all share one digit template (lsusb again). Such a block is `colons`'
    # territory: one field per line, split at the first colon.
    local _mixed_ok=1 _mixed_multi=0 _mx_line _mx_tpl="" _mx_tpl_same=1 _mx_colons=0 _mx_n=0
    local -A _mx_seen=()
    if [[ $idx -ge 2 ]]; then
        while IFS= read -r _mx_line; do
            [[ -z "${_mx_line//[[:space:]]/}" ]] && continue
            if [[ ! "$_mx_line" =~ ^[[:space:]]*([^:]+):[[:space:]]+[^[:space:]] ]]; then
                _mixed_ok=0; break
            fi
            local _mxl="${BASH_REMATCH[1]}"
            _mxl="${_mxl#"${_mxl%%[![:space:]]*}"}"
            _mxl="${_mxl%"${_mxl##*[![:space:]]}"}"
            [[ "$_mxl" == *"  "* || -z "$_mxl" ]] && { _mixed_ok=0; break; }
            # A possessive/prose label (`pid 3421's current scheduling
            # policy`) is a sentence wearing a colon, not a field name —
            # chrt/taskset keep their aligned parse.
            [[ "$_mxl" == *"'"* ]] && { _mixed_ok=0; break; }
            [[ -n "${_mx_seen[$_mxl]:-}" ]] && { _mixed_ok=0; break; }
            _mx_seen[$_mxl]=1
            [[ "$_mxl" == *" "* || "$_mxl" == */* ]] && _mixed_multi=1
            _mx_n=$((_mx_n + 1))
            [[ "$_mxl" =~ ^[A-Za-z][A-Za-z0-9_\ -]*$ ]] && _mx_colons=$((_mx_colons + 1))
            local _mxt="${_mxl//[0-9]/#}"
            while [[ "$_mxt" == *"##"* ]]; do _mxt="${_mxt//##/#}"; done
            if [[ -z "$_mx_tpl" ]]; then _mx_tpl="$_mxt"
            elif [[ "$_mxt" != "$_mx_tpl" ]]; then _mx_tpl_same=0
            fi
        done <<< "$text"
        # Only defer when `colons` will actually ACCEPT the block (>=40% of
        # labels letter-led simple charset) — else no parser takes it at all.
        if [[ $_mixed_ok -eq 1 && $_mixed_multi -eq 1 && $_mx_n -ge 1 \
              && $(( _mx_colons * 100 / _mx_n )) -ge 40 \
              && ! ( $_mx_tpl_same -eq 1 && "$_mx_tpl" == *"#"* ) ]]; then
            return 1
        fi
    fi

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
    # Same shape, but the FIELD row's labels carry digits (`p50`, `BW(MB/s)`,
    # `Lat(ms)` — benchmark/spanning-group tables). A digit alone can't demote
    # it: the discriminator is VALUE-shaped tokens (a bare number/time/IP/date).
    # Row 2 must have none while row 3 has at least one.
    if [[ $nlines -ge 3 && ${dcount[0]} -eq 0 && ${dcount[1]} -gt 0 \
          && ${dcount[2]} -gt 0 && ${counts[1]} -gt ${counts[0]} ]]; then
        local _h2v=0 _h3v=0 _h2t _h2i=0 _h2l="" _h3l=""
        while IFS= read -r _h2t; do
            [[ -z "${_h2t//[[:space:]]/}" ]] && continue
            _h2i=$((_h2i + 1))
            [[ $_h2i -eq 2 ]] && _h2l="$_h2t"
            [[ $_h2i -eq 3 ]] && { _h3l="$_h2t"; break; }
        done <<< "$text"
        local _h2arr=(); read -ra _h2arr <<< "$_h2l"
        for _h2t in "${_h2arr[@]}"; do
            [[ "$_h2t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_h2t" =~ ^[0-9]{1,2}:[0-9]{2} \
               || "$_h2t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_h2t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && _h2v=$((_h2v + 1))
        done
        local _h3arr=(); read -ra _h3arr <<< "$_h3l"
        for _h2t in "${_h3arr[@]}"; do
            [[ "$_h2t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_h2t" =~ ^[0-9]{1,2}:[0-9]{2} \
               || "$_h2t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_h2t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && _h3v=$((_h3v + 1))
        done
        # Containment: row 1 must be a real GROUP-LABEL row — every token
        # alphanumeric-bearing (a `==== test session starts ====` banner fails
        # on its `====`), and row 2 a real FIELD row — no lone-punctuation
        # tokens (an ` X : Y   Z : W ` kv line fails on its bare `:`).
        local _h1ok=1 _h1arr=()
        read -ra _h1arr <<< "$first_line"
        for _h2t in "${_h1arr[@]}"; do
            [[ "$_h2t" =~ [A-Za-z0-9] ]] || { _h1ok=0; break; }
        done
        local _h2ok=1
        for _h2t in "${_h2arr[@]}"; do
            [[ "$_h2t" =~ ^[\|#/%+:=-]+$ ]] && { _h2ok=0; break; }
        done
        if [[ $_h1ok -eq 1 && $_h2ok -eq 1 && $_h2v -eq 0 && $_h3v -ge 1 ]]; then
            printf 'HDR2 %s\n' "${counts[1]}"
            return 0
        fi
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
    # A CJK/hangul header row (名前 年齢 都市) has no [A-Za-z0-9] anywhere, so it
    # could never pass the labelly check. Accept fully-non-ASCII tokens as labels
    # — but ONLY when EVERY non-separator token in the row is fully non-ASCII (a
    # pure CJK label row). A mixed row (⚡️ User toolchain:, + pod › nginx,
    # docker · list …) is a decorated log/record line, not a header.
    local _row_cjk=1
    for _t in "${_t1arr[@]}"; do
        [[ "$_t" =~ ^[\|#/%+-]$ ]] && continue
        [[ "$_t" == *[[:ascii:]]* ]] && { _row_cjk=0; break; }
    done
    # sysstat convention: sar prints the interval TIMESTAMP as the first header
    # token (`07:00:01  CPU  %user %nice …`), which counts as a value token and
    # would veto promotion. Forgive exactly that: row 1's ONLY value-shaped
    # token is a leading bare clock time AND the remaining tokens look like
    # sysstat column labels (at least half are %-prefixed or ALL-CAPS) — a log
    # line that merely starts with a time (`07:00:01 app started`) has
    # lowercase words and stays headerless.
    if [[ $v0 -eq 1 && ${#_t1arr[@]} -ge 4 \
          && "${_t1arr[0]}" =~ ^[0-9]{1,2}:[0-9]{2}(:[0-9]{2})?$ ]]; then
        local _ss_lab=0 _ss_i
        for ((_ss_i = 1; _ss_i < ${#_t1arr[@]}; _ss_i++)); do
            [[ "${_t1arr[$_ss_i]}" == %* ]] && { _ss_lab=$((_ss_lab + 1)); continue; }
            [[ "${_t1arr[$_ss_i]}" =~ ^[A-Z][A-Z0-9/]*$ ]] && _ss_lab=$((_ss_lab + 1))
        done
        [[ $((_ss_lab * 2)) -ge $(( ${#_t1arr[@]} - 1 )) ]] && v0=0
    fi
    local labelly=1 _lbl_seen=0 _lbl_ok
    for _t in "${_t1arr[@]}"; do
        [[ "$_t" =~ ^[\|#/%+-]$ ]] && continue
        _lbl_seen=1
        _lbl_ok=0
        [[ "$_t" =~ [A-Za-z0-9] ]] && _lbl_ok=1
        [[ $_row_cjk -eq 1 && "$_t" != *[[:ascii:]]* ]] && _lbl_ok=1
        [[ $_lbl_ok -eq 1 && ! "$_t" =~ ^\[ && ! "$_t" =~ \]$ && ! "$_t" =~ \.$ ]] || { labelly=0; break; }
    done
    [[ $_lbl_seen -eq 0 ]] && labelly=0
    # PROSE veto: a sentence is not a header. Row 1 shaped `Titleword lower
    # lower …` — first token Titlecase, EVERY other token a pure lowercase
    # word (>=2 of them), no digits anywhere — over data whose modal token
    # count differs from row 1's is a title line ("List of devices attached"),
    # not labels. Real multi-word-label headers keep further Titlecase tokens
    # ("Property Name … Group") and survive; lowercase HEADERS ("username
    # fullname active") fail the Titlecase-first test and survive.
    if [[ $labelly -eq 1 && ${#_t1arr[@]} -ge 3 && "${_t1arr[0]}" =~ ^[A-Z][a-z]+$ ]]; then
        local _pr_low=1 _pr_stop=0 _pr_i
        for ((_pr_i = 1; _pr_i < ${#_t1arr[@]}; _pr_i++)); do
            [[ "${_t1arr[$_pr_i]}" =~ ^[a-z]+$ ]] || { _pr_low=0; break; }
            case "${_t1arr[$_pr_i]}" in
                of|the|to|in|for|with|and|on|at|by|from|is|are) _pr_stop=1 ;;
            esac
        done
        # A sentence carries a function word ("List OF devices attached");
        # a lowercase label row ("Host cpu mem disk net") does not.
        if [[ $_pr_low -eq 1 && $_pr_stop -eq 1 ]]; then
            local _pr_m=0 _pr_b=0 _pr_a _pr_n
            for ((_pr_i = 1; _pr_i < nlines; _pr_i++)); do
                _pr_n=0
                for ((_pr_a = 1; _pr_a < nlines; _pr_a++)); do
                    [[ ${counts[$_pr_a]} -eq ${counts[$_pr_i]} ]] && _pr_n=$((_pr_n + 1))
                done
                [[ $_pr_n -gt $_pr_b ]] && { _pr_b=$_pr_n; _pr_m=${counts[$_pr_i]}; }
            done
            [[ $_pr_m -ne ${counts[0]} ]] && labelly=0
        fi
    fi
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
        # …or the styling contrast is on the DATA side: a lowercase header
        # (`username fullname active`, `household members flag`) still reads
        # as a header when EVERY data row carries a token the header lacks —
        # Titlecase (`Alice Anders`) or fully non-ASCII (emoji, Farsi). A
        # lowercase name grid (sqlite .tables) has neither and stays data.
        if [[ $wordy -eq 1 && $styled -eq 0 ]]; then
            local _dc_all=1 _dc_hit _dc_tk _dc_l _dc_i=0
            while IFS= read -r _dc_l; do
                [[ -z "${_dc_l//[[:space:]]/}" ]] && continue
                _dc_i=$((_dc_i + 1))
                [[ $_dc_i -eq 1 ]] && continue          # skip the header row
                _dc_hit=0
                local _dc_arr=(); read -ra _dc_arr <<< "$_dc_l"
                for _dc_tk in "${_dc_arr[@]}"; do
                    [[ "$_dc_tk" =~ ^[A-Z][a-z] ]] && { _dc_hit=1; break; }
                    [[ "$_dc_tk" != *[[:ascii:]]* ]] && { _dc_hit=1; break; }
                done
                [[ $_dc_hit -eq 0 ]] && { _dc_all=0; break; }
                [[ $_dc_i -ge 40 ]] && break
            done <<< "$text"
            [[ $_dc_all -eq 1 ]] && styled=1
        fi
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
        # Header tokens with their own start/end offsets — the raw material
        # for the sub-column refinement below.
        hn=0; i=1
        while (i<=L) {
            while (i<=L && substr(hl,i,1)==" ") i++
            if (i>L) break
            hn++; hts[hn]=i; htx[hn]=""
            while (i<=L && substr(hl,i,1)!=" ") { htx[hn]=htx[hn] substr(hl,i,1); i++ }
            hte[hn]=i-1
        }
        for (i2=1;i2<=hn;i2++) hcnt[htx[i2]]++
    }
    { rows[NR]=$0; nr=NR }
    END {
        # SUB-COLUMN REFINEMENT. A 2-space window holding k>=2 header tokens
        # is EITHER one multi-word label ("Ends At", "Property Name") OR k
        # separate single-space-separated columns ("SIZE USED PRIO",
        # "DEVICE OFFSET TYPE UUID"). The tell is alignment: real sub-columns
        # keep their data tokens edge-aligned under each header token (left
        # edge for left-aligned, right edge for right-aligned); a multi-word
        # value ("2026-07-11 06:00:00" under "Ends At") aligns only with the
        # window, not with each label token. Split a window into sub-columns
        # only when EVERY header token in it edge-aligns in >=60% of rows.
        ndata=nr-1
        for (r=2;r<=nr;r++) {
            line=rows[r]; L=length(line); i=1
            tn[r]=0
            while (i<=L) {
                while (i<=L && substr(line,i,1)==" ") i++
                if (i>L) break
                ts=i; anum=0
                while (i<=L && substr(line,i,1)!=" ") {
                    if (substr(line,i,1) ~ /[A-Za-z0-9]/) anum=1
                    i++
                }
                # Only alnum-bearing tokens witness an edge: a bare "/"
                # separator (docker stats MEM USAGE) must not vouch for a
                # sub-column boundary. Spans are kept for the bridge veto;
                # bare separators are kept for the composite-value veto.
                if (anum) {
                    sa[r "," ts]=1; ea[r "," (i-1)]=1
                    tn[r]++; tsA[r "," tn[r]]=ts; teA[r "," tn[r]]=i-1
                } else {
                    bn[r]++; bsA[r "," bn[r]]=ts
                }
            }
        }
        # Token spans per row are also needed window-wise: a window may only
        # split when the MODAL count of data tokens inside it equals its
        # label count — a single "webapp" under "Job ID", "0.006442" under
        # "Avg time" or "a1b2c3" under "CONTAINER ID" must never split (the
        # duplicate/empty sub-columns collide in the melt and DROP data).
        for (r=2;r<=nr;r++) {
            line=rows[r]; L=length(line); i=1
            while (i<=L) {
                while (i<=L && substr(line,i,1)==" ") i++
                if (i>L) break
                ts=i
                while (i<=L && substr(line,i,1)!=" ") i++
                for (w=1;w<=nc;w++)
                    if (ts>=cstart[w] && ts<cstart[w+1]) { wc[r "," w]++; break }
            }
        }
        m=0
        for (w=1;w<=nc;w++) {
            k=0
            for (t=1;t<=hn;t++)
                if (hts[t]>=cstart[w] && hts[t]<cstart[w+1]) { k++; wt[k]=t }
            ok=0
            if (k>=2 && ndata>0) {
                # MAX data token count inside this window must REACH the
                # label count: a lone "webapp" under "Job ID" (max 1 < 2)
                # must never split — the duplicate/empty sub-columns collide
                # in the melt and DROP data. More tokens than labels is fine
                # (xz-list holds "12.4 MiB  88.2 MiB" under
                # "Compressed Uncompressed"); the edge gate arbitrates.
                mo=0
                for (r=2;r<=nr;r++) if (wc[r "," w]+0 > mo) mo=wc[r "," w]+0
                if (mo>=k) {
                    ok=1
                    # DUPLICATE-NAME veto: sub-labels that repeat elsewhere
                    # in the header ("CPU REQUESTS  CPU LIMITS" —
                    # kube-capacity) would collide in the melt and DROP a
                    # column; the joined window names stay unique.
                    for (j=1;j<=k;j++)
                        if (hcnt[htx[wt[j]]] > 1) ok=0
                    # COMPOSITE-VALUE veto: a bare SEPARATOR token ("12M / 4M"
                    # under "NET RX/TX" — ctop gauges) inside the window marks
                    # one composite value, never two columns. A separator sits
                    # BETWEEN alnum tokens of the same window; a bare token
                    # with nothing after it is a value in its own right
                    # (a "/" mountpoint) and does not veto.
                    for (r=2;r<=nr && ok;r++)
                        for (x=1;x<=bn[r]+0;x++) {
                            if (!(bsA[r "," x] >= cstart[w] && bsA[r "," x] < cstart[w+1])) continue
                            lft=0; rgt=0
                            for (y=1;y<=tn[r];y++) {
                                if (tsA[r "," y] >= cstart[w] && tsA[r "," y] < cstart[w+1]) {
                                    if (teA[r "," y] < bsA[r "," x]) lft=1
                                    if (tsA[r "," y] > bsA[r "," x]) rgt=1
                                }
                            }
                            if (lft && rgt) { ok=0; break }
                        }
                    # BRIDGE veto: a data token that SPANS a sub-column
                    # start ("93.184.216.34:443" across "Peer Address:Port")
                    # is one value bridging both labels — splitting would
                    # strand an empty sub-column.
                    for (j=2;j<=k && ok;j++) {
                        t=wt[j]; br=0; bden=0
                        for (r=2;r<=nr;r++) {
                            if (wc[r "," w]+0 < 1) continue
                            bden++
                            for (x=1;x<=tn[r];x++)
                                if (tsA[r "," x] < hts[t] && teA[r "," x] >= hts[t]) { br++; break }
                        }
                        if (bden>0 && br*100/bden >= 40) ok=0
                    }
                    if (!ok) { m++; bstart[m]=cstart[w]; bend[m]=0; bsub[m]=0; continue }
                    for (j=1;j<=k;j++) {
                        t=wt[j]; hit=0; den=0
                        # Denominator: only rows that HAVE a j-th token in
                        # this window — a sparse trailing sub-column (lsblk
                        # MOUNTPOINT) is judged on the rows where it exists.
                        # +-1 tolerance: `#`-prefixed headers (collectl) and
                        # one-char pads shift edges by a column.
                        for (r=2;r<=nr;r++) {
                            if (wc[r "," w]+0 < j) continue
                            den++
                            if (sa[r "," hts[t]] || sa[r "," (hts[t]-1)] || sa[r "," (hts[t]+1)] || \
                                ea[r "," hte[t]] || ea[r "," (hte[t]-1)] || ea[r "," (hte[t]+1)]) hit++
                        }
                        if (den==0 || hit*100/den < 60) { ok=0; break }
                    }
                }
            }
            if (ok) {
                for (j=1;j<=k;j++) {
                    m++; bstart[m]=hts[wt[j]]; bend[m]=hte[wt[j]]; bsub[m]=1
                }
            } else { m++; bstart[m]=cstart[w]; bend[m]=0; bsub[m]=0 }
        }
        bstart[m+1]=1000000
        for (r=1;r<=nr;r++) {
            line=rows[r]; L=length(line); i=1
            for (c=1;c<=m;c++) cell[c]=""
            while (i<=L) {
                while (i<=L && substr(line,i,1)==" ") i++
                if (i>L) break
                ts=i; tok=""
                while (i<=L && substr(line,i,1)!=" ") { tok=tok substr(line,i,1); i++ }
                te=i-1
                col=1
                for (c=1;c<=m;c++) { if (bstart[c]<=ts) col=c; else break }
                # Right-aligned escape: a value wider than its header label
                # starts left of the sub-column boundary but ENDS on the
                # label end (+-1, matching the split tolerance) —
                # end-alignment wins over start assignment.
                for (c=1;c<=m;c++)
                    if (bsub[c] && te>=bend[c]-1 && te<=bend[c]+1) { col=c; break }
                if (cell[col]=="") cell[col]=tok; else cell[col]=cell[col] " " tok
            }
            out=cell[1]
            for (c=2;c<=m;c++) out=out "\t" cell[c]
            print out
        }
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

# Char-accurate positional grid for blocks with SCATTERED multibyte content
# (asv's `412±2ns`): the awk grid measures BYTES, so every token after a
# multibyte char drifts right and lands under the wrong header window. Bash
# under a UTF-8 locale measures characters. Subshell body so the locale
# switch can't leak. Prints the TAB grid when the block is cleanly aligned
# (>=80% of rows), else exits 1 (caller falls back). Fully-CJK tables keep
# the awk path — their double-width glyphs make byte math the closer proxy.
_ac_grid_mb () (
    export LC_ALL=C.UTF-8
    local hl; IFS= read -r hl
    local L=${#hl}; local i=0; local nc=0; local cstart=()
    while (( i < L )); do
        while (( i < L )) && [[ "${hl:$i:1}" == " " ]]; do i=$((i+1)); done
        (( i >= L )) && break
        cstart+=("$i"); nc=$((nc+1))
        while (( i < L )); do
            [[ "${hl:$i:1}" == " " && "${hl:$((i+1)):1}" == " " ]] && break
            i=$((i+1))
        done
    done
    (( nc < 2 )) && exit 1
    local rows=("$hl"); local l
    # `|| [[ -n "$l" ]]`: the caller pipes without a trailing newline, and a
    # plain read loop would silently drop the final data row.
    while IFS= read -r l || [[ -n "$l" ]]; do rows+=("$l"); done
    local aligned=0; local ndata=0; local r; local c; local ch
    for ((r=1; r<${#rows[@]}; r++)); do
        ndata=$((ndata+1)); local ok=1
        for ((c=1; c<nc; c++)); do
            ch="${rows[$r]:$((${cstart[$c]}-1)):1}"
            [[ -n "$ch" && "$ch" != " " ]] && { ok=0; break; }
        done
        [[ $ok -eq 1 ]] && aligned=$((aligned+1))
    done
    (( ndata == 0 )) && exit 1
    if (( aligned * 100 / ndata >= 80 )); then
        for ((r=0; r<${#rows[@]}; r++)); do
            local line="${rows[$r]}"; local n=${#line}; local j=0
            local cells=()
            for ((c=0; c<nc; c++)); do cells+=(""); done
            while (( j < n )); do
                while (( j < n )) && [[ "${line:$j:1}" == " " ]]; do j=$((j+1)); done
                (( j >= n )) && break
                local ts=$j; local tok=""
                while (( j < n )) && [[ "${line:$j:1}" != " " ]]; do tok+="${line:$j:1}"; j=$((j+1)); done
                local col=0
                for ((c=0; c<nc; c++)); do
                    if (( ${cstart[$c]} <= ts )); then col=$c; else break; fi
                done
                if [[ -z "${cells[$col]}" ]]; then cells[$col]="$tok"; else cells[$col]+=" $tok"; fi
            done
            local out="${cells[0]}"
            for ((c=1; c<nc; c++)); do out+=$'\t'"${cells[$c]}"; done
            printf '%s\n' "$out"
        done
        exit 0
    fi
    # RAGGED-ALIGNMENT fallback: a benchmark-style table whose data rows have
    # a UNIFORM token count above the label count (asv's `+ 412±2ns 440±3ns
    # 1.07 parser.time_parse` under `before after ratio`) with right-aligned
    # bleed. Use the first modal-width row's token spans as the reference
    # columns, map each header label onto the column it overlaps most (extra
    # columns stay unnamed for the caller's letter fallback), then assign
    # every row's tokens to reference columns by best overlap.
    _mb_spans () {  # $1=line -> _MB_TS/_MB_TE/_MB_TOK arrays
        local line="$1"; local n=${#line}; local j=0
        _MB_TS=(); _MB_TE=(); _MB_TOK=()
        while (( j < n )); do
            while (( j < n )) && [[ "${line:$j:1}" == " " ]]; do j=$((j+1)); done
            (( j >= n )) && break
            local ts=$j; local tok=""
            while (( j < n )) && [[ "${line:$j:1}" != " " ]]; do tok+="${line:$j:1}"; j=$((j+1)); done
            _MB_TS+=("$ts"); _MB_TE+=("$((j-1))"); _MB_TOK+=("$tok")
        done
    }
    local counts=(); local r2
    for ((r2=1; r2<${#rows[@]}; r2++)); do
        _mb_spans "${rows[$r2]}"
        counts+=("${#_MB_TOK[@]}")
    done
    local modal=0; local best=0; local a; local b; local k
    for a in "${counts[@]}"; do
        k=0; for b in "${counts[@]}"; do [[ "$b" -eq "$a" ]] && k=$((k+1)); done
        [[ $k -gt $best ]] && { best=$k; modal=$a; }
    done
    (( modal > nc && best >= 2 )) || exit 1
    local refts=(); local refte=()
    for ((r2=1; r2<${#rows[@]}; r2++)); do
        _mb_spans "${rows[$r2]}"
        [[ ${#_MB_TOK[@]} -eq $modal ]] || continue
        refts=("${_MB_TS[@]}"); refte=("${_MB_TE[@]}"); break
    done
    [[ ${#refts[@]} -eq $modal ]] || exit 1
    _mb_best_col () {  # $1=ts $2=te -> echoes reference column with max overlap
        local ts=$1; local te=$2; local bc=0; local bo=-999999; local c2 o lo hi
        for ((c2=0; c2<modal; c2++)); do
            lo=$ts; [[ ${refts[$c2]} -gt $lo ]] && lo=${refts[$c2]}
            hi=$te; [[ ${refte[$c2]} -lt $hi ]] && hi=${refte[$c2]}
            o=$((hi - lo))
            [[ $o -gt $bo ]] && { bo=$o; bc=$c2; }
        done
        echo "$bc"
    }
    local out_rows=(); local hdr=(); local c3
    for ((c3=0; c3<modal; c3++)); do hdr+=(""); done
    _mb_spans "$hl"
    local hi2
    for ((hi2=0; hi2<${#_MB_TOK[@]}; hi2++)); do
        c3="$(_mb_best_col "${_MB_TS[$hi2]}" "${_MB_TE[$hi2]}")"
        if [[ -z "${hdr[$c3]}" ]]; then hdr[$c3]="${_MB_TOK[$hi2]}"; else hdr[$c3]+=" ${_MB_TOK[$hi2]}"; fi
    done
    local out="${hdr[0]}"
    for ((c3=1; c3<modal; c3++)); do out+=$'\t'"${hdr[$c3]}"; done
    out_rows+=("$out")
    for ((r2=1; r2<${#rows[@]}; r2++)); do
        _mb_spans "${rows[$r2]}"
        local cells2=()
        for ((c3=0; c3<modal; c3++)); do cells2+=(""); done
        for ((hi2=0; hi2<${#_MB_TOK[@]}; hi2++)); do
            c3="$(_mb_best_col "${_MB_TS[$hi2]}" "${_MB_TE[$hi2]}")"
            if [[ -z "${cells2[$c3]}" ]]; then cells2[$c3]="${_MB_TOK[$hi2]}"; else cells2[$c3]+=" ${_MB_TOK[$hi2]}"; fi
        done
        out="${cells2[0]}"
        for ((c3=1; c3<modal; c3++)); do out+=$'\t'"${cells2[$c3]}"; done
        out_rows+=("$out")
    done
    printf '%s\n' "${out_rows[@]}"
    exit 0
)

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
        # mistaken for a header must not eat its own repeats) and digit-free —
        # OR digit-bearing but with RARE repeats: sar's timestamped header
        # (`07:00:01  CPU  %user …`) re-prints each interval, and those exact
        # repeats are chrome even though the timestamp carries digits. The
        # rarity gate (repeats <= 1/4 of data rows) is what separates that from
        # a block dominated by one legitimately repeated log line (entr), where
        # the repeats ARE the data and must survive.
        local _fhdrfree=1
        if [[ ${#_fharr[@]} -lt 3 ]]; then
            _fhdrfree=0
        elif [[ "${lines[$_fhidx]}" =~ [0-9] ]]; then
            local _frep=0 _ftot=0 _fj _fjarr
            for ((_fj = _fhidx + 1; _fj < ${#lines[@]}; _fj++)); do
                _ftot=$((_ftot + 1))
                _fjarr=(); read -ra _fjarr <<< "${lines[$_fj]}"
                [[ "${_fjarr[*]}" == "$_fhnorm" ]] && _frep=$((_frep + 1))
            done
            [[ $_frep -eq 0 || $_ftot -eq 0 || $((_frep * 4)) -gt $_ftot ]] && _fhdrfree=0
        fi
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

    # FIRST-CELL WRAP: a data row that is a LONE token, followed by an INDENTED
    # row exactly one column short, is a value too long for column 1 printed on
    # its own line (df's `/dev/mapper/vg-root` over an indented `98G 45G …`) —
    # merge the pair into one row. Gated on a headed table with >=4 columns so
    # narrow key/value layouts never pair-merge.
    if [[ "$mode" == HDR && $ncols -ge 4 && ${#lines[@]} -ge 3 ]]; then
        local _mw=() _mi _mt1 _mt2
        for ((_mi = 0; _mi < ${#lines[@]}; _mi++)); do
            if [[ $_mi -gt 0 && $((_mi + 1)) -lt ${#lines[@]} ]]; then
                _mt1=(); read -ra _mt1 <<< "${lines[$_mi]}"
                if [[ ${#_mt1[@]} -eq 1 ]]; then
                    _mt2=(); read -ra _mt2 <<< "${lines[$((_mi + 1))]}"
                    # merged pair must land on a full row: ncols tokens, or one
                    # short of it (a multi-word header label like `Mounted on`
                    # makes ncols one higher than any data row)
                    if [[ $((1 + ${#_mt2[@]})) -ge $((ncols - 1)) && $((1 + ${#_mt2[@]})) -le $ncols \
                          && "${lines[$((_mi + 1))]}" == [' 	']* ]]; then
                        _mw+=("${_mt1[0]} ${_mt2[*]}")
                        _mi=$((_mi + 1))
                        continue
                    fi
                fi
            fi
            _mw+=("${lines[$_mi]}")
        done
        lines=("${_mw[@]}")
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
        else
            # EQUAL token counts can still hide multi-word labels AND multi-word
            # values in the same table ("Property Name … Group" over
            # "www.example.com … Web Delivery" — 8 tokens each). The tell: the
            # header's 2-space segmentation collapses BELOW its token count
            # (multi-word labels exist) while the DATA rows segment the same
            # way the header does. Data that segments more finely than the
            # header (pam-tally2, ip6tables — their own 2-space runs mark MORE
            # columns than the header shows) is telling us the single-spaced
            # header under-segments, and tokenization is the right reading.
            local _hsegq; _hsegq="$(_ac_seg "${lines[$hidx]}")"
            if [[ $_hsegq -ge 2 && $_hsegq -lt $_htok ]]; then
                local _dsegc=() _dsi _dsa _dsb _dsk _dsbest=0 _dsmod=0
                for ((_dsi = hidx + 1; _dsi < ${#lines[@]}; _dsi++)); do
                    _dsegc+=("$(_ac_seg "${lines[$_dsi]}")")
                done
                for _dsa in "${_dsegc[@]}"; do
                    _dsk=0; for _dsb in "${_dsegc[@]}"; do [[ "$_dsb" -eq "$_dsa" ]] && _dsk=$((_dsk + 1)); done
                    [[ $_dsk -gt $_dsbest ]] && { _dsbest=$_dsk; _dsmod=$_dsa; }
                done
                [[ $_dsmod -eq $_hsegq ]] && _use_pos=1
            fi
        fi
        # Route lightly-non-ASCII blocks (<20% multibyte chars) through the
        # char-accurate bash grid; everything else through the awk grid.
        # Only NARROW 2-byte chars qualify (±, µ, é): emoji/CJK/box-drawing
        # (3-4 byte, double-width), soft hyphens (zero-width) and combining
        # marks all break the char==display-column assumption, so those
        # blocks keep the awk path.
        local _mb_grid=""
        if [[ $_use_pos -eq 1 && "$hd" == *[![:ascii:]]* ]]; then
            local _mb_ascii="${hd//[![:ascii:]]/}"
            local _mb_wide=0
            case "$hd" in
                *$'\xe0'*|*$'\xe1'*|*$'\xe2'*|*$'\xe3'*|*$'\xe4'*|*$'\xe5'*|*$'\xe6'*|*$'\xe7'*|*$'\xe8'*|*$'\xe9'*|*$'\xea'*|*$'\xeb'*|*$'\xec'*|*$'\xed'*|*$'\xee'*|*$'\xef'*|*$'\xf0'*|*$'\xf1'*|*$'\xf2'*|*$'\xf3'*|*$'\xf4'*) _mb_wide=1 ;;
            esac
            case "$hd" in
                *$'\xc2\xad'*|*$'\xcc'*|*$'\xcd'*) _mb_wide=1 ;;
            esac
            if [[ $_mb_wide -eq 0 ]] && (( (${#hd} - ${#_mb_ascii}) * 5 < ${#hd} )); then
                _mb_grid="$(printf '%s' "$hd" | _ac_grid_mb)" || _mb_grid=""
            fi
        fi
        if [[ $_use_pos -eq 1 ]] && { [[ -n "$_mb_grid" ]] || [[ "$(printf '%s' "$hd" | _ac_aligned)" == "1" ]]; }; then
            local gridrows=() _g
            if [[ -n "$_mb_grid" ]]; then
                while IFS= read -r _g; do gridrows+=("$_g"); done <<< "$_mb_grid"
            else
                while IFS= read -r _g; do gridrows+=("$_g"); done < <(printf '%s' "$hd" | _ac_assign)
            fi
            if [[ ${#gridrows[@]} -ge 2 ]]; then
                # Tab-SAFE cell split: `IFS=$'\t' read -ra` treats TAB as IFS
                # whitespace, so leading/consecutive tabs COLLAPSE and an empty
                # leading cell shifts every value left. Split explicitly.
                _ac_cells () {
                    local _s="$1"; _AC_CELLS=()
                    while [[ "$_s" == *$'\t'* ]]; do
                        _AC_CELLS+=("${_s%%$'\t'*}"); _s="${_s#*$'\t'}"
                    done
                    _AC_CELLS+=("$_s")
                }
                # WRAPPED CELLS: rejoin continuation lines before emitting.
                #   * tail wrap — a grid row whose FIRST cell is empty and whose
                #     only content sits in the LAST cell is the previous row's
                #     last column wrapped onto a new line (kubectl events'
                #     MESSAGE, systemctl's DESCRIPTION, crontab COMMAND): append
                #     it, space-joined. A sparse-matrix row keeps its row label,
                #     so first-cell-empty + only-last-cell never fires there.
                #   * leading overflow — a grid row with ONLY its first cell
                #     filled, when the NEXT row's first cell is empty, is a value
                #     too long for column 1 printed alone (df's long device
                #     path): carry it into the next row's first cell.
                local _wj=() _wr _wc=() _wn _wonly_last _wonly_first _wnc
                for ((_wr = 1; _wr < ${#gridrows[@]}; _wr++)); do
                    _ac_cells "${gridrows[$_wr]}"; _wc=("${_AC_CELLS[@]}")
                    _wnc=${#_wc[@]}
                    _wonly_last=0; _wonly_first=0
                    if [[ $_wnc -ge 2 ]]; then
                        local _wi _wfilled=0 _wlastfill=0 _wfirstfill=0
                        for ((_wi = 0; _wi < _wnc; _wi++)); do
                            [[ -n "${_wc[$_wi]//[[:space:]]/}" ]] || continue
                            _wfilled=$((_wfilled + 1))
                            [[ $_wi -eq $((_wnc - 1)) ]] && _wlastfill=1
                            [[ $_wi -eq 0 ]] && _wfirstfill=1
                        done
                        [[ $_wfilled -eq 1 && $_wlastfill -eq 1 ]] && _wonly_last=1
                        [[ $_wfilled -eq 1 && $_wfirstfill -eq 1 ]] && _wonly_first=1
                    fi
                    if [[ $_wonly_last -eq 1 && ${#_wj[@]} -gt 0 ]]; then
                        # append to previous kept row's last cell
                        local _wprev=() _wpi=$(( ${#_wj[@]} - 1 ))
                        _ac_cells "${_wj[$_wpi]}"; _wprev=("${_AC_CELLS[@]}")
                        _wprev[$((${#_wprev[@]} - 1))]="${_wprev[$((${#_wprev[@]} - 1))]:+${_wprev[$((${#_wprev[@]} - 1))]} }${_wc[$((_wnc - 1))]}"
                        _wj[$_wpi]="$(IFS=$'\t'; printf '%s' "${_wprev[*]}")"
                        continue
                    fi
                    if [[ $_wonly_first -eq 1 && $((_wr + 1)) -lt ${#gridrows[@]} ]]; then
                        local _wnext=(); _ac_cells "${gridrows[$((_wr + 1))]}"; _wnext=("${_AC_CELLS[@]}")
                        if [[ ${#_wnext[@]} -ge 2 && -z "${_wnext[0]//[[:space:]]/}" ]]; then
                            _wnext[0]="${_wc[0]}"
                            gridrows[$((_wr + 1))]="$(IFS=$'\t'; printf '%s' "${_wnext[*]}")"
                            continue
                        fi
                    fi
                    _wj+=("${gridrows[$_wr]}")
                done
                gridrows=("${gridrows[0]}" "${_wj[@]}")

                local headers=() result="" entry=0 li i
                # Tab-SAFE header split too: the ragged-alignment mb grid can
                # emit EMPTY leading/interior header cells (asv's unnamed sign
                # column) — IFS-tab read would strip them and shift every name
                # left. Empty cells fall through to the letter fallback below.
                _ac_cells "${gridrows[0]}"; headers=("${_AC_CELLS[@]}")
                for ((i = 0; i < ${#headers[@]}; i++)); do
                    local h="${headers[$i]//./_}"; h="${h// /_}"
                    while [[ "$h" == *__* ]]; do h="${h//__/_}"; done
                    h="${h#_}"; h="${h%_}"; [[ -z "$h" ]] && h="$(_col_letter $((i + 1)))"
                    headers[$i]="$h"
                done
                for ((li = 1; li < ${#gridrows[@]}; li++)); do
                    local values; _ac_cells "${gridrows[$li]}"; values=("${_AC_CELLS[@]}")
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

    # OFFSET ASSIGNMENT for SPARSE tables. When data rows carry FEWER tokens
    # than the header names columns, whitespace tokenization assigns the
    # surviving values to the FIRST header names rather than their own:
    # `lsblk -f` (five of eight columns empty on every row) put sizes under
    # FSTYPE and mountpoints under LABEL, and `lsof` put USER under TID — and
    # nothing in the output betrays the error, which is what makes this the
    # most insidious defect the held-out benchmark found. The header's
    # CHARACTER OFFSETS say which column a value belongs to; use them.
    #
    # Each data token goes to the header token whose printed span it overlaps
    # most (nearest span when a right-aligned value pokes out); everything at
    # or past the last header's start joins the last column, which is where
    # free-text tails (lsof's NAME) live. The whole parse is buffered and
    # WITHDRAWN unless >=80% of data tokens actually overlap a header span —
    # a table that is not genuinely offset-aligned falls through to the
    # tokenized path below exactly as before.
    if [[ "$mode" == HDR && ${#lines[@]} -ge 3 ]]; then
        local _oa_h=(); read -ra _oa_h <<< "${lines[0]}"
        if [[ ${#_oa_h[@]} -ge 4 ]]; then
            # Modal data-row token count, and raggedness.
            local _oa_cnt=() _oa_i _oa_t _oa_mod=0 _oa_ba _oa_bb _oa_bk _oa_best=0
            for ((_oa_i = 1; _oa_i < ${#lines[@]}; _oa_i++)); do
                _oa_t=(); read -ra _oa_t <<< "${lines[$_oa_i]}"
                _oa_cnt+=("${#_oa_t[@]}")
            done
            for _oa_ba in "${_oa_cnt[@]}"; do
                _oa_bk=0; for _oa_bb in "${_oa_cnt[@]}"; do [[ "$_oa_bb" -eq "$_oa_ba" ]] && _oa_bk=$((_oa_bk + 1)); done
                [[ $_oa_bk -gt $_oa_best ]] && { _oa_best=$_oa_bk; _oa_mod=$_oa_ba; }
            done
            if [[ $_oa_mod -lt ${#_oa_h[@]} && $_oa_mod -ge 1 ]]; then
                local _oa_out
                _oa_out=$(printf '%s\n' "${lines[@]}" | awk '
                    NR == 1 {
                        # Header token spans (1-based columns).
                        len = length($0); st = 0; nh = 0
                        for (i = 1; i <= len + 1; i++) {
                            c = (i <= len) ? substr($0, i, 1) : " "
                            if (c != " " && c != "\t") { if (st == 0) st = i }
                            else if (st > 0) {
                                nh++; hs[nh] = st; he[nh] = i - 1
                                nm = substr($0, st, i - st)
                                gsub(/\./, "_", nm)
                                hn[nh] = nm
                                st = 0
                            }
                        }
                        # A trailing preposition is the tail of a two-word
                        # label (`Mounted on`), not a column of its own —
                        # weld it onto its neighbour so the last value gets
                        # the full name instead of a truncated one.
                        pl = tolower(hn[nh])
                        if (nh >= 3 && pl ~ /^(on|by|in|at|of|to)$/) {
                            hn[nh - 1] = hn[nh - 1] "_" hn[nh]
                            he[nh - 1] = he[nh]
                            nh--
                        }
                        # DUPLICATE header token names are the signature of
                        # multi-word labels tokenized apart: doctl repeats ID
                        # (`Active Deployment ID` / `In Progress Deployment
                        # ID`), spark repeats Tasks three times. Per-token
                        # spans are meaningless there — the duplicate names
                        # collide in the melt and each label loses half of
                        # itself — so the whole path withdraws.
                        for (i = 1; i <= nh; i++)
                            for (j = i + 1; j <= nh; j++)
                                if (hn[i] == hn[j]) { dupname = 1 }
                        next
                    }
                    {
                        row++
                        len = length($0); st = 0
                        for (c = 1; c <= nh; c++) cells[c] = ""
                        for (i = 1; i <= len + 1; i++) {
                            ch = (i <= len) ? substr($0, i, 1) : " "
                            if (ch != " " && ch != "\t") { if (st == 0) st = i }
                            else if (st > 0) {
                                s = st; e = i - 1; st = 0
                                tok = substr($0, s, e - s + 1)
                                if (s >= hs[nh]) { col = nh; ov = 1 }
                                else {
                                    col = 0; ov = 0; nspan = 0
                                    for (c = 1; c <= nh; c++) {
                                        lo = (s > hs[c]) ? s : hs[c]
                                        hi = (e < he[c]) ? e : he[c]
                                        o = hi - lo + 1
                                        if (o > 0) nspan++
                                        if (o > ov) { ov = o; col = c }
                                    }
                                    # A token stretching across TWO header
                                    # token spans is a value sitting under a
                                    # multi-word label (`starfish-api` under
                                    # `Spec Name`) — count them; too many and
                                    # the table is not per-token aligned.
                                    if (nspan >= 2) nwide++
                                    if (col == 0) {
                                        # no overlap: nearest span by gap
                                        bd = -1
                                        for (c = 1; c <= nh; c++) {
                                            d = (e < hs[c]) ? hs[c] - e : s - he[c]
                                            if (bd < 0 || d < bd) { bd = d; col = c }
                                        }
                                    }
                                }
                                ntok++
                                if (ov > 0) nhit++
                                # Edge alignment: a genuinely offset-aligned
                                # table puts each value START at its header
                                # label start (left-aligned columns) or its
                                # END at the label end (right-aligned
                                # numerics). Prose that merely OVERLAPS spans
                                # (deno error lines under a first line
                                # mistaken for a header) has almost no edge
                                # hits, and that difference is the gate.
                                # NOTE: this comment sits inside a single-
                                # quoted awk program — no apostrophes.
                                for (c2 = 1; c2 <= nh; c2++)
                                    if (s == hs[c2] || e == he[c2]) { nedge++; break }
                                cells[col] = (cells[col] == "") ? tok : cells[col] " " tok
                            }
                        }
                        for (c = 1; c <= nh; c++)
                            if (cells[c] != "")
                                buf = buf "entry" row "." hn[c] " " cells[c] "\n"
                    }
                    END {
                        # Withdraw unless the rows really sit under the header:
                        # >=80% of tokens overlap a header span AND >=60% land
                        # exactly on a span edge (left- or right-aligned) AND
                        # the header names are per-token meaningful — no
                        # duplicate names, and <10% of tokens spanning two
                        # labels (multi-word-label tables belong to the
                        # positional grid / seg-split paths, not this one).
                        if (row == 0 || ntok == 0 || nhit * 5 < ntok * 4) exit 0
                        if (nedge * 10 < ntok * 6) exit 0
                        if (dupname) exit 0
                        if (nwide * 10 > ntok) exit 0
                        printf "%s", buf
                        printf "total_entries %d\n", row
                    }
                ')
                if [[ -n "$_oa_out" ]]; then
                    echo "$_oa_out"; return 0
                fi
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
    # HDR2 group-prefixing: when the field row repeats names under different
    # group labels (`Pod  Req Lim Use  Req Lim Use` under `CPU  Memory`), the
    # duplicates would COLLIDE in the wide record and the melt silently drops
    # the earlier group's columns. Disambiguate positionally: each duplicated
    # header token (except the first, key column) gets the group label whose
    # printed CENTER is nearest — `CPU_Req`, `Memory_Req`. Unique names stay
    # untouched, so single-group two-line headers (vmstat) are unaffected.
    if [[ "$mode" == HDR2 && ${#headers[@]} -ge 3 ]]; then
        local _gpdup=0 _gpi _gpj
        for ((_gpi = 1; _gpi < ${#headers[@]} && _gpdup == 0; _gpi++)); do
            for ((_gpj = _gpi + 1; _gpj < ${#headers[@]}; _gpj++)); do
                [[ "${headers[$_gpi]}" == "${headers[$_gpj]}" ]] && { _gpdup=1; break; }
            done
        done
        if [[ $_gpdup -eq 1 ]]; then
            # token centers of a raw line -> _GP_CENTERS / _GP_TOKS
            _gp_scan () {
                local _s="$1"
                local _i _c _st=-1 _n=${#_s}
                _GP_CENTERS=(); _GP_TOKS=()
                for ((_i = 0; _i <= _n; _i++)); do
                    _c="${_s:$_i:1}"
                    if [[ "$_c" != " " && "$_c" != "	" && $_i -lt $_n ]]; then
                        [[ $_st -lt 0 ]] && _st=$_i
                    elif [[ $_st -ge 0 ]]; then
                        _GP_TOKS+=("${_s:$_st:$((_i - _st))}")
                        _GP_CENTERS+=($(( (_st + _i - 1) / 2 )))
                        _st=-1
                    fi
                done
            }
            _gp_scan "${lines[0]}"
            local _gpg_toks=("${_GP_TOKS[@]}") _gpg_cent=("${_GP_CENTERS[@]}")
            # The group row's tokens become NAME PREFIXES — sanitize each
            # (vmstat -d's `------------reads------------` → `reads`), and bail
            # out entirely when the row is banner chrome rather than labels
            # (goose's `=== PER REQUEST METRICS ===`: punctuation-only edge
            # tokens mark a banner, whose words would make junk prefixes).
            local _gpk _gpsan=1
            if [[ ! "${_gpg_toks[0]}" =~ [A-Za-z0-9] \
                  || ! "${_gpg_toks[$(( ${#_gpg_toks[@]} - 1 ))]}" =~ [A-Za-z0-9] ]]; then
                _gpsan=0
            fi
            for ((_gpk = 0; _gpk < ${#_gpg_toks[@]}; _gpk++)); do
                local _gpt="${_gpg_toks[$_gpk]}"
                _gpt="${_gpt##+(-)}"; _gpt="${_gpt%%+(-)}"
                while [[ "$_gpt" == -* ]]; do _gpt="${_gpt#-}"; done
                while [[ "$_gpt" == *- ]]; do _gpt="${_gpt%-}"; done
                [[ -z "$_gpt" ]] && { _gpsan=0; break; }
                _gpg_toks[$_gpk]="$_gpt"
            done
            _gp_scan "${lines[1]}"
            local _gph_cent=("${_GP_CENTERS[@]}")
            if [[ $_gpsan -eq 1 && ${#_gpg_toks[@]} -ge 2 && ${#_gph_cent[@]} -eq ${#headers[@]} ]]; then
                # Mark duplicates on the ORIGINAL names first — renaming inside
                # the same pass would hide a later twin (`Req` at index 4 stops
                # matching once index 1 became `CPU_Req`) and leave the second
                # group's columns bare and still colliding with any third.
                local _gpdups=()
                for ((_gpi = 0; _gpi < ${#headers[@]}; _gpi++)); do _gpdups[$_gpi]=0; done
                for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                    for ((_gpj = 1; _gpj < ${#headers[@]}; _gpj++)); do
                        [[ $_gpj -ne $_gpi && "${headers[$_gpj]}" == "${headers[$_gpi]}" ]] && { _gpdups[$_gpi]=1; break; }
                    done
                done
                for ((_gpi = 1; _gpi < ${#headers[@]}; _gpi++)); do
                    [[ ${_gpdups[$_gpi]} -eq 0 ]] && continue
                    local _gpbest=0 _gpbd=999999 _gpdist
                    for ((_gpj = 0; _gpj < ${#_gpg_toks[@]}; _gpj++)); do
                        _gpdist=$(( ${_gph_cent[$_gpi]} - ${_gpg_cent[$_gpj]} ))
                        [[ $_gpdist -lt 0 ]] && _gpdist=$(( -_gpdist ))
                        [[ $_gpdist -lt $_gpbd ]] && { _gpbd=$_gpdist; _gpbest=$_gpj; }
                    done
                    headers[$_gpi]="${_gpg_toks[$_gpbest]}_${headers[$_gpi]}"
                done
            fi
        fi
    fi
    # Field names must not contain '.' (the tidy melt splits entry<N>.<field> on
    # the first dot).
    for ((i = 0; i < ${#headers[@]}; i++)); do headers[$i]="${headers[$i]//./_}"; done

    # A TRAILING PREPOSITION in the header is the tail of a two-word label,
    # not a column: df's `Mounted on` tokenizes as two names, the data rows
    # run one token short, and the last real value landed under `Mounted`
    # with `on` forever empty — silently truncating the label. When the data
    # rows are exactly one short and the last header token is such a word,
    # weld it onto its neighbour (`Mounted_on`).
    if [[ ( "$mode" == HDR || "$mode" == HDR2 ) && ${#headers[@]} -ge 3 ]]; then
        local _tp_last="${headers[$(( ${#headers[@]} - 1 ))]}"
        local _tp_lc="${_tp_last,,}"
        case "$_tp_lc" in
            on|by|in|at|of|to)
                local _tp_cnt=() _tp_i _tp_t _tp_mod=0 _tp_a _tp_b _tp_k _tp_best=0
                for ((_tp_i = startidx; _tp_i < ${#lines[@]}; _tp_i++)); do
                    _tp_t=(); read -ra _tp_t <<< "${lines[$_tp_i]}"
                    _tp_cnt+=("${#_tp_t[@]}")
                done
                for _tp_a in "${_tp_cnt[@]}"; do
                    _tp_k=0; for _tp_b in "${_tp_cnt[@]}"; do [[ "$_tp_b" -eq "$_tp_a" ]] && _tp_k=$((_tp_k + 1)); done
                    [[ $_tp_k -gt $_tp_best ]] && { _tp_best=$_tp_k; _tp_mod=$_tp_a; }
                done
                if [[ $_tp_mod -eq $(( ${#headers[@]} - 1 )) ]]; then
                    headers[$(( ${#headers[@]} - 2 ))]="${headers[$(( ${#headers[@]} - 2 ))]}_${_tp_last}"
                    unset 'headers[$(( ${#headers[@]} - 1 ))]'
                    headers=("${headers[@]}")
                fi
                ;;
        esac
    fi

    # SCAFFOLD SPLIT: headerless RAGGED rows sharing >=2 function words
    # (`? (ip) at MAC [ether] on eth0` / `? (ip) at <incomplete> on eth0`,
    # arp -an) are sentence-records, and per-position columns misalign the
    # moment an optional field is absent. The constant function words are the
    # real field boundaries: split there, name each following segment after
    # its scaffold word, and keep multi-token segments as ONE cell. Fires
    # only when every row carries the SAME allowlisted words (at on from via
    # dev to of by for), each exactly once, in the same order, with a uniform
    # prefix width — so ordinary uniform tables and ip-route-style blocks
    # (word sets differ per row) never enter.
    if [[ "$mode" == HL && ${#lines[@]} -ge 2 ]]; then
        local _sc_r _sc_tk _sc_w0=-1 _sc_ragged=0
        for ((_sc_r = startidx; _sc_r < ${#lines[@]}; _sc_r++)); do
            _sc_tk=(); read -ra _sc_tk <<< "${lines[$_sc_r]}"
            [[ $_sc_w0 -lt 0 ]] && _sc_w0=${#_sc_tk[@]}
            [[ ${#_sc_tk[@]} -ne $_sc_w0 ]] && _sc_ragged=1
        done
        if [[ $_sc_ragged -eq 1 ]]; then
            local _sc_seq=() _sc_pre=-1 _sc_ok=1 _sc_t _sc_i
            _sc_tk=(); read -ra _sc_tk <<< "${lines[$startidx]}"
            for ((_sc_i = 0; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                case "${_sc_tk[$_sc_i]}" in
                    at|on|from|via|dev|to|of|by|for)
                        [[ ${#_sc_seq[@]} -eq 0 ]] && _sc_pre=$_sc_i
                        _sc_seq+=("${_sc_tk[$_sc_i]}") ;;
                esac
            done
            local _sc_a _sc_b
            for ((_sc_a = 0; _sc_a < ${#_sc_seq[@]} && _sc_ok == 1; _sc_a++)); do
                for ((_sc_b = _sc_a + 1; _sc_b < ${#_sc_seq[@]}; _sc_b++)); do
                    [[ "${_sc_seq[$_sc_a]}" == "${_sc_seq[$_sc_b]}" ]] && { _sc_ok=0; break; }
                done
            done
            if [[ $_sc_ok -eq 1 && ${#_sc_seq[@]} -ge 2 && $_sc_pre -ge 1 ]]; then
                # verify every row: same words, same order, exactly once,
                # same prefix width
                local _sc_rows=()
                for ((_sc_r = startidx; _sc_r < ${#lines[@]} && _sc_ok == 1; _sc_r++)); do
                    _sc_tk=(); read -ra _sc_tk <<< "${lines[$_sc_r]}"
                    local _sc_found=() _sc_fpre=-1
                    for ((_sc_i = 0; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                        case "${_sc_tk[$_sc_i]}" in
                            at|on|from|via|dev|to|of|by|for)
                                [[ ${#_sc_found[@]} -eq 0 ]] && _sc_fpre=$_sc_i
                                _sc_found+=("${_sc_tk[$_sc_i]}") ;;
                        esac
                    done
                    [[ "${_sc_found[*]}" == "${_sc_seq[*]}" && $_sc_fpre -eq $_sc_pre ]] || _sc_ok=0
                done
                if [[ $_sc_ok -eq 1 ]]; then
                    local _sc_res="" _sc_e=0
                    for ((_sc_r = startidx; _sc_r < ${#lines[@]}; _sc_r++)); do
                        _sc_tk=(); read -ra _sc_tk <<< "${lines[$_sc_r]}"
                        _sc_e=$((_sc_e + 1))
                        for ((_sc_i = 0; _sc_i < _sc_pre; _sc_i++)); do
                            _sc_res+="entry${_sc_e}.$(_col_letter $((_sc_i + 1))) ${_sc_tk[$_sc_i]}"$'\n'
                        done
                        local _sc_name="" _sc_val=""
                        for ((_sc_i = _sc_pre; _sc_i < ${#_sc_tk[@]}; _sc_i++)); do
                            local _sc_isword=0
                            case "${_sc_tk[$_sc_i]}" in
                                at|on|from|via|dev|to|of|by|for) _sc_isword=1 ;;
                            esac
                            if [[ $_sc_isword -eq 1 ]]; then
                                [[ -n "$_sc_name" && -n "$_sc_val" ]] && _sc_res+="entry${_sc_e}.${_sc_name} ${_sc_val}"$'\n'
                                _sc_name="${_sc_tk[$_sc_i]}"; _sc_val=""
                            else
                                _sc_val+="${_sc_val:+ }${_sc_tk[$_sc_i]}"
                            fi
                        done
                        [[ -n "$_sc_name" && -n "$_sc_val" ]] && _sc_res+="entry${_sc_e}.${_sc_name} ${_sc_val}"$'\n'
                    done
                    if [[ $_sc_e -gt 0 ]]; then
                        _sc_res+="total_entries ${_sc_e}"$'\n'
                        echo "$_sc_res"; return 0
                    fi
                fi
            fi
        fi
    fi

    # HEADERLESS PHRASE MERGE: with no header to say otherwise, the TRAILING
    # pair of columns holding the SAME two lowercase words on every row
    # ("not confined" split into C/D — aa-unconfined) is one status phrase,
    # not two columns. Trailing-only: a constant mid-table word pair is a
    # real pair of columns that happens to be constant (`ls -l`'s owner and
    # group, masscan's "open port"), so only the LAST pair may merge. Both
    # cells pure lowercase alpha, identical down the whole table, every row
    # full-width.
    local _pm_join=()
    if [[ "$mode" == HL && ${#headers[@]} -ge 3 && ${#lines[@]} -ge 2 ]]; then
        local _pm_c _pm_l _pm_vals _pm_first _pm_ok
        for ((i = 0; i < ${#headers[@]}; i++)); do _pm_join[$i]=0; done
        _pm_c=$(( ${#headers[@]} - 1 ))
        _pm_ok=1; _pm_first=""
        for ((_pm_l = startidx; _pm_l < ${#lines[@]}; _pm_l++)); do
            _pm_vals=(); read -ra _pm_vals <<< "${lines[$_pm_l]}"
            [[ ${#_pm_vals[@]} -eq ${#headers[@]} ]] || { _pm_ok=0; break; }
            local _pm_pair="${_pm_vals[$((_pm_c - 1))]} ${_pm_vals[$_pm_c]}"
            [[ "${_pm_vals[$((_pm_c - 1))]}" =~ ^[a-z]+$ && "${_pm_vals[$_pm_c]}" =~ ^[a-z]+$ ]] || { _pm_ok=0; break; }
            [[ -z "$_pm_first" ]] && _pm_first="$_pm_pair"
            [[ "$_pm_pair" != "$_pm_first" ]] && { _pm_ok=0; break; }
        done
        [[ $_pm_ok -eq 1 ]] && _pm_join[$_pm_c]=1
    fi

    # Emit each data line as an indexed group (entry<N>.<field>) so the tidy melt
    # renders one row per line with shared columns.
    local result="" entry=0 li
    for ((li = startidx; li < ${#lines[@]}; li++)); do
        local values; values=(); read -ra values <<< "${lines[$li]}"
        # Apply the phrase merges (right-to-left so indices stay valid).
        if [[ ${#_pm_join[@]} -gt 0 && ${#values[@]} -eq ${#headers[@]} ]]; then
            for ((i = ${#headers[@]} - 1; i >= 1; i--)); do
                [[ "${_pm_join[$i]:-0}" -eq 1 ]] || continue
                values[$((i - 1))]="${values[$((i - 1))]} ${values[$i]}"
                values=("${values[@]:0:$i}" "${values[@]:$((i + 1))}")
            done
        fi
        entry=$((entry + 1))
        local _ncols=${#headers[@]}
        if [[ ${#_pm_join[@]} -gt 0 ]]; then
            _ncols=0
            for ((i = 0; i < ${#headers[@]}; i++)); do
                [[ "${_pm_join[$i]:-0}" -eq 1 ]] || _ncols=$((_ncols + 1))
            done
        fi
        for ((i = 0; i < _ncols; i++)); do
            local name; name="$(_col_letter $((i + 1)))"
            [[ ${#_pm_join[@]} -eq 0 || $_ncols -eq ${#headers[@]} ]] && name="${headers[$i]}"
            local value="${values[$i]:-}"
            [[ -z "$value" ]] && continue
            # Last column absorbs any extra trailing tokens.
            if [[ $i -eq $((_ncols - 1)) && ${#values[@]} -gt $_ncols ]]; then
                local j
                for ((j = i + 1; j < ${#values[@]}; j++)); do value+="_${values[$j]}"; done
            fi
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
