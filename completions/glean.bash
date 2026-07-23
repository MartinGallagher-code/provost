# bash completion for glean — source this file, or drop it in
# /etc/bash_completion.d/ (the installer does this).
_glean_complete () {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"; prev="${COMP_WORDS[COMP_CWORD-1]}"
        cword=$COMP_CWORD
    }

    local verbs="run inject source control uncontrol instances export import log restore ls show rm stats triage doctor help"
    local ws="${GLEAN_WORKSPACE:-${GLEAN_HOME:-$HOME/.glean}}"

    # First word: complete the verb.
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$verbs" -- "$cur") )
        return
    fi

    local verb="${COMP_WORDS[1]}"
    case "$verb" in
        show|stats|rm|delete|drop)
            # complete dataset names from the active store (rm also offers flags)
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "-f --yes --purge --no-purge --keep-captures --help" -- "$cur") ); return ;;
            esac
            local ds
            ds="$(cd "$ws/datasets" 2>/dev/null && ls -1 *.tsv 2>/dev/null | sed 's/\.tsv$//')"
            COMPREPLY=( $(compgen -W "$ds" -- "$cur") ) ;;
        restore)
            local caps
            caps="latest $(cd "$ws/captures" 2>/dev/null && ls -1d c* 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$caps" -- "$cur") ) ;;
        control|uncontrol|import|export)
            COMPREPLY=( $(compgen -o default -- "$cur") ) ;;   # paths
        run|inject)
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "--silent --min-confidence --plugin-dir --async --sync --help" -- "$cur") ) ;;
                *)  COMPREPLY=( $(compgen -c -- "$cur") ) ;;    # a command to run
            esac ;;
        *) COMPREPLY=() ;;
    esac
}
complete -F _glean_complete glean
