#!/bin/bash
## Name: pbs
## Description: Extract job and node information from PBS/Torque scheduler output (qstat, pbsnodes)
## Version: 1.0
## Priority: 15
## Sample: samples/pbs/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # qstat -f output
    if [[ "$text" == *"Job_Name"* || "$text" == *"job_state"* ]]; then
        if [[ "$text" == *"PBS"* || "$text" == *"queue"* || "$text" == *"Job Id"* ]]; then
            return 0
        fi
    fi
    # pbsnodes output
    if [[ "$text" == *"pbsnodes"* ]]; then
        if [[ "$text" == *"state"* || "$text" == *"np"* || "$text" == *"status"* ]]; then
            return 0
        fi
    fi
    # qstat table output
    if [[ "$text" == *"Job id"* || "$text" == *"Job ID"* ]]; then
        if [[ "$text" == *"Queue"* || "$text" == *"Req'd"* || "$text" == *"Elap"* ]]; then
            return 0
        fi
    fi
    # PBS-specific environment
    if [[ "$text" == *"PBS_JOBID"* || "$text" == *"PBS_O_WORKDIR"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Detect output type and dispatch
    if [[ "$text" == *"Job Id:"* && "$text" == *"Job_Name"* ]]; then
        local _out
        _out=$(_strat_pbs_extract_qstat_full "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"pbsnodes"* ]] || \
         [[ "$text" == *"state ="* && "$text" == *"np ="* ]]; then
        local _out
        _out=$(_strat_pbs_extract_pbsnodes "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"Job id"* || "$text" == *"Job ID"* ]]; then
        local _out
        _out=$(_strat_pbs_extract_qstat_table "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    echo "$result"
}

_strat_pbs_extract_qstat_full () {
    local text="$1"
    local result=""
    local job_id="" job_name="" queue="" state="" nodes=""
    local walltime="" cput="" exit_status=""

    while IFS= read -r _line; do
        # Job Id: 12345.pbs-server
        if [[ "$_line" == *"Job Id:"* && -z "$job_id" ]]; then
            job_id="${_line#*Job Id: }"
            while [[ "$job_id" == " "* ]]; do job_id="${job_id# }"; done
        fi
        # Job_Name = test_job
        if [[ "$_line" == *"Job_Name"* && -z "$job_name" ]]; then
            job_name="${_line#*= }"
            while [[ "$job_name" == " "* ]]; do job_name="${job_name# }"; done
        fi
        # queue = batch
        if [[ "$_line" == *"queue"*"="* && -z "$queue" ]]; then
            queue="${_line#*= }"
            while [[ "$queue" == " "* ]]; do queue="${queue# }"; done
        fi
        # job_state = R
        if [[ "$_line" == *"job_state"* && -z "$state" ]]; then
            state="${_line#*= }"
            while [[ "$state" == " "* ]]; do state="${state# }"; done
        fi
        # Resource_List.nodes = 2:ppn=8
        if [[ "$_line" == *"Resource_List.nodes"* && -z "$nodes" ]]; then
            nodes="${_line#*= }"
            while [[ "$nodes" == " "* ]]; do nodes="${nodes# }"; done
        fi
        # Resource_List.walltime = 01:00:00
        if [[ "$_line" == *"Resource_List.walltime"* && -z "$walltime" ]]; then
            walltime="${_line#*= }"
            while [[ "$walltime" == " "* ]]; do walltime="${walltime# }"; done
        fi
        # resources_used.cput = 00:30:00
        if [[ "$_line" == *"resources_used.cput"* && -z "$cput" ]]; then
            cput="${_line#*= }"
            while [[ "$cput" == " "* ]]; do cput="${cput# }"; done
        fi
        # resources_used.walltime
        if [[ "$_line" == *"resources_used.walltime"* ]]; then
            local _wt="${_line#*= }"
            while [[ "$_wt" == " "* ]]; do _wt="${_wt# }"; done
            [[ -n "$_wt" ]] && result+="walltime_used ${_wt}"$'\n'
        fi
        # exit_status = 0
        if [[ "$_line" == *"exit_status"* && -z "$exit_status" ]]; then
            exit_status="${_line#*= }"
            while [[ "$exit_status" == " "* ]]; do exit_status="${exit_status# }"; done
        fi
    done <<< "$text"

    [[ -n "$job_id" ]] && result+="job_id ${job_id}"$'\n'
    [[ -n "$job_name" ]] && result+="job_name ${job_name}"$'\n'
    [[ -n "$queue" ]] && result+="queue ${queue}"$'\n'
    [[ -n "$state" ]] && result+="state ${state}"$'\n'
    [[ -n "$nodes" ]] && result+="nodes ${nodes}"$'\n'
    [[ -n "$walltime" ]] && result+="walltime ${walltime}"$'\n'
    [[ -n "$cput" ]] && result+="cput ${cput}"$'\n'
    [[ -n "$exit_status" ]] && result+="exit_status ${exit_status}"$'\n'

    echo "$result"
}

_strat_pbs_extract_qstat_table () {
    local text="$1"
    local result=""
    local header_found=0
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Header: "Job id  Name  User  Time Use  S  Queue"
        if [[ $header_found -eq 0 && ( "$_line" == *"Job id"* || "$_line" == *"Job ID"* ) ]]; then
            header_found=1
            continue
        fi

        # Skip separator
        if [[ $header_found -eq 1 && "$_line" == *"------"* ]]; then
            continue
        fi

        # Data rows
        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -lt 4 ]] && continue

            job_num=$((job_num + 1))
            local prefix=""
            if [[ $job_num -gt 1 ]]; then
                prefix="job${job_num}."
            fi

            result+="${prefix}job_id ${_fields[0]}"$'\n'
            [[ ${#_fields[@]} -ge 2 ]] && result+="${prefix}job_name ${_fields[1]}"$'\n'
            [[ ${#_fields[@]} -ge 3 ]] && result+="${prefix}user ${_fields[2]}"$'\n'
            # Time Use and State vary in position; find single-char state
            local i
            for i in "${!_fields[@]}"; do
                local f="${_fields[$i]}"
                if [[ ${#f} -eq 1 && "$f" =~ ^[RQHCESW]$ ]]; then
                    result+="${prefix}state ${f}"$'\n'
                fi
            done
            # Queue is typically the last field
            local last_idx=$(( ${#_fields[@]} - 1 ))
            result+="${prefix}queue ${_fields[$last_idx]}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_pbs_extract_pbsnodes () {
    local text="$1"
    local result=""
    local node_num=0
    local current_node=""

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Node name line (not indented, no = sign)
        if [[ "$_line" != *"="* && "$_line" != " "* && "$_line" != $'\t'* ]]; then
            node_num=$((node_num + 1))
            local prefix=""
            if [[ $node_num -gt 1 ]]; then
                prefix="node${node_num}."
            fi
            current_node="$_line"
            while [[ "$current_node" == " "* ]]; do current_node="${current_node# }"; done
            result+="${prefix}hostname ${current_node}"$'\n'
            continue
        fi

        local prefix=""
        if [[ $node_num -gt 1 ]]; then
            prefix="node${node_num}."
        fi

        # state = free
        if [[ "$_line" == *"state ="* ]]; then
            local _val="${_line#*= }"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            result+="${prefix}state ${_val}"$'\n'
        fi
        # np = 16
        if [[ "$_line" == *"np ="* ]]; then
            local _val="${_line#*= }"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            result+="${prefix}np ${_val}"$'\n'
        fi
        # ntype = cluster
        if [[ "$_line" == *"ntype ="* ]]; then
            local _val="${_line#*= }"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            result+="${prefix}ntype ${_val}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
