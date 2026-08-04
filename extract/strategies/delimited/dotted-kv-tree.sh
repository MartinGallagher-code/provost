#!/bin/bash
## Name: dotted-kv-tree
## Description: cgget/cgroup dotted `key: value` lines with stat sub-blocks and packed pair values -> key/subkey/value rows
## Version: 1.0
## Priority: 31
## Sample: samples/dotted-kv-tree/basic.txt

# cgget's cgroup dumps are dotted keys in three flavours:
#
#   cpu.max: max 100000                  <- flat value
#   cpu.stat:                            <- bare header over INDENTED members
#   	usage_usec 8821004000
#   	user_usec 4102839000
#   memory.stat: anon 512004096 file 150728704 kernel 8421376
#                                        <- value is PACKED name/number pairs
#   cpu.pressure: some avg10=0.00 avg60=0.00 total=1204882
#                                        <- value is k=v pairs after a qualifier
#   mysql.service:                       <- bare header over UNINDENTED kv
#                                           lines: a group, carried as a column
#
# The reviewer spelled the tidy shape out on cgget-cpu: "column A should only
# hold cpu.max, cpu.weight, cpu.stat; B has nothing for cpu.max/cpu.weight but
# usage_usec etc for the cpu.stat sub-entries; C is the values" — and on cgget:
# "the multiple word values are really mostly key/values." So:
#
#   key         subkey       value
#   cpu.max                  max 100000
#   cpu.stat    usage_usec   8821004000
#   memory.stat anon         512004096
#   cpu.pressure some avg10  0.00
#
# A bare dotted header whose followers are indented plain `sub value` lines is
# a STAT BLOCK: the header carries down as `key`, each member's first token is
# the `subkey`. A bare dotted header whose followers are NOT indented
# (mysql.service:) is a GROUP: carried as a `group` column on every row below
# it. Packed values decompose: an alternating `name NUM name NUM …` run (>=2
# pairs) or a run of `k=v` tokens (optionally after one bare qualifier word)
# becomes one row per pair. Everything is entry-prefixed — keys repeat.
#
# Containment: EVERY key (kv or bare header) must be dotted (`a.b` — the
# cgroup controller signature) and space-free, and every line must classify.

# Classify -> _DKT_KIND (K kv | H bare header | M indented member | X reject)
# K: _DKT_KEY/_DKT_VAL;  H: _DKT_KEY;  M: _DKT_SUB/_DKT_VAL.
_dkt_classify () {
    local l="$1"
    _DKT_KIND=X
    [[ -z "${l//[[:space:]]/}" ]] && { _DKT_KIND=-; return; }
    if [[ "$l" == [!$' \t']* ]]; then
        # Unindented: needs `dotted.key:` with optional value. The key must be
        # the cgroup CONTROLLER shape — lowercase alpha-led dot-separated
        # segments (`cpu.max`, `memory.swap.current`, `mysql.service`). That
        # charset is the containment: `src/main.rs:12` (rg counts, ruff, any
        # path) carries `/`; `127.0.0.1:2379` (etcdctl) has digit-led
        # segments; `GENERAL.DEVICE` (nmcli) and `README.md` (file) are
        # uppercase; `[ro.product.model]` (getprop) is bracketed. All reject.
        local k="${l%%:*}"
        [[ "$k" == "$l" ]] && return                      # no colon
        [[ "$k" =~ ^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$ ]] || return
        local v="${l#*:}"
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        # A value opening with a `NN:NN` coordinate is a linter's file:row:col
        # (`deploy.py:12:1: E402 …` — ruff, flake8), not a cgroup value.
        [[ "$v" =~ ^[0-9]+:[0-9]+ ]] && return
        _DKT_KEY="$k"
        if [[ -z "$v" ]]; then _DKT_KIND=H; else _DKT_VAL="$v"; _DKT_KIND=K; fi
        return
    fi
    # Indented: `sub value…`, no colon pair (stat members are bare pairs).
    local b="${l#"${l%%[![:space:]]*}"}"
    b="${b%"${b##*[![:space:]]}"}"
    [[ "$b" == *": "* ]] && return
    [[ "$b" == *" "* ]] || return
    _DKT_SUB="${b%% *}"
    _DKT_VAL="${b#* }"
    _DKT_KIND=M
}

# Decompose a flat value into subkey/value pairs -> _DKT_PK[] / _DKT_PV[].
# Returns 1 when the value does not decompose (stays whole).
_dkt_pairs () {
    local v="$1"
    _DKT_PK=(); _DKT_PV=()
    local -a tok=(); read -ra tok <<< "$v"
    local n=${#tok[@]} i
    # k=v run, optionally after ONE bare qualifier word (pressure's `some`).
    local eq=0 qual="" first=0
    for ((i = 0; i < n; i++)); do
        [[ "${tok[$i]}" == *=* ]] && eq=$((eq + 1))
    done
    if [[ $eq -ge 2 && ( $eq -eq $n || ( $eq -eq $((n - 1)) && "${tok[0]}" != *=* ) ) ]]; then
        [[ "${tok[0]}" != *=* ]] && { qual="${tok[0]} "; first=1; }
        for ((i = first; i < n; i++)); do
            _DKT_PK+=("${qual}${tok[$i]%%=*}")
            _DKT_PV+=("${tok[$i]#*=}")
        done
        return 0
    fi
    # Alternating `name NUM name NUM …` run, >=2 pairs.
    if [[ $n -ge 4 && $((n % 2)) -eq 0 ]]; then
        local ok=1
        for ((i = 0; i < n; i += 2)); do
            [[ "${tok[$i]}" =~ ^[A-Za-z_][A-Za-z0-9_.]*$ ]] || { ok=0; break; }
            [[ "${tok[$((i+1))]}" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || { ok=0; break; }
        done
        if [[ $ok -eq 1 ]]; then
            for ((i = 0; i < n; i += 2)); do
                _DKT_PK+=("${tok[$i]}")
                _DKT_PV+=("${tok[$((i+1))]}")
            done
            return 0
        fi
    fi
    return 1
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line kv=0 hdr=0 mem=0 last=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        _dkt_classify "$line"
        case "$_DKT_KIND" in
            -) ;;
            K) kv=$((kv + 1)); last=K ;;
            H) hdr=$((hdr + 1)); last=H ;;
            M)
                # A member needs a header (or another member) directly above.
                [[ "$last" == H || "$last" == M ]] || return 1
                mem=$((mem + 1)); last=M ;;
            X) return 1 ;;
        esac
    done <<< "$text"
    # The dotted-kv signature: >=2 dotted kv lines, or a stat block.
    [[ $((kv + hdr)) -ge 2 && $((kv + mem)) -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=82
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 group="" stat="" prev=""

    # Pass 1: which bare headers open STAT blocks (indented member follows)?
    # The rest are GROUP headers. Track per-header kind by line order.
    local -a kinds=()
    local i=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        _dkt_classify "$line"
        kinds[$i]="$_DKT_KIND"
        i=$((i + 1))
    done <<< "$text"
    local total=$i

    i=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        _dkt_classify "$line"
        case "$_DKT_KIND" in
            K)
                stat=""
                entry=$((entry + 1))
                [[ -n "$group" ]] && result+="entry${entry}.group ${group}"$'\n'
                result+="entry${entry}.key ${_DKT_KEY}"$'\n'
                if _dkt_pairs "$_DKT_VAL"; then
                    # First pair rides the entry just opened; the rest open
                    # their own entries with the same key.
                    local p
                    for p in "${!_DKT_PK[@]}"; do
                        if [[ $p -gt 0 ]]; then
                            entry=$((entry + 1))
                            [[ -n "$group" ]] && result+="entry${entry}.group ${group}"$'\n'
                            result+="entry${entry}.key ${_DKT_KEY}"$'\n'
                        fi
                        result+="entry${entry}.subkey ${_DKT_PK[$p]}"$'\n'
                        result+="entry${entry}.value ${_DKT_PV[$p]}"$'\n'
                    done
                else
                    result+="entry${entry}.value ${_DKT_VAL}"$'\n'
                fi
                ;;
            H)
                # STAT header when the NEXT classified line is a member;
                # otherwise a group header.
                local j=$((i + 1)) nk="-"
                while [[ $j -lt $total ]]; do
                    nk="${kinds[$j]}"
                    [[ "$nk" != "-" ]] && break
                    j=$((j + 1))
                done
                if [[ "$nk" == M ]]; then stat="$_DKT_KEY"; else group="$_DKT_KEY"; stat=""; fi
                ;;
            M)
                [[ -n "$stat" ]] || { i=$((i + 1)); continue; }
                entry=$((entry + 1))
                [[ -n "$group" ]] && result+="entry${entry}.group ${group}"$'\n'
                result+="entry${entry}.key ${stat}"$'\n'
                result+="entry${entry}.subkey ${_DKT_SUB}"$'\n'
                result+="entry${entry}.value ${_DKT_VAL}"$'\n'
                ;;
        esac
        i=$((i + 1))
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
