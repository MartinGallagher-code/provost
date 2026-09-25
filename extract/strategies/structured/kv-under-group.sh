#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: kv-under-group
## Description: Grouped kv records — indented key/value runs under repeated group labels (ethtool queues, nvme namespaces, blkid -o full)
## Version: 1.0
## Priority: 10
## Sample: samples/kv-under-group/basic.txt

# The kv-CARRY-DOWN shape grouped-rows explicitly cannot take (its leaves must
# be a table) and pivot-stats cannot either (no header/values pivot): a GROUP
# label line over an INDENTED run of key/value leaves, the same keys repeating
# group after group:
#
#   NIC statistics for enp3s0:
#     Queue 0:
#        rx_packets: 88213
#        tx_packets: 77120
#     Queue 1:
#        rx_packets: 91002
#   ...
#
# One wide row per LEAF group (the group whose kv lines follow directly):
# `name` = its label, one column per key, and the nearest OUTER group
# (nvme's `Controller nvme0 …` over its namespaces, ethtool's NIC title)
# carried down as a `group` column. Leaves take `key: value` (tight or spaced
# colon) and `KEY value` (blkid's indented pairs).
#
# Priority 10 — it must outrank key-value (11), which flattens these into one
# record with colliding keys. What makes that safe is the detection signature:
# >=2 leaf groups with >=2 leaves each AND >=2 leaf KEYS REPEATED across
# different groups. A single-record kv snapshot has no repeated keys; a
# multi-record one without group labels belongs to block-records. Nothing
# else looks like this.

# Leaf-kv shape: sets _KUG_KEY/_KUG_VAL, returns 0/1. Forms: `key: value`,
# `key : value`, `KEY value` (bare label token).
_kug_leaf () {
    local line="$1"
    _KUG_KEY=""; _KUG_VAL=""
    local -a tk=(); { _fr_tok "$line"; tk=("${_FR_TOK[@]}"); }
    [[ ${#tk[@]} -lt 2 ]] && return 1
    local k="${tk[0]}"
    if [[ "$k" == *: && "$k" != : ]]; then
        _KUG_KEY="${k%:}"
        _KUG_VAL="${tk[*]:1}"
    elif [[ "${tk[1]:-}" == ":" ]]; then
        [[ ${#tk[@]} -lt 3 ]] && return 1
        _KUG_KEY="$k"
        _KUG_VAL="${tk[*]:2}"
    elif [[ "$k" =~ ^[A-Z0-9_-]+$ || "$k" =~ ^[a-z0-9_-]+$ ]]; then
        # A colon-less pair's key must be LABEL-shaped — ALL-CAPS (blkid's
        # UUID/TYPE) or lowercase_snake (rx_packets). A Titlecase English word
        # (`Operating System   Ubuntu…`) is the first word of a MULTI-WORD key,
        # which this parser would truncate — not a leaf.
        _KUG_KEY="$k"
        _KUG_VAL="${tk[*]:1}"
    else
        return 1
    fi
    [[ -n "$_KUG_KEY" && -n "$_KUG_VAL" ]] || return 1
    return 0
}

_kug_indent () {
    local l="$1" i=0
    while [[ "${l:$i:1}" == ' ' || "${l:$i:1}" == '	' ]]; do i=$((i + 1)); done
    _KUG_IND=$i
}

# Load $1 into _KUG_LINES/_KUG_INDS/_KUG_BODYS (nonblank only) and classify
# each as G (group), L (leaf) or X in _KUG_KIND. A line is a GROUP when its
# last token ends ':' with 1-4 tokens, when it is a single bare token
# (blkid's `/dev/sda1`), or — lookahead — when it is NOT a leaf, has 1-6
# tokens, and the next line is deeper-indented (nvme's `Controller nvme0
# (PCIe …)` carrier). The group test runs BEFORE the leaf test: `Queue 0:`
# reads as `Queue=0:` to the leaf matcher but IS a group.
_kug_load () {
    local text="$1"
    _KUG_LINES=(); _KUG_INDS=(); _KUG_BODYS=(); _KUG_KIND=()
    local _l
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        _KUG_LINES+=("$_l")
        _kug_indent "$_l"
        _KUG_INDS+=("$_KUG_IND")
        _KUG_BODYS+=("${_l#"${_l%%[![:space:]]*}"}")
    done
    local i n=${#_KUG_LINES[@]}
    for ((i = 0; i < n; i++)); do
        local body="${_KUG_BODYS[$i]}"
        local -a tk=(); { _fr_tok "$body"; tk=("${_FR_TOK[@]}"); }
        local ntk=${#tk[@]}
        local last="${tk[$((ntk - 1))]:-}"
        if [[ $ntk -ge 1 && $ntk -le 4 && "$last" == *: && "$body" =~ [A-Za-z0-9] ]]; then
            _KUG_KIND+=("G"); continue
        fi
        if [[ $ntk -eq 1 && "$body" =~ [A-Za-z0-9] ]]; then
            # a group label must bear an alphanumeric — a `────` separator
            # rule (netlify's site cards) is chrome, not a group
            _KUG_KIND+=("G"); continue
        fi
        # An UNINDENTED line over deeper content is a record carrier (nvme's
        # `Controller nvme0 (PCIe …)`) even though it also parses as a kv leaf
        # — test before the leaf rule, but only at indent 0 so real indented
        # leaves are never stolen.
        if [[ ${_KUG_INDS[$i]} -eq 0 && $ntk -le 6 && $((i + 1)) -lt $n \
              && ${_KUG_INDS[$((i + 1))]} -gt 0 ]]; then
            _KUG_KIND+=("G"); continue
        fi
        if _kug_leaf "$body"; then
            _KUG_KIND+=("L"); continue
        fi
        if [[ $ntk -le 6 && $((i + 1)) -lt $n && ${_KUG_INDS[$((i + 1))]} -gt ${_KUG_INDS[$i]} ]]; then
            _KUG_KIND+=("G"); continue
        fi
        _KUG_KIND+=("X")
    done
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="repeated kv keys under group labels (kv carry-down)"
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # PREFILTER (exact): the size gate below counts NON-BLANK lines (what
    # _kug_load keeps); count them first — stopping at 401 — so an input
    # outside 5..400 lines is declined without classifying every line.
    local _kug_nb=0 _kug_l
    _fr_lines "$text"
    for _kug_l in "${_FR_LINES[@]}"; do
        [[ "${_kug_l}" != *[![:space:]]* ]] && continue
        _kug_nb=$((_kug_nb + 1))
        [[ $_kug_nb -gt 400 ]] && return 1
    done
    [[ $_kug_nb -lt 5 ]] && return 1
    _kug_load "$text"
    local n=${#_KUG_LINES[@]} i
    [[ $n -lt 5 || $n -gt 400 ]] && return 1
    # Not ours, whole-input vetoes:
    #  - a `- ` list marker means YAML (kubectl config view, helm values) —
    #    the yaml parser flattens those losslessly, we would DROP subtrees;
    #  - `{` / `}` block syntax means a CONFIG file (named.conf), not records.
    local braces=0
    for ((i = 0; i < n; i++)); do
        [[ "${_KUG_BODYS[$i]}" == "- "* ]] && return 1
        # YAML anchors/aliases (`defaults: &defaults`, `<<: *defaults`) mark a
        # YAML document even without list items — the yaml parser flattens it
        # losslessly, this model would mangle the merge keys.
        [[ "${_KUG_BODYS[$i]}" =~ (^|[[:space:]])[\&\*][A-Za-z0-9_] ]] && return 1
        [[ "${_KUG_BODYS[$i]}" == *"{" || "${_KUG_BODYS[$i]}" == "}"* ]] && braces=$((braces + 1))
    done
    [[ $braces -ge 2 ]] && return 1
    local groups_ok=0 cur_ind=-1 cur_leaves=0 classified=0 mangled=0 leaves_total=0 dup_in_group=0
    local -A key_groups=() key_seen_this=()
    for ((i = 0; i < n; i++)); do
        case "${_KUG_KIND[$i]}" in
            L)
                if [[ $cur_ind -ge 0 && ${_KUG_INDS[$i]} -gt $cur_ind ]]; then
                    _kug_leaf "${_KUG_BODYS[$i]}"
                    cur_leaves=$((cur_leaves + 1)); classified=$((classified + 1))
                    leaves_total=$((leaves_total + 1))
                    # a value whose 1st/2nd token ends ':' means the REAL key
                    # was multi-word (`API version: 1.43` → key API, val
                    # `version: 1.43`) — we'd truncate every such key
                    local -a _vt=(); { _fr_tok "$_KUG_VAL"; _vt=("${_FR_TOK[@]}"); }
                    [[ "${_vt[0]:-}" == *: || "${_vt[1]:-}" == *: ]] && mangled=$((mangled + 1))
                    if [[ -z "${key_seen_this[$_KUG_KEY]:-}" ]]; then
                        key_seen_this[$_KUG_KEY]=1
                        key_groups[$_KUG_KEY]=$(( ${key_groups[$_KUG_KEY]:-0} + 1 ))
                    else
                        # same key twice INSIDE one group (ifconfig's two RX
                        # lines): these aren't kv keys, a wide row would drop
                        # data
                        dup_in_group=1
                    fi
                else
                    [[ $cur_leaves -ge 2 ]] && groups_ok=$((groups_ok + 1))
                    cur_ind=-1; cur_leaves=0; key_seen_this=()
                fi ;;
            G)
                [[ $cur_leaves -ge 2 ]] && groups_ok=$((groups_ok + 1))
                cur_ind=${_KUG_INDS[$i]}; cur_leaves=0; key_seen_this=()
                classified=$((classified + 1)) ;;
            X)
                [[ $cur_leaves -ge 2 ]] && groups_ok=$((groups_ok + 1))
                cur_ind=-1; cur_leaves=0; key_seen_this=() ;;
        esac
    done
    [[ $cur_leaves -ge 2 ]] && groups_ok=$((groups_ok + 1))

    [[ $groups_ok -ge 2 ]] || return 1
    [[ $dup_in_group -eq 1 ]] && return 1
    # Bare (no-colon) leaves with a uniform >=3-token count are TABLE rows
    # under a group header (lsof's `cwd DIR 8,1 /` under COMMAND=nginx), not
    # kv pairs — that's grouped-rows' shape; a wide kv row would weld cells.
    local bare3=0 bare_tot=0
    for ((i = 0; i < n; i++)); do
        [[ "${_KUG_KIND[$i]}" == "L" ]] || continue
        local -a bt=(); { _fr_tok "${_KUG_BODYS[$i]}"; bt=("${_FR_TOK[@]}"); }
        [[ "${bt[0]}" == *: || "${bt[1]:-}" == ":" ]] && continue
        bare_tot=$((bare_tot + 1))
        [[ ${#bt[@]} -ge 3 ]] && bare3=$((bare3 + 1))
    done
    [[ $bare_tot -ge 3 && $(( bare3 * 100 / bare_tot )) -ge 70 ]] && return 1
    # mangled multi-word keys dominate → not safely parseable by this model
    [[ $leaves_total -gt 0 && $(( mangled * 5 )) -gt $leaves_total ]] && return 1
    # >=2 keys repeated under >=2 distinct groups — THE signature.
    local k rep=0
    for k in "${!key_groups[@]}"; do [[ ${key_groups[$k]} -ge 2 ]] && rep=$((rep + 1)); done
    [[ $rep -ge 2 ]] || return 1
    # the shape must dominate the block
    [[ $(( classified * 100 / n )) -ge 80 ]] || return 1
    _STRATEGY_CONFIDENCE=82
    return 0
}

strategy_extract () {
    local text="$1"
    _kug_load "$text"
    local n=${#_KUG_LINES[@]} i
    local result="" entry=0
    # Group stack: parallel indent/label arrays. A leaf materializes an entry
    # for the TOP group (once), with the nearest ancestor as `group`.
    local -a st_ind=() st_lab=()
    local emitted=0
    for ((i = 0; i < n; i++)); do
        local ind=${_KUG_INDS[$i]} body="${_KUG_BODYS[$i]}"
        case "${_KUG_KIND[$i]}" in
            G)
                local label="${body%:}"
                # pop groups at same-or-deeper indent
                while [[ ${#st_ind[@]} -gt 0 && ${st_ind[$(( ${#st_ind[@]} - 1 ))]} -ge $ind ]]; do
                    unset "st_ind[$(( ${#st_ind[@]} - 1 ))]"; st_ind=("${st_ind[@]}")
                    unset "st_lab[$(( ${#st_lab[@]} - 1 ))]"; st_lab=("${st_lab[@]}")
                done
                st_ind+=("$ind"); st_lab+=("$label")
                emitted=0 ;;
            L)
                if [[ ${#st_ind[@]} -gt 0 && $ind -gt ${st_ind[$(( ${#st_ind[@]} - 1 ))]} ]]; then
                    _kug_leaf "$body"
                    if [[ $emitted -eq 0 ]]; then
                        entry=$((entry + 1)); emitted=1
                        result+="entry${entry}.name ${st_lab[$(( ${#st_lab[@]} - 1 ))]}"$'\n'
                        if [[ ${#st_lab[@]} -ge 2 ]]; then
                            result+="entry${entry}.group ${st_lab[$(( ${#st_lab[@]} - 2 ))]}"$'\n'
                        fi
                    fi
                    local k="${_KUG_KEY//./_}"; k="${k// /_}"
                    result+="entry${entry}.${k} ${_KUG_VAL}"$'\n'
                fi ;;
            X)
                st_ind=(); st_lab=(); emitted=0 ;;
        esac
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
