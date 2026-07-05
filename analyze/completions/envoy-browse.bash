# bash completion for envoy-browse (ENV-062)

_envoy_browse_complete () {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        --log-file|--interval|--change-token|--settle-ms)
            if [[ "$prev" == "--change-token" ]]; then
                COMPREPLY=( $(compgen -W "mtime-size stat hash" -- "$cur") )
                return 0
            fi
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        local flags="-h --help --all --good --debug --log-file --no-timeout --fresh --watch --interval --change-token --settle-ms --no-preserve-view"
        COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
        return 0
    fi

    COMPREPLY=( $(compgen -f -- "$cur") )
    return 0
}

complete -F _envoy_browse_complete envoy-browse
