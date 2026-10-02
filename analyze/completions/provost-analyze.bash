# bash completion for provost-analyze (ENV-062)
# Install: copy to ~/.local/share/bash-completion/completions/provost-analyze
#    or:  source this file from your ~/.bashrc

_provost_analyze_complete () {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Flags accepting enumerated values
    case "$prev" in
        --format)
            COMPREPLY=( $(compgen -W "plain json markdown csv tsv html" -- "$cur") )
            return 0
            ;;
        --mode)
            COMPREPLY=( $(compgen -W "benchmark monitor explore" -- "$cur") )
            return 0
            ;;
        --tags)
            COMPREPLY=( $(compgen -W "GOOD NOISY ADVANCED DIAGNOSTIC" -- "$cur") )
            return 0
            ;;
        --color)
            COMPREPLY=( $(compgen -W "auto always never" -- "$cur") )
            return 0
            ;;
        --benford-alpha)
            COMPREPLY=( $(compgen -W "0.05 0.01 0.001" -- "$cur") )
            return 0
            ;;
        --profile|--save|--suggest-save)
            # Profile names from the default profiles dir or --profile-dir if set
            local pdir
            pdir=""
            local i
            for ((i=1; i<COMP_CWORD; i++)); do
                if [[ "${COMP_WORDS[i]}" == "--profile-dir" ]]; then
                    pdir="${COMP_WORDS[i+1]:-}"
                    break
                fi
            done
            if [[ -z "$pdir" ]]; then
                # Guess default relative to script location (installed or local)
                local script_dir
                script_dir="$(command -v provost-analyze 2>/dev/null)"
                if [[ -n "$script_dir" ]]; then
                    pdir="$(dirname "$(readlink -f "$script_dir")")/profiles"
                fi
            fi
            if [[ -n "$pdir" && -d "$pdir" ]]; then
                local names=()
                local f
                for f in "$pdir"/*.profile; do
                    [[ -e "$f" ]] || continue
                    names+=( "$(basename "${f%.profile}")" )
                done
                COMPREPLY=( $(compgen -W "${names[*]}" -- "$cur") )
            fi
            return 0
            ;;
        --profile-dir)
            COMPREPLY=( $(compgen -d -- "$cur") )
            return 0
            ;;
        --delimiter|--max-corr-cols|--max-groups|--max-group-unique|\
        --columns|--threshold|--top-n|--numeric-columns|\
        --categorical-columns|--missing-values|--categorical-unique-max|\
        --categorical-ratio-max|--head|--sample|--seed|--log-file)
            # Free-form values; fall through to default completion (files)
            ;;
    esac

    if [[ "$cur" == --* || "$cur" == -* ]]; then
        local flags="
            -h --help -V --version
            --delimiter --profile --save --profile-dir
            --good --all --tags --kinds
            --list-items --suggest --suggest-save
            --format --max-corr-cols --max-groups --max-group-unique
            --columns --compare --threshold --mode --summary
            --timeseries --top-n
            --numeric-columns --categorical-columns
            --missing-values --missing-values-case-insensitive
            --categorical-unique-max --categorical-ratio-max
            --benford-alpha --color
            --head --sample --seed
        "
        COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
        return 0
    fi

    # Default: complete file paths
    COMPREPLY=( $(compgen -f -- "$cur") )
    return 0
}

complete -F _provost_analyze_complete provost-analyze
