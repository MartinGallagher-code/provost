# bash completion for provost — source this file, or drop it in
# /etc/bash_completion.d/ (the installer does this).
# COMPREPLY=( $(compgen ...) ) is the idiomatic completion form; the words
# compgen emits (verbs, flags, dataset names) contain no whitespace.
# shellcheck disable=SC2207
_provost_complete () {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"; prev="${COMP_WORDS[COMP_CWORD-1]}"
        cword=$COMP_CWORD
    }

    local verbs="run inject source control uncontrol instances export import log restore ls show rm stats triage doctor help"
    local capopts="--name --min-confidence --min-coverage --min-consistency --plugin-dir --multi --auto-multi --no-auto-multi --async --sync --wait --silent --help"
    local ws="${PROVOST_WORKSPACE:-${PROVOST_HOME:-$HOME/.provost}}"

    # First word: complete the verb (or a capture option / file for inject).
    if [[ $cword -eq 1 ]]; then
        case "$cur" in
            -*) COMPREPLY=( $(compgen -W "$capopts --version" -- "$cur") ) ;;
            *)  COMPREPLY=( $(compgen -W "$verbs" -- "$cur") ) ;;
        esac
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
            COMPREPLY=( $(compgen -W "$caps --help" -- "$cur") ) ;;
        log)
            COMPREPLY=( $(compgen -W "--failed --help" -- "$cur") ) ;;
        control|uncontrol|import|export)
            COMPREPLY=( $(compgen -o default -- "$cur") ) ;;   # paths
        run|inject)
            case "$prev" in
                --plugin-dir) COMPREPLY=( $(compgen -d -- "$cur") ); return ;;
                --name|--min-confidence) COMPREPLY=(); return ;;
            esac
            case "$cur" in
                -*) COMPREPLY=( $(compgen -W "$capopts" -- "$cur") ) ;;
                *)  if [[ "$verb" == run ]]; then COMPREPLY=( $(compgen -c -- "$cur") )   # a command to run
                    else COMPREPLY=( $(compgen -f -- "$cur") ); fi ;;                    # a file to inject
            esac ;;
        *) COMPREPLY=() ;;
    esac
}
complete -F _provost_complete provost
