#!/bin/bash
## Name: columnar-specs
## Description: Data-driven columnar parser — one spec per tool (detect + column map) instead of a bespoke strategy each
## Version: 1.1
## Priority: 14
## Technique: yes
## Sample: samples/columnar-specs/basic.txt

# A single engine that replaces many near-identical per-tool columnar strategies.
# Full reference (spec format, transforms, how to add a tool / a transform):
#   docs/columnar-specs-engine.md   — keep it current when you extend the engine.
# Each tool is one TAB-separated spec line instead of a ~50-line .sh file:
#
#   name <TAB> detect1;detect2;… <TAB> header_marker <TAB> delim <TAB> absorb <TAB> minreq <TAB> col,col,…
#
#   detect*       — substrings that must ALL appear in the input for this spec
#   header_marker — skip every line up to and INCLUDING the first line containing
#                   this (drops preamble + header/rule row); `-` = headerless.
#                   (Must not be empty — `read` collapses consecutive TAB fields.)
#   delim         — "ws" (whitespace tokens) or "pipe" (split on `|`, trim cells)
#   absorb        — 0-based index of the column that soaks up overflow tokens when
#                   a row has more tokens than columns (ws only); -1 = none
#   minreq        — minimum token count for a row to be accepted (lets trailing
#                   columns be optional, e.g. ss `Process`)
#   detect tokens may be plain substrings (must appear anywhere) or `re:PATTERN`
#     (at least one line must match the bash regex PATTERN) — the latter gives the
#     precision a substring can't, e.g. mount's `<dev> on <mp> type <fs>` shape.
#   colN          — output field name, optionally with a transform:
#                     name                 always emit
#                     ~name                structural separator token (e.g. mount
#                                          `on`/`type`): consume a token, emit nothing
#                     name@opt             emit only if the cell is non-empty
#                     name@unwrap          strip one layer of surrounding ()/[]/{}/""
#                                          e.g. mount `(rw,relatime)` → `rw,relatime`
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
  $'mount\tre:^[^[:space:]]+ on .* type \t-\tws\t-1\t6\tdevice,~on,mount_point,~type,fstype,options@unwrap'
  $'iostat-d\ttps;kB_read/s\tDevice\tws\t-1\t6\tdevice,tps,kb_read_s,kb_wrtn_s,kb_read,kb_wrtn'
  $'rabbitmqctl-list-queues\tListing queues for vhost\tListing queues for vhost\tws\t-1\t3\tname,messages,consumers'
  $'goose-status\tApplied At;Migration\tApplied At\tws\t0\t2\tapplied_at,migration'
  $'ipmitool-sensor\tre:[|] *(ok|na|nc|cr) *[|]\t-\tpipe\t-1\t10\tname,reading,unit,status,lower_nr,lower_crit,lower_noncrit,upper_noncrit,upper_crit,upper_nr'
  $'dpkg-get-selections\tre:[[:space:]](install|deinstall|hold|purge)$\t-\tws\t-1\t2\tpackage,status'
  $'gsutil-ls-l\tgs://\t-\tws\t-1\t3\tsize,timestamp,url\t1\tgs://'
  $'grafana-cli-plugins\tinstalled plugins\t-\tws\t-1\t3\tid,~at,version\t1\t @ [0-9]'
  $'bq-ls\ttableId;Type\ttableId\tws\t-1\t2\ttableid,type\t1\t[[:alpha:]]'
  $'arp-scan\tarp-scan\t-\tws\t-1\t3\tip,mac,vendor@rest\t1\t^[0-9]+[.][0-9]+[.][0-9]+[.][0-9]+'
  $'rustc-cfg\ttarget_arch=;target_os=\t-\tws\t-1\t1\tc1@line'
  $'apache2ctl-modules\tLoaded Modules:\tLoaded Modules:\tws\t-1\t1\tc1@line'
  $'dub-list\tknown to dub\tknown to dub\tws\t-1\t1\tc1@line'
  $'lstopo-no-graphics\tMachine (;NUMANode\t-\tws\t-1\t1\tc1@line'
  $'lshw-network\t*-network;logical name:\t-\tws\t-1\t1\tc1@line'
  $'route-6\tKernel IPv6 routing\tDestination\tws\t-1\t7\tdestination,next_hop,flag,met,ref,use,iface'
  $'snap-connections\tPlug;Slot;Notes\tInterface\tws\t-1\t4\tinterface,plug,slot,notes'
  $'networkctl-lldp\tCHASSIS ID;PORT DESCRIPTION\tLINK\tws\t5\t6\tlink,chassis_id,system_name,caps,port_id,port_description\t1\t^eth[0-9]'
  $'memcached-stats\tre:^STAT \t-\tws\t-1\t3\t~stat,key,value'
  $'es-cat-allocation\tdisk.indices;disk.percent\tshards\tws\t-1\t9\tshards,disk_indices,disk_used,disk_avail,disk_total,disk_percent,host,ip,node'
  $'bundle-list\tGems included by the bundle\tGems included by the bundle\tws\t-1\t3\t~star,name,version@unwrap\t1\t^ *[*]'
  $'nethogs\tre:PID +USER +PROGRAM\tRECEIVED\tws\t-1\t7\tpid,user,program,dev,sent,received,unit'
  $'slabtop\tOBJ/SLAB\tNAME\tws\t-1\t8\tobjs,active,use,obj_size,slabs,obj_per_slab,cache_size,name'
  $'objdump-headers\tfile format\tAlgn\tws\t-1\t7\tidx,name,size,vma,lma,file_off,algn\t1\t^ *[0-9]'
  $'iptables-save\tre:^-A \t-\tws\t-1\t3\t~a,chain,rule@rest\t1\t^-A '
  $'ldconfig-p\tre: => \tlibs found\tws\t-1\t4\tsoname,info@unwrap,~arrow,path\t1\t => '
  $'perf-top\tre:^Samples:\tSymbol\tws\t-1\t4\toverhead,shared_object,~marker,symbol@rest\t1\t%'
  $'turbostat\tBzy_MHz\t-\tws\t-1\t10\tCore,CPU,Avg_MHz,Busy_pct,Bzy_MHz,TSC_MHz,IRQ,PkgTmp,PkgWatt,RAMWatt\t1\t^[0-9]'
  $'traceroute\ttraceroute to\thops max\tws\t-1\t9\thop,host,~ip,rtt1,~m1,rtt2,~m2,rtt3,~m3'
  $'crontab\tdom mon dow\t-\tws\t-1\t6\tminute,hour,day_of_month,month,day_of_week,command@rest\t0\t^[^#]\tjob'
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
    # Field 9 (optional): a per-row ACCEPT regex. When set, a row is processed
    # only if its raw line matches — the engine's per-row structural guard, for
    # outputs with footer/note lines that survive the minreq filter (e.g.
    # gsutil `TOTAL:`, grafana trailing note). Empty ⇒ every row past the header.
    _CS_ROWRE="${p[8]:-}"
    # Field 10 (optional): record-name prefix (default "entry"). Some bespokes
    # label records `jobN`/`commitN`/… instead of `entryN`; match byte-for-byte.
    _CS_PREFIX="${p[9]:-entry}"
}

# Does the text match this spec's detect tokens (all present)? A plain token is a
# substring anywhere; a `re:PATTERN` token requires >=1 line to match the regex.
_cs_matches () {
    local text="$1" det="$2" IFS=';' tok
    local -a toks=(); read -ra toks <<< "$det"
    for tok in "${toks[@]}"; do
        [[ -z "$tok" ]] && continue
        if [[ "$tok" == re:* ]]; then
            local pat="${tok#re:}" _l hit=0
            while IFS= read -r _l; do [[ "$_l" =~ $pat ]] && { hit=1; break; }; done <<< "$text"
            [[ $hit -eq 1 ]] || return 1
        else
            [[ "$text" == *"$tok"* ]] || return 1
        fi
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
        unwrap)
            case "$raw" in
                "("*")") _CS_OUT="${raw#(}"; _CS_OUT="${_CS_OUT%)}" ;;
                "["*"]") _CS_OUT="${raw#[}"; _CS_OUT="${_CS_OUT%]}" ;;
                "{"*"}") _CS_OUT="${raw#\{}"; _CS_OUT="${_CS_OUT%\}}" ;;
                '"'*'"') _CS_OUT="${raw#\"}"; _CS_OUT="${_CS_OUT%\"}" ;;
            esac ;;
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
    # index of the terminal @rest column (soaks remaining tokens, space-joined), or -1
    local rest_idx=-1 _ci
    for ((_ci=0; _ci<ncols; _ci++)); do [[ "${cols[$_ci]}" == *"@rest" ]] && rest_idx=$_ci; done
    # @line: a sole column capturing the whole TRIMMED line verbatim (no tokenizing).
    # For single-column list outputs (module lists, cfg dumps, cgroup trees).
    local line_mode=0
    [[ $ncols -eq 1 && "${cols[0]}" == *"@line" ]] && line_mode=1

    local result="" entry=0 line past=0
    [[ -z "$_CS_HDR" || "$_CS_HDR" == "-" ]] && past=1
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ $past -eq 0 ]]; then
            [[ "$line" == *"$_CS_HDR"* ]] && past=1
            continue
        fi
        # per-row accept guard (field 9): skip rows whose raw line doesn't match
        [[ -n "$_CS_ROWRE" && ! "$line" =~ $_CS_ROWRE ]] && continue
        # @line mode: emit the whole trimmed line as the sole column (no tokenizing)
        if [[ $line_mode -eq 1 ]]; then
            entry=$((entry + 1))
            result+="${_CS_PREFIX}${entry}.${cols[0]%%@*} $(_cs_trim "$line")"$'\n'
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

        # Assign tokens to columns.
        local -a vals=()
        if [[ "$_CS_DELIM" == "ws" && $rest_idx -ge 0 ]]; then
            # @rest column: takes every remaining token from its slot, joined with
            # single spaces (verbatim internal spacing, unlike absorb's `_`). It is
            # terminal — no columns follow it.
            local i; for ((i=0; i<rest_idx; i++)); do vals+=("${tok[$i]:-}"); done
            local r="${tok[$rest_idx]:-}" k
            for ((k=rest_idx+1; k<${#tok[@]}; k++)); do r="$r ${tok[$k]}"; done
            vals+=("$r")
        elif [[ "$_CS_DELIM" == "ws" && "$_CS_ABSORB" -ge 0 && ${#tok[@]} -gt $ncols ]]; then
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
            # ~name = structural separator: it consumed a token slot (keeping later
            # columns aligned) but is never emitted.
            [[ "${cols[$i]}" == "~"* ]] && continue
            _cs_apply "${vals[$i]}" "${cols[$i]}"
            [[ "$_CS_SKIP" -eq 1 ]] && continue
            fname="${cols[$i]%%@*}"
            result+="${_CS_PREFIX}${entry}.${fname} ${_CS_OUT}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 && "${_CS_TOTAL:-1}" != "0" ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
