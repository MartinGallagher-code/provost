#!/bin/bash
## Name: columnar-specs
## Description: Data-driven columnar parser — one spec per tool (detect + column map) instead of a bespoke strategy each
## Version: 1.1
## Priority: 14
## Technique: yes
## Sample: samples/columnar-specs/basic.txt

# A single engine that replaces many near-identical per-tool columnar strategies.
# Each tool is one TAB-separated spec line instead of a ~50-line .sh file:
#
#   name <TAB> detect1;detect2;… <TAB> header_marker <TAB> delim <TAB> absorb <TAB> minreq <TAB> col,col,…
#
#   detect*       — substrings that must ALL appear in the input for this spec
#   header_marker — skip every line up to and INCLUDING the first line containing
#                   this (drops preamble + header/rule row); empty = headerless
#   delim         — "ws" (whitespace tokens) or "pipe" (split on `|`, trim cells)
#   absorb        — 0-based index of the column that soaks up overflow tokens when
#                   a row has more tokens than columns (ws only); -1 = none
#   minreq        — minimum token count for a row to be accepted (lets trailing
#                   columns be optional, e.g. ss `Process`)
#   colN          — output field name, optionally with a transform:
#                     name                 always emit
#                     name@opt             emit only if the cell is non-empty
#                     name@between@L@R     emit the substring between the first L
#                                          and the next R (empty ⇒ skip); e.g.
#                                          ss `users:(("sshd",…))` → `sshd`
#
# The winning strategy name is `columnar-specs` for every tool it handles, but the
# tidy output (melted by tool) is identical to the retired bespokes — verified
# byte-for-byte at migration time.

_COLUMNAR_SPECS=(
  $'zypper-search\t| Name ;| Summary ;| Type\t-+-\tpipe\t-1\t4\tstatus,name,summary,type'
  $'buildah-containers\tCONTAINER ID;BUILDER;CONTAINER NAME\tCONTAINER ID\tws\t3\t4\tid,builder,image_id,image_name@opt,name'
  $'lsmem\tRANGE;REMOVABLE;BLOCK\tRANGE\tws\t-1\t5\trange,size,state,removable,block'
  $'ss-tulnp\tState;Local;Process\tRecv-Q\tws\t5\t5\tstate,recv_q,send_q,local,peer,process@between@users:(("@"\t0'
  $'smartctl-attributes\tATTRIBUTE_NAME;RAW_VALUE;WHEN_FAILED\tATTRIBUTE_NAME\tws\t-1\t10\tid,attribute_name,flag,value,worst,thresh,type,updated,when_failed,raw_value'
)

# Split a spec string into the globals used by detect/extract. Field 7 (total) is
# optional: 1 (default) emits a `total_entries` record, 0 omits it — some bespokes
# emit it, some don't, and migration must match byte-for-byte.
_cs_parse () {
    local IFS=$'\t'; local -a p=()
    read -ra p <<< "$1"
    _CS_NAME="${p[0]}"; _CS_DETECT="${p[1]}"; _CS_HDR="${p[2]}"
    _CS_DELIM="${p[3]}"; _CS_ABSORB="${p[4]}"; _CS_MINREQ="${p[5]}"; _CS_COLS="${p[6]}"
    _CS_TOTAL="${p[7]:-1}"
}

# Does the text match this spec's detect substrings (all present)?
_cs_matches () {
    local text="$1" det="$2" IFS=';' tok
    local -a toks=(); read -ra toks <<< "$det"
    for tok in "${toks[@]}"; do
        [[ -z "$tok" ]] && continue
        [[ "$text" == *"$tok"* ]] || return 1
    done
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local spec
    for spec in "${_COLUMNAR_SPECS[@]}"; do
        _cs_parse "$spec"
        if _cs_matches "$text" "$_CS_DETECT"; then
            _CS_MATCHED="$spec"
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done
    return 1
}

_cs_trim () { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# Apply a column's transform. Sets _CS_OUT to the (possibly transformed) value and
# _CS_SKIP=1 when an @opt/@between column should be dropped. Uses globals (not a
# command-substitution) so the caller sees _CS_SKIP — a subshell would lose it.
_CS_OUT=""; _CS_SKIP=0
_cs_apply () {  # $1=raw value, $2=colspec (name@…)
    local raw="$1" spec="$2"; _CS_SKIP=0; _CS_OUT="$raw"
    [[ "$spec" != *"@"* ]] && return          # plain column: always emit raw
    local IFS='@'; local -a c=(); read -ra c <<< "$spec"
    local xform="${c[1]:-}"
    case "$xform" in
        opt) [[ -z "$raw" ]] && _CS_SKIP=1 ;;
        between)
            local L="${c[2]:-}" R="${c[3]:-}" out=""
            if [[ "$raw" == *"$L"* ]]; then local t="${raw#*"$L"}"; out="${t%%"$R"*}"; fi
            [[ -z "$out" ]] && _CS_SKIP=1
            _CS_OUT="$out" ;;
    esac
}

strategy_extract () {
    local text="$1"
    local spec="${_CS_MATCHED:-}"
    if [[ -z "$spec" ]]; then
        local s
        for s in "${_COLUMNAR_SPECS[@]}"; do
            _cs_parse "$s"; _cs_matches "$text" "$_CS_DETECT" && { spec="$s"; break; }
        done
        [[ -z "$spec" ]] && { echo ""; return 0; }
    fi
    _cs_parse "$spec"
    local -a cols=(); IFS=',' read -ra cols <<< "$_CS_COLS"
    local ncols=${#cols[@]}
    local minreq="${_CS_MINREQ:-$ncols}"

    local result="" entry=0 line past=0
    [[ -z "$_CS_HDR" ]] && past=1
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ $past -eq 0 ]]; then
            [[ "$line" == *"$_CS_HDR"* ]] && past=1
            continue
        fi
        local -a tok=()
        if [[ "$_CS_DELIM" == "pipe" ]]; then
            [[ "$line" == *"|"* ]] || continue
            local IFSbak="$IFS"; IFS='|'; read -ra tok <<< "$line"; IFS="$IFSbak"
            local i; for ((i=0; i<${#tok[@]}; i++)); do tok[$i]="$(_cs_trim "${tok[$i]}")"; done
        else
            read -ra tok <<< "$line"
        fi
        [[ ${#tok[@]} -lt $minreq ]] && continue

        # Assign tokens to columns, folding overflow into the absorb column.
        local -a vals=()
        if [[ "$_CS_DELIM" == "ws" && "$_CS_ABSORB" -ge 0 && ${#tok[@]} -gt $ncols ]]; then
            local extra=$(( ${#tok[@]} - ncols )) i ti=0
            for ((i=0; i<ncols; i++)); do
                if [[ $i -eq $_CS_ABSORB ]]; then
                    local j v="${tok[$ti]}"; ti=$((ti+1))
                    for ((j=0; j<extra; j++)); do v="${v}_${tok[$ti]}"; ti=$((ti+1)); done
                    vals+=("$v")
                else
                    vals+=("${tok[$ti]:-}"); ti=$((ti+1))
                fi
            done
        else
            local i; for ((i=0; i<ncols; i++)); do vals+=("${tok[$i]:-}"); done
        fi

        entry=$((entry + 1))
        local i fname
        for ((i=0; i<ncols; i++)); do
            _cs_apply "${vals[$i]}" "${cols[$i]}"
            [[ "$_CS_SKIP" -eq 1 ]] && continue
            fname="${cols[$i]%%@*}"
            result+="entry${entry}.${fname} ${_CS_OUT}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 && "${_CS_TOTAL:-1}" != "0" ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
