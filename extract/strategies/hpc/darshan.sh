#!/bin/bash
## Name: darshan
## Description: Extract I/O profiling data from darshan-parser text output
## Version: 1.0
## Priority: 15
## Sample: samples/darshan/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Darshan header comment
    if [[ "$text" == *"# darshan"* ]]; then
        return 0
    fi

    # Darshan log version line
    if [[ "$text" == *"log version"* && "$text" == *"darshan"* ]]; then
        return 0
    fi

    # Module counters (POSIX, MPI-IO, STDIO are darshan modules)
    local module_count=0
    [[ "$text" == *"POSIX"* ]] && module_count=$((module_count + 1))
    [[ "$text" == *"MPI-IO"* ]] && module_count=$((module_count + 1))
    [[ "$text" == *"STDIO"* ]] && module_count=$((module_count + 1))

    if [[ $module_count -ge 2 && "$text" == *"_OPENS"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_module=""
    local num_files=0
    local -A seen_files

    # Accumulators
    local posix_bytes_read=0
    local posix_bytes_written=0
    local posix_opens=0
    local posix_reads=0
    local posix_writes=0
    local posix_fsyncs=0
    local posix_read_time=0
    local posix_write_time=0
    local mpiio_bytes_read=0
    local mpiio_bytes_written=0
    local mpiio_opens=0
    local mpiio_reads=0
    local mpiio_writes=0
    local stdio_bytes_read=0
    local stdio_bytes_written=0
    local stdio_opens=0
    local stdio_reads=0
    local stdio_writes=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip pure comment lines except darshan metadata
        if [[ "$line" =~ ^#[[:space:]]*darshan[[:space:]]+log[[:space:]]+version[[:space:]]*:[[:space:]]*(.*) ]]; then
            result+="log_version ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^#[[:space:]]*exe[[:space:]]*:[[:space:]]*(.*) ]]; then
            result+="exe ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^#[[:space:]]*nprocs[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            result+="nprocs ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^#[[:space:]]*run[[:space:]]+time[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
            result+="run_time ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^#[[:space:]]*start_time[[:space:]]*:[[:space:]]*(.*) ]]; then
            result+="start_time ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Skip other comments
        [[ "$line" =~ ^# ]] && continue

        # Counter=value lines from darshan-parser
        # Full format: module  rank  record_id  counter  value  file_name  mount_pt  fs_type
        # Or simpler: counter<tab>value
        _strat_darshan_parse_counter "$line"

    done <<< "$text"

    # Emit POSIX metrics
    _strat_darshan_emit_if_nonzero "posix_bytes_read" "$posix_bytes_read"
    _strat_darshan_emit_if_nonzero "posix_bytes_written" "$posix_bytes_written"
    _strat_darshan_emit_if_nonzero "posix_opens" "$posix_opens"
    _strat_darshan_emit_if_nonzero "posix_reads" "$posix_reads"
    _strat_darshan_emit_if_nonzero "posix_writes" "$posix_writes"
    _strat_darshan_emit_if_nonzero "posix_fsyncs" "$posix_fsyncs"
    _strat_darshan_emit_if_nonzero "posix_read_time" "$posix_read_time"
    _strat_darshan_emit_if_nonzero "posix_write_time" "$posix_write_time"

    # Emit MPI-IO metrics
    _strat_darshan_emit_if_nonzero "mpiio_bytes_read" "$mpiio_bytes_read"
    _strat_darshan_emit_if_nonzero "mpiio_bytes_written" "$mpiio_bytes_written"
    _strat_darshan_emit_if_nonzero "mpiio_opens" "$mpiio_opens"
    _strat_darshan_emit_if_nonzero "mpiio_reads" "$mpiio_reads"
    _strat_darshan_emit_if_nonzero "mpiio_writes" "$mpiio_writes"

    # Emit STDIO metrics
    _strat_darshan_emit_if_nonzero "stdio_bytes_read" "$stdio_bytes_read"
    _strat_darshan_emit_if_nonzero "stdio_bytes_written" "$stdio_bytes_written"
    _strat_darshan_emit_if_nonzero "stdio_opens" "$stdio_opens"
    _strat_darshan_emit_if_nonzero "stdio_reads" "$stdio_reads"
    _strat_darshan_emit_if_nonzero "stdio_writes" "$stdio_writes"

    # Totals
    local total_bytes_read=$((posix_bytes_read + mpiio_bytes_read + stdio_bytes_read))
    local total_bytes_written=$((posix_bytes_written + mpiio_bytes_written + stdio_bytes_written))
    _strat_darshan_emit_if_nonzero "total_bytes_read" "$total_bytes_read"
    _strat_darshan_emit_if_nonzero "total_bytes_written" "$total_bytes_written"

    # File count
    if [[ ${#seen_files[@]} -gt 0 ]]; then
        result+="num_files ${#seen_files[@]}"$'\n'
    fi

    # I/O time
    local io_time
    if [[ "$posix_read_time" != "0" || "$posix_write_time" != "0" ]]; then
        io_time=$(echo "$posix_read_time + $posix_write_time" | bc 2>/dev/null || echo "0")
        _strat_darshan_emit_if_nonzero "io_time" "$io_time"
    fi

    echo "$result"
}

_strat_darshan_parse_counter () {
    local line="$1"

    # Full darshan-parser format (tab or space separated):
    # module  rank  record_id  counter  value  file_name  mount_pt  fs_type
    local fields
    read -ra fields <<< "$line"

    # Need at least 5 fields for the full format
    if [[ ${#fields[@]} -ge 5 ]]; then
        local module="${fields[0]}"
        local counter="${fields[3]}"
        local value="${fields[4]}"
        local filename="${fields[5]:-}"

        # Track unique files
        if [[ -n "$filename" && "$filename" != "-1" && "$filename" != "0" ]]; then
            seen_files["$filename"]=1
        fi

        # Route to module
        case "$module" in
            POSIX)  _strat_darshan_accum_posix "$counter" "$value" ;;
            MPI-IO) _strat_darshan_accum_mpiio "$counter" "$value" ;;
            STDIO)  _strat_darshan_accum_stdio "$counter" "$value" ;;
        esac
        return
    fi

    # Simple counter=value or counter<tab>value format
    if [[ "$line" =~ ^([A-Z_]+)[[:space:]=]+([0-9]+\.?[0-9]*) ]]; then
        local counter="${BASH_REMATCH[1]}"
        local value="${BASH_REMATCH[2]}"
        _strat_darshan_accum_posix "$counter" "$value"
    fi
}

_strat_darshan_accum_posix () {
    local counter="$1"
    local value="$2"
    case "$counter" in
        POSIX_BYTES_READ|*_BYTES_READ)
            posix_bytes_read=$((posix_bytes_read + value)) ;;
        POSIX_BYTES_WRITTEN|*_BYTES_WRITTEN)
            posix_bytes_written=$((posix_bytes_written + value)) ;;
        POSIX_OPENS|*_OPENS)
            posix_opens=$((posix_opens + value)) ;;
        POSIX_READS|*_READS)
            posix_reads=$((posix_reads + value)) ;;
        POSIX_WRITES|*_WRITES)
            posix_writes=$((posix_writes + value)) ;;
        POSIX_FSYNCS|*_FSYNCS)
            posix_fsyncs=$((posix_fsyncs + value)) ;;
        POSIX_F_READ_TIME|*_READ_TIME)
            posix_read_time="$value" ;;
        POSIX_F_WRITE_TIME|*_WRITE_TIME)
            posix_write_time="$value" ;;
    esac
}

_strat_darshan_accum_mpiio () {
    local counter="$1"
    local value="$2"
    case "$counter" in
        MPIIO_BYTES_READ|*_BYTES_READ)
            mpiio_bytes_read=$((mpiio_bytes_read + value)) ;;
        MPIIO_BYTES_WRITTEN|*_BYTES_WRITTEN)
            mpiio_bytes_written=$((mpiio_bytes_written + value)) ;;
        MPIIO_INDEP_OPENS|MPIIO_COLL_OPENS|*_OPENS)
            mpiio_opens=$((mpiio_opens + value)) ;;
        MPIIO_INDEP_READS|MPIIO_COLL_READS|*_READS)
            mpiio_reads=$((mpiio_reads + value)) ;;
        MPIIO_INDEP_WRITES|MPIIO_COLL_WRITES|*_WRITES)
            mpiio_writes=$((mpiio_writes + value)) ;;
    esac
}

_strat_darshan_accum_stdio () {
    local counter="$1"
    local value="$2"
    case "$counter" in
        STDIO_BYTES_READ|*_BYTES_READ)
            stdio_bytes_read=$((stdio_bytes_read + value)) ;;
        STDIO_BYTES_WRITTEN|*_BYTES_WRITTEN)
            stdio_bytes_written=$((stdio_bytes_written + value)) ;;
        STDIO_OPENS|*_OPENS)
            stdio_opens=$((stdio_opens + value)) ;;
        STDIO_READS|*_READS)
            stdio_reads=$((stdio_reads + value)) ;;
        STDIO_WRITES|*_WRITES)
            stdio_writes=$((stdio_writes + value)) ;;
    esac
}

_strat_darshan_emit_if_nonzero () {
    local key="$1"
    local val="$2"
    if [[ "$val" != "0" && -n "$val" ]]; then
        result+="${key} ${val}"$'\n'
    fi
}
