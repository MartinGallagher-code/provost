#!/bin/bash
## Name: grouped-rows
## Description: Group-header lines over indented tabular rows — the group keys carried down onto each leaf row
## Version: 1.0
## Priority: 41
## Sample: samples/grouped-rows/basic.txt

# The nested-records shape: an outer GROUP line establishing context, then
# INDENTED tabular rows that belong to it — possibly through two levels:
#
#   Region: us-east-1                COMMAND=nginx  PID=1201  USER=www-data
#     AZ: us-east-1a                   FD   TYPE   DEVICE   NAME
#       i-0a11  m5.large  running      cwd  DIR    8,1      /
#       i-0a12  t3.micro  running      0u   CHR    1,3      /dev/null
#
# The lossless tidy carries each group's key(s) down onto its leaf rows:
# (region, az, A, B, C) / (command, pid, user, fd, type, device, name). A group
# line is either `Label: value` (one simple-token label) or a run of KEY=value
# tokens; a leaf row is TABULAR — >=2 whitespace tokens that are NOT themselves
# `key: value` pairs (a kv block under a header is a hierarchy/yaml, not a
# grouped table, and stays with those parsers). A digit-free first leaf row over
# digit-bearing ones names the leaf columns (`Product Units Revenue`,
# `FD TYPE DEVICE NAME`); otherwise columns are synthesised. Subtotal/total
# leaf rows are data, per the corpus-wide convention.

# Classify a line. Sets:
#   _GR_KIND   group|leaf|blank|other
#   _GR_IND    leading-space count
#   _GR_KEYS   for a group: TAB-separated key=value pairs (label lowercased)
_gr_classify () {
    local l="$1"
    _GR_KIND="other"; _GR_IND=0; _GR_KEYS=""
    [[ -z "${l//[[:space:]]/}" ]] && { _GR_KIND="blank"; return; }
    local ind="${l%%[![:space:]]*}"; _GR_IND=${#ind}
    local t="${l#"${l%%[![:space:]]*}"}"
    while [[ "$t" == *" " || "$t" == *$'\t' ]]; do t="${t%?}"; done
    # group form (b): >=2 KEY=value tokens (lsof-style COMMAND=nginx PID=1201)
    local _tk=() _n_eq=0 _tok
    read -ra _tk <<< "$t"
    for _tok in "${_tk[@]}"; do
        [[ "$_tok" == *=* ]] || continue
        local _k="${_tok%%=*}"
        case "$_k" in ""|*[!A-Za-z0-9_-]*) ;; *) _n_eq=$((_n_eq + 1)) ;; esac
    done
    if [[ $_n_eq -ge 2 && $_n_eq -eq ${#_tk[@]} ]]; then
        _GR_KIND="group"
        local _kv
        for _tok in "${_tk[@]}"; do
            _kv="${_tok%%=*}"; _kv="$(printf '%s' "$_kv" | tr '[:upper:]' '[:lower:]')"
            _GR_KEYS+="${_GR_KEYS:+$'\t'}${_kv}=${_tok#*=}"
        done
        return
    fi
    # group form (e): >=2 colon-terminated labels each followed by a value
    # token (`Filesystem UUID: 3f7a-c2e1  Label: data`) — keys from the labels
    local _ei _elab=0 _ekeys=""
    for ((_ei = 0; _ei < ${#_tk[@]} - 1; _ei++)); do
        local _et="${_tk[$_ei]}"
        if [[ "$_et" =~ ^[A-Za-z][A-Za-z0-9_-]*:$ ]]; then
            local _next="${_tk[$((_ei + 1))]}"
            [[ "$_next" =~ :$ ]] && continue
            _elab=$((_elab + 1))
            _ekeys+="${_ekeys:+$'\t'}$(printf '%s' "${_et%:}" | tr '[:upper:]' '[:lower:]')=${_next}"
        fi
    done
    if [[ $_elab -ge 2 ]]; then
        _GR_KIND="group"; _GR_KEYS="$_ekeys"
        return
    fi
    # group form (a): `Label: value` — colon followed by whitespace, ONE simple
    # label, value NOT a long sentence (<=3 tokens keeps prose out). The
    # no-space variant (`group:web`) counts ONLY when it is alone on the line —
    # `worker:w_02  STARTING` is a data row whose first cell contains a colon.
    if [[ "$t" =~ ^([A-Za-z][A-Za-z0-9_-]*):[[:space:]]+([^[:space:]].*)$ ]]; then
        local _lab="${BASH_REMATCH[1]}" _val="${BASH_REMATCH[2]}"
        local _vt=(); read -ra _vt <<< "$_val"
        if [[ ${#_vt[@]} -le 3 ]]; then
            _GR_KIND="group"
            _GR_KEYS="$(printf '%s' "$_lab" | tr '[:upper:]' '[:lower:]')=${_val}"
            return
        fi
    fi
    if [[ ${#_tk[@]} -eq 1 && "$t" =~ ^([A-Za-z][A-Za-z0-9_-]*):([^[:space:]]+)$ ]]; then
        _GR_KIND="group"
        _GR_KEYS="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]')=${BASH_REMATCH[2]}"
        return
    fi
    # group form (c): trailing-colon block opener — `Node node-01:`, `Videos:`
    # (<=3 tokens, colon only at the very end)
    if [[ "$t" =~ ^([A-Za-z][^:]{0,49}):$ ]]; then
        local _body="${BASH_REMATCH[1]}"
        local _bt=(); read -ra _bt <<< "$_body"
        if [[ ${#_bt[@]} -ge 1 && ${#_bt[@]} -le 3 ]]; then
            _GR_KIND="group"
            if [[ ${#_bt[@]} -ge 2 ]]; then
                _GR_KEYS="$(printf '%s' "${_bt[0]}" | tr '[:upper:]' '[:lower:]')=${_body#* }"
            else
                _GR_KEYS="group=${_bt[0]}"
            fi
            return
        fi
    fi
    # group form (d): a single bare token opening an indented block (`Images`,
    # `Documents`) — classified group here; detection still demands the
    # tabular-leaf structure around it, so a lone word in prose never matters
    if [[ ${#_tk[@]} -eq 1 && "$t" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]]; then
        _GR_KIND="group"
        _GR_KEYS="group=${t}"
        return
    fi
    # a YAML list item is a mapping entry, never a grouped-table row — treat as
    # unclassifiable so detection walks away from YAML documents entirely
    [[ "$t" == "- "* || "$t" == "-" ]] && return
    # leaf: >=2 tokens, not a kv pair itself
    if [[ ${#_tk[@]} -ge 2 && ! "$t" =~ ^[A-Za-z][A-Za-z0-9_-]*:([[:space:]]|$) ]]; then
        _GR_KIND="leaf"
        _GR_NTOK=${#_tk[@]}
        return
    fi
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local _l groups=0 leaves=0 last_group_ind=-1 leaf_after_group=0 min_ind=-1
    local _lcounts=()
    while IFS= read -r _l; do
        _gr_classify "$_l"
        case "$_GR_KIND" in
            blank) continue ;;
            group)
                # track the outermost indent; groups must live at it (or nested deeper)
                [[ $min_ind -lt 0 || $_GR_IND -lt $min_ind ]] && min_ind=$_GR_IND
                groups=$((groups + 1)); last_group_ind=$_GR_IND ;;
            leaf)
                [[ $min_ind -lt 0 ]] && min_ind=$_GR_IND
                leaves=$((leaves + 1)); _lcounts+=("$_GR_NTOK")
                [[ $last_group_ind -ge 0 && $_GR_IND -gt $last_group_ind ]] && leaf_after_group=$((leaf_after_group + 1)) ;;
            other) return 1 ;;   # prose or unclassifiable line — not this shape
        esac
    done <<< "$text"
    # >=2 groups, >=3 leaves, and most leaves sit deeper than a group
    [[ $groups -ge 2 && $leaves -ge 3 ]] || return 1
    [[ $((leaf_after_group * 3)) -ge $((leaves * 2)) ]] || return 1
    # a grouped TABLE has more rows than group headers — a kv hierarchy where
    # most lines parse as "groups" (homectl, pgbackrest) is not this shape
    [[ $leaves -ge $groups ]] || return 1
    # leaves must be a table: a modal token count (±1) covering >=70% of rows.
    # Hierarchy attribute lines (ifconfig's inet/ether/RX mix: 9,4,6,7 tokens)
    # vary far too much to qualify.
    local _ma _mb _mk _mbest=0 _modal=0
    for _ma in "${_lcounts[@]}"; do
        _mk=0
        for _mb in "${_lcounts[@]}"; do
            local _md=$(( _ma - _mb )); [[ ${_md#-} -le 1 ]] && _mk=$((_mk + 1))
        done
        [[ $_mk -gt $_mbest ]] && { _mbest=$_mk; _modal=$_ma; }
    done
    [[ $(( _mbest * 100 )) -ge $(( leaves * 70 )) ]] || return 1
    _STRATEGY_CONFIDENCE=82
    _STRATEGY_CONFIDENCE_REASON="group headers over indented tabular rows"
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0
    # context stack: parallel arrays of indent + TAB-joined key=value pairs
    local ctx_ind=() ctx_keys=()
    # leaf sub-header per group block; only the FIRST leaf after a group may be
    # one (a later digit-free leaf — "w_02  STARTING" — is data)
    local subhdr=() subhdr_valid=0 first_leaf=0
    local _l i
    while IFS= read -r _l; do
        _gr_classify "$_l"
        case "$_GR_KIND" in
            blank|other) continue ;;
            group)
                # pop contexts at same or deeper indent
                while [[ ${#ctx_ind[@]} -gt 0 && ${ctx_ind[$(( ${#ctx_ind[@]} - 1 ))]} -ge $_GR_IND ]]; do
                    unset 'ctx_ind[${#ctx_ind[@]}-1]'; unset 'ctx_keys[${#ctx_keys[@]}-1]'
                    ctx_ind=("${ctx_ind[@]}"); ctx_keys=("${ctx_keys[@]}")
                done
                ctx_ind+=("$_GR_IND"); ctx_keys+=("$_GR_KEYS")
                subhdr=(); subhdr_valid=0; first_leaf=1
                ;;
            leaf)
                # a leaf at (or above) a group's indent has LEFT that group —
                # supervisorctl's trailing ungrouped `scheduler` row must not
                # inherit `group=worker`
                while [[ ${#ctx_ind[@]} -gt 0 && ${ctx_ind[$(( ${#ctx_ind[@]} - 1 ))]} -ge $_GR_IND ]]; do
                    unset 'ctx_ind[${#ctx_ind[@]}-1]'; unset 'ctx_keys[${#ctx_keys[@]}-1]'
                    ctx_ind=("${ctx_ind[@]}"); ctx_keys=("${ctx_keys[@]}")
                done
                local _tk=(); read -ra _tk <<< "${_l#"${_l%%[![:space:]]*}"}"
                # a digit-free FIRST leaf right under a group is the sub-table
                # header naming the leaf columns
                if [[ $first_leaf -eq 1 && ! "$_l" =~ [0-9] ]]; then
                    subhdr=("${_tk[@]}"); subhdr_valid=1; first_leaf=0
                    continue
                fi
                first_leaf=0
                entry=$((entry + 1))
                # carried group keys (outermost first)
                local _c _pair
                for ((_c = 0; _c < ${#ctx_keys[@]}; _c++)); do
                    while IFS= read -r -d $'\t' _pair || [[ -n "$_pair" ]]; do
                        # the <<< herestring appends a newline that survives the
                        # tab-delimited read as a ghost pair — strip and require
                        # a real key=value
                        _pair="${_pair//$'\n'/}"
                        [[ -z "$_pair" || "$_pair" != *=* ]] && continue
                        local _pk="${_pair%%=*}" _pv="${_pair#*=}"
                        _pk="${_pk// /_}"
                        result+="entry${entry}.${_pk} ${_pv}"$'\n'
                    done <<< "${ctx_keys[$_c]}"$'\t'
                done
                # leaf columns
                for ((i = 0; i < ${#_tk[@]}; i++)); do
                    local _name
                    if [[ $subhdr_valid -eq 1 && $i -lt ${#subhdr[@]} ]]; then
                        _name="${subhdr[$i]//./_}"; _name="${_name// /_}"
                    else
                        _name="$(_col_letter $((i + 1)))"
                    fi
                    [[ -z "${_tk[$i]}" ]] && continue
                    result+="entry${entry}.${_name} ${_tk[$i]}"$'\n'
                done
                ;;
        esac
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
