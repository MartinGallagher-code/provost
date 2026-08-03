#!/bin/bash
## Name: indented-colon-groups
## Description: `header:` lines over indented members (cargo install/machete, hwinfo --short) -> group/value rows
## Version: 1.1
## Priority: 35
## Sample: samples/indented-colon-groups/basic.txt

# Some tools print an unindented header ending in a colon, then the items that
# belong to it indented beneath, one bare token per line:
#
#   cargo-audit v0.20.0:
#       cargo-audit
#   ripgrep v14.1.0:
#       rg
#
# A flat line list (text-lines / line-records) loses the header->item grouping
# and leaves each header stranded in its own row. The tidy shape carries the
# header down: one row per member, `group` + `value`.
#
# cargo-machete names the group as `crate -- /path/Cargo.toml:`. When EVERY
# header carries that ` -- ` split the group becomes two columns, `name` and
# `path`, so the crate and its manifest are addressable separately -- exactly
# what a reviewer asked for (crate, path, and one dependency per row).
#
# Kept off config / YAML / key:value output by two gates: members carry no
# `key: value` colon pair, and the header's own text (before the trailing
# colon) holds no `key: value` pair either. Preamble and footer lines are
# tolerated only at the very top and bottom -- any unclassifiable line in
# the middle rejects the block. (v1.0 also required members to be a single
# token; hwinfo --short's multi-token members showed that was the first
# shape we met, not the discriminator -- the colon gate is what matters.)

# Leading whitespace width of $1 -> _ICG_IND
_icg_indent () {
    local l="$1" i=0
    while [[ "${l:$i:1}" == ' ' || "${l:$i:1}" == $'\t' ]]; do i=$((i + 1)); done
    _ICG_IND=$i
}

# Classify a raw line -> _ICG_KIND (G group | M member | N noise), _ICG_BODY.
_icg_classify () {
    local l="$1"
    _ICG_KIND=N; _ICG_BODY=""
    [[ -z "${l//[[:space:]]/}" ]] && return
    _icg_indent "$l"
    local body="${l#"${l%%[![:space:]]*}"}"    # lstrip
    body="${body%"${body##*[![:space:]]}"}"    # rstrip
    if [[ $_ICG_IND -eq 0 ]]; then
        # A group header: unindented, ends in ':', and the text before that
        # colon holds no `key: value` pair (so YAML/config mappings stay out).
        if [[ "$body" == *: && "${body%:}" != *": "* ]]; then
            _ICG_BODY="${body%:}"; _ICG_KIND=G
        fi
        return
    fi
    # A member: indented, no `key: value` colon pair. Members may be
    # MULTI-token — hwinfo --short's `/dev/input/event3    AT Translated Set 2
    # keyboard` is one member, its 2+-space run being column alignment inside
    # the member, so runs collapse to a single space in the value. The colon
    # gate is what keeps YAML / config mappings out; single-token-ness never
    # was the discriminator, it was just the first shape we met.
    [[ "$body" == *": "* ]] && return
    while [[ "$body" == *"  "* ]]; do body="${body//  / }"; done
    _ICG_BODY="$body"; _ICG_KIND=M
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line groups=0 members=0
    local order=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _icg_classify "$line"
        case "$_ICG_KIND" in
            G) order+="G"; groups=$((groups + 1)) ;;
            M) order+="M"; members=$((members + 1)) ;;
            N) order+="N" ;;
        esac
    done <<< "$text"
    # Need real grouping: >=2 headers and at least one member each.
    [[ $groups -ge 2 && $members -ge $groups ]] || return 1
    # Multi-token members brought two shapes this strategy must NOT eat:
    #   * ` = ` members are an assignment block under section headers
    #     (python -m sysconfig, qperf, hdparm) — kv parsers' territory;
    #   * same-width members are an embedded TABLE's rows (yugabyte's
    #     `UUID Host Port Role State`, pulumi's Type/Name/Plan) — welding a
    #     row into one value cell loses its columns. Rejected when >=3
    #     members share one token count >=3 covering at least half of all
    #     members. Exempt: an all-` - `-pair block (fdbcli status), which
    #     LOOKS same-width only because the dashes align — it is a kv list
    #     and extract splits it properly.
    local _m_eq=0 _m_dash=0 _m_counts=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        _icg_classify "$line"
        [[ "$_ICG_KIND" == M ]] || continue
        [[ "$_ICG_BODY" == *" = "* ]] && _m_eq=1
        [[ "$_ICG_BODY" == *" - "* ]] && _m_dash=$((_m_dash + 1))
        local -a _mt=(); read -ra _mt <<< "$_ICG_BODY"
        _m_counts+="${#_mt[@]} "
    done <<< "$text"
    [[ $_m_eq -eq 1 ]] && return 1
    if [[ $_m_dash -lt $members ]]; then
        local _c _best=0
        for _c in $_m_counts; do
            [[ $_c -lt 3 ]] && continue
            local _n=0 _c2
            for _c2 in $_m_counts; do [[ "$_c2" == "$_c" ]] && _n=$((_n + 1)); done
            [[ $_n -gt $_best ]] && _best=$_n
        done
        [[ $_best -ge 3 && $(( _best * 2 )) -ge $members ]] && return 1
    fi
    # Noise (preamble/footer) only at the very ends -- never between groups.
    local core="${order#"${order%%[!N]*}"}"   # strip leading N run
    core="${core%"${core##*[!N]}"}"           # strip trailing N run
    [[ "$core" == *N* ]] && return 1
    # Every group must be followed by a member somewhere before the next group.
    [[ "$core" == G* ]] || return 1
    case "$core" in *GG*) return 1 ;; esac     # a header with no members of its own
    _STRATEGY_CONFIDENCE=85
    return 0
}

strategy_extract () {
    local text="$1"
    local line

    # Two-column group name only when EVERY member-bearing header carries the
    # ` -- ` split; otherwise a single `group` column, so a file never mixes the
    # two shapes. Headers with no members (a trailing footer line that happens
    # to end in a colon) do not count — they emit nothing and must not veto the
    # split for the real groups above them.
    local split=1 saw_group=0 cur_group="" cur_split=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        _icg_classify "$line"
        case "$_ICG_KIND" in
            G)
                cur_group="$_ICG_BODY"
                [[ "$cur_group" == *" -- "* ]] && cur_split=1 || cur_split=0
                ;;
            M)
                [[ -n "$cur_group" ]] || continue
                saw_group=1
                [[ $cur_split -eq 1 ]] || split=0
                ;;
        esac
    done <<< "$text"
    [[ $saw_group -eq 1 ]] || split=0

    # An all-` - `-pair member block (fdbcli status: `Redundancy mode - triple`)
    # is a kv list whose dashes merely align; split each member into key |
    # value instead of welding the pair into one cell. Only when the header
    # ` -- ` split is off — the two shapes have not co-occurred.
    local dash=0
    if [[ $split -eq 0 ]]; then
        local _dm=0 _mm=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            _icg_classify "$line"
            [[ "$_ICG_KIND" == M ]] || continue
            _mm=$((_mm + 1))
            [[ "$_ICG_BODY" == *" - "* ]] && _dm=$((_dm + 1))
        done <<< "$text"
        [[ $_mm -gt 0 && $_dm -eq $_mm ]] && dash=1
    fi

    local result="" entry=0 gname="" gpath="" group=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        _icg_classify "$line"
        case "$_ICG_KIND" in
            G)
                group="$_ICG_BODY"
                if [[ $split -eq 1 ]]; then
                    gname="${group%% -- *}"
                    gpath="${group#* -- }"
                fi
                ;;
            M)
                [[ -n "$group" ]] || continue
                entry=$((entry + 1))
                if [[ $split -eq 1 ]]; then
                    result+="entry${entry}.name ${gname}"$'\n'
                    result+="entry${entry}.path ${gpath}"$'\n'
                else
                    result+="entry${entry}.group ${group}"$'\n'
                fi
                if [[ $dash -eq 1 ]]; then
                    local _mk="${_ICG_BODY%% - *}" _mv="${_ICG_BODY#* - }"
                    result+="entry${entry}.key ${_mk}"$'\n'
                    result+="entry${entry}.value ${_mv}"$'\n'
                else
                    result+="entry${entry}.value ${_ICG_BODY}"$'\n'
                fi
                ;;
        esac
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
