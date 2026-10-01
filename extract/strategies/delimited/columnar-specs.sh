#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: columnar-specs
## Description: Data-driven columnar parser — one spec per tool (detect + column map) instead of a bespoke strategy each
## Version: 1.1
## Priority: 14
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
# On a match the engine REPORTS the matched tool name (via `_STRATEGY_REPORT_NAME`,
# set in `strategy_detect`), not "columnar-specs" — so `provost` names the dataset
# per-tool (mount -> dataset `mount`, not `columnar-specs`) and different tools
# don't collide into one dataset. The tidy output (melted by tool) is identical to
# the retired bespokes — verified byte-for-byte at migration time.

_COLUMNAR_SPECS=(
  $'zypper-search\t| Name ;| Summary ;| Type\t-+-\tpipe\t-1\t4\tstatus,name,summary,type'
  $'buildah-containers\tCONTAINER ID;BUILDER;CONTAINER NAME\tCONTAINER ID\tws\t3\t4\tid,builder,image_id,image_name@opt,name'
  $'lsmem\tRANGE;REMOVABLE;BLOCK\tRANGE\tws\t-1\t5\trange,size,state,removable,block'
  $'ss-tulnp\tState;Local;Process\tRecv-Q\tws\t5\t5\tstate,recv_q,send_q,local,peer,process@between@users:(("@"\t0'
  $'smartctl-attributes\tATTRIBUTE_NAME;RAW_VALUE;WHEN_FAILED\tATTRIBUTE_NAME\tws\t-1\t10\tid,attribute_name,flag,value,worst,thresh,type,updated,when_failed,raw_value'
  # `ps -ef f` / `ps ef --forest`: the tree-drawing `\_` prefixes make CMD a
  # multi-token cell, which pushed the generic parser into a 6-segment split
  # that welded C/STIME/TTY into one column. The header fixes 8 columns; CMD
  # absorbs the tree.
  $'ps-forest\tre:^UID +PID +PPID +C STIME TTY\tC STIME TTY\tws\t7\t8\tuid,pid,ppid,c,stime,tty,stat,time,cmd@rest'
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
  $'apache2ctl-modules\tLoaded Modules:\tLoaded Modules:\tws\t-1\t2\tmodule,type@unwrap'
  $'apk-list\tre:\\{[^}]+\\} \\([^)]+\\)\t-\tws\t3\t5\tpackage,arch,origin@unwrap,license@unwrap,status@unwrap'
  $'dub-list\tknown to dub\tknown to dub\tws\t-1\t1\tA@line'
  $'lstopo-no-graphics\tMachine (;NUMANode\t-\tws\t-1\t1\tA@line'
  $'lshw-network\t*-network;logical name:\t-\tws\t-1\t1\tA@line'
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
  $'traceroute\ttraceroute to\thops max\tws\t-1\t4\thop,host,~ip,rtt1@opt,~m1,rtt2@opt,~m2,rtt3@opt,~m3'
  $'git-remote\t(fetch);(push)\t-\tws\t-1\t3\tremote,url,direction@unwrap'
  $'w-sessions\tLOGIN@;JCPU;PCPU;WHAT\tTTY\tws\t-1\t8\tuser,tty,from,login,idle,jcpu,pcpu,what@rest'
  $'dpkg-list\tDesired=Unknown\t+++-\tws\t-1\t5\tstatus,name,version,arch,description@rest'
  $'tar-listing\tre:^[-dlbcps][-rwxsStT]{9} +[^ ]+/[^ ]+ +[0-9]+ +[0-9]{4}-[0-9]{2}-[0-9]{2} \t-\tws\t-1\t6\tpermissions,owner,size,date,time,path@rest'
  $'beegfs\tBeeGFS Storage Targets;TargetID\t=========\tws\t-1\t5\ttarget_id,~node_id,state,capacity,free_space\t0\t^[0-9]\ttarget'
)

# Split a spec string into the globals used by detect/extract. Field 7 (total) is
# optional: 1 (default) emits a `total_entries` record, 0 omits it — some bespokes
# emit it, some don't, and migration must match byte-for-byte.
_cs_parse () {
    local IFS=$'\t'; local -a p=()
    { _fr_tok "$1"; p=("${_FR_TOK[@]}"); }
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

# A ws-delim spec with a FIXED column layout (no `absorb` overflow sink and no
# terminal `@rest` column) can only faithfully map a row whose token count is at
# most its column count — any extra tokens are silently DROPPED, and worse, when
# the real table is WIDER than the spec, its first `ncols` tokens get mapped onto
# the wrong names (turbostat -q's 20-column output mis-labelled by the 10-column
# `turbostat` spec: SMI->PkgTmp, POLL->PkgWatt, …, 10 columns lost). Since no
# fixed-layout spec can legitimately rely on that drop (a genuinely multi-token
# trailing column would already need @rest/absorb), a spec whose data rows carry
# MORE tokens than it has columns is being misapplied — decline so a generic
# parser (tsv / aligned-columns) can take the full width. Returns 0 (overflow →
# decline) only for ws specs with no absorb and no @rest; every other spec shape
# returns 1 (no objection). Uses the already-parsed _CS_* globals.
_cs_row_overflow () {
    local text="$1"
    [[ "$_CS_DELIM" == "ws" ]] || return 1
    [[ "${_CS_ABSORB:--1}" -ge 0 ]] && return 1
    local -a cols=(); { IFS=',' _fr_tok "$_CS_COLS"; cols=("${_FR_TOK[@]}"); }
    local ncols=${#cols[@]} _ci
    [[ $ncols -le 1 ]] && return 1                 # @line / single-col: never overflows
    for ((_ci=0; _ci<ncols; _ci++)); do [[ "${cols[$_ci]}" == *"@rest" ]] && return 1; done
    local _l past=0 wide=0 seen=0
    [[ -z "$_CS_HDR" || "$_CS_HDR" == "-" ]] && past=1
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        if [[ $past -eq 0 ]]; then [[ "$_l" == *"$_CS_HDR"* ]] && past=1; continue; fi
        [[ -n "$_CS_ROWRE" && ! "$_l" =~ $_CS_ROWRE ]] && continue
        local -a _tk=(); { _fr_tok "$_l"; _tk=("${_FR_TOK[@]}"); }
        [[ ${#_tk[@]} -lt "${_CS_MINREQ:-$ncols}" ]] && continue
        seen=$((seen + 1))
        [[ ${#_tk[@]} -gt $ncols ]] && wide=$((wide + 1))
    done
    # Decline only when the OVERWHELMING majority of accepted rows are wider than
    # the layout — a lone ragged row shouldn't lose the spec its normal input.
    [[ $seen -ge 2 && $((wide * 100 / seen)) -ge $(( 80 + ${_FR_SLACK:-0} )) ]]
}

# Does the text match this spec's detect tokens (all present)? A plain token is a
# substring anywhere; a `re:PATTERN` token requires >=1 line to match the regex.
_cs_matches () {
    local text="$1" det="$2" IFS=';' tok
    local -a toks=(); { _fr_tok "$det"; toks=("${_FR_TOK[@]}"); }
    for tok in "${toks[@]}"; do
        [[ -z "$tok" ]] && continue
        if [[ "$tok" == re:* ]]; then
            local pat="${tok#re:}" _l hit=0
            # PREFILTER (exact): a line matching PAT is a substring of the text,
            # so the text matches PAT with its line anchors dropped (in a
            # whole-text match `.`/`[^…]` may also span lines — only ever MORE
            # matches). Applied only when the pattern's sole anchors are a
            # leading `^` / trailing `$`; a miss means no line can match.
            local _cs_up="${pat#^}"
            [[ "$_cs_up" == *'$' && "$_cs_up" != *'\$' ]] && _cs_up="${_cs_up%'$'}"
            local _cs_q="${_cs_up//\[^/}"
            if [[ "$_cs_q" != *[\^\$]* && "$_cs_up" != *'\['* ]]; then
                [[ "$text" =~ $_cs_up ]] || return 1
            fi
            _fr_lines "$text"; for _l in "${_FR_LINES[@]}"; do [[ "$_l" =~ $pat ]] && { hit=1; break; }; done
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
            # A fixed-layout spec that would silently drop columns on a wider
            # table declines here (see _cs_row_overflow) so a generic full-width
            # parser wins instead.
            _cs_row_overflow "$text" && continue
            _CS_MATCHED="$spec"
            _STRATEGY_CONFIDENCE=85
            # Report the matched TOOL name (not the shared "columnar-specs") so
            # the engine names the dataset per-tool. Runs in the parent shell
            # (unlike strategy_extract, which is a command-substitution subshell).
            _STRATEGY_REPORT_NAME="$_CS_NAME"
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
    local IFS='@'; local -a c=(); { _fr_tok "$spec"; c=("${_FR_TOK[@]}"); }
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
    local -a cols=(); { IFS=',' _fr_tok "$_CS_COLS"; cols=("${_FR_TOK[@]}"); }
    local ncols=${#cols[@]}
    local minreq="${_CS_MINREQ:-$ncols}"
    # index of the terminal @rest column (soaks remaining tokens, space-joined), or -1
    local rest_idx=-1 _ci
    for ((_ci=0; _ci<ncols; _ci++)); do [[ "${cols[$_ci]}" == *"@rest" ]] && rest_idx=$_ci; done
    # @line: a sole column capturing the whole TRIMMED line verbatim (no tokenizing).
    # For single-column list outputs (module lists, cfg dumps, cgroup trees).
    local line_mode=0
    [[ $ncols -eq 1 && "${cols[0]}" == *"@line" ]] && line_mode=1

    local result="" entry=0 line past=0 _cs_hdr_line=""
    [[ -z "$_CS_HDR" || "$_CS_HDR" == "-" ]] && past=1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ $past -eq 0 ]]; then
            [[ "$line" == *"$_CS_HDR"* ]] && { past=1; _cs_hdr_line="$line"; }
            continue
        fi
        # A mid-stream repeat of the header line (watch/interval re-prints the
        # whole table every cycle) is chrome, not a data row.
        [[ -n "$_cs_hdr_line" && "$line" == "$_cs_hdr_line" ]] && continue
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
            local IFSbak="$IFS"; IFS='|'; { _fr_tok "$line"; tok=("${_FR_TOK[@]}"); }; IFS="$IFSbak"
            local i; for ((i=0; i<${#tok[@]}; i++)); do tok[$i]="$(_cs_trim "${tok[$i]}")"; done
        else
            { _fr_tok "$line"; tok=("${_FR_TOK[@]}"); }
        fi
        [[ ${#tok[@]} -lt $minreq ]] && continue

        # Assign tokens to columns.
        local -a vals=()
        if [[ "$_CS_DELIM" == "ws" && $rest_idx -ge 0 ]]; then
            # @rest column: takes every remaining token from its slot, joined with
            # single spaces (the same join absorb uses). It is
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
                    for ((j=0; j<extra; j++)); do v="${v} ${tok[$ti]}"; ti=$((ti+1)); done
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
    done
    [[ $entry -gt 0 && "${_CS_TOTAL:-1}" != "0" ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
