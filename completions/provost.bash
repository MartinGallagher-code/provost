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

    local verbs="run inject batch listen unlisten source control uncontrol instances export import log restore next prev files diff search ls show rm stats triage annotate check-manifest doctor verify store help"
    local capopts="--name --min-confidence --min-coverage --min-consistency --plugin-dir --multi --auto-multi --no-auto-multi --model --no-model --llm --no-llm --context-columns --no-context-columns --units --manifest --manifest-profile --strict-manifest --no-strict-manifest --env --env=modules --no-env --show --async --sync --wait --silent --help"
    local ws="${PROVOST_WORKSPACE:-${PROVOST_HOME:-$HOME/.provost}}"

    # First word: complete the verb (or a capture option / file for inject).
    if [[ $cword -eq 1 ]]; then
        case "$cur" in
            -*) COMPREPLY=( $(compgen -W "$capopts --version" -- "$cur") ) ;;
            *)  COMPREPLY=( $(compgen -W "$verbs" -- "$cur") ) ;;
        esac
        return
    fi

    # --units takes a mode, wherever it comes (piped input has no verb).
    if [[ "$prev" == --units ]]; then COMPREPLY=( $(compgen -W "base off" -- "$cur") ); return; fi

    local verb="${COMP_WORDS[1]}"
    case "$verb" in
        help)
            COMPREPLY=( $(compgen -W "advanced $verbs" -- "$cur") ) ;;
        show|stats|rm|delete|drop|diff|search)
            # complete dataset names from the active store (rm also offers flags)
            case "$cur" in
                -*) case "$verb" in
                        show)   COMPREPLY=( $(compgen -W "--capture --at --tsv --help" -- "$cur") ) ;;
                        search) COMPREPLY=( $(compgen -W "-i -F -w -e --at --output --files --help" -- "$cur") ) ;;
                        diff)   COMPREPLY=( $(compgen -W "--help" -- "$cur") ) ;;
                        *)      COMPREPLY=( $(compgen -W "-f --yes --purge --no-purge --keep-captures --help" -- "$cur") ) ;;
                    esac; return ;;
            esac
            local ds
            ds="$(cd "$ws/datasets" 2>/dev/null && ls -1 *.tsv 2>/dev/null | sed 's/\.tsv$//')"
            COMPREPLY=( $(compgen -W "$ds" -- "$cur") ) ;;
        restore|files|source)
            local caps
            caps="latest $(cd "$ws/captures" 2>/dev/null && ls -1d c* 2>/dev/null)"
            COMPREPLY=( $(compgen -W "$caps --help" -- "$cur") ) ;;
        log)
            COMPREPLY=( $(compgen -W "--failed --help" -- "$cur") ) ;;
        store)
            if [[ $cword -eq 2 ]]; then COMPREPLY=( $(compgen -W "check --help" -- "$cur") )
            else COMPREPLY=( $(compgen -d -- "$cur") ); fi ;;
        annotate)
            local caps
            caps="$(cd "$ws/captures" 2>/dev/null && ls -1d c* 2>/dev/null)"
            if [[ $cword -eq 2 ]]; then COMPREPLY=( $(compgen -W "$caps --help" -- "$cur") ); else COMPREPLY=(); fi ;;
        check-manifest)
            case "$prev" in --profile) COMPREPLY=( $(compgen -W "default proposal" -f -- "$cur") ); return ;; esac
            local caps
            caps="$(cd "$ws/captures" 2>/dev/null && ls -1d c* 2>/dev/null) $(cd "$ws/datasets" 2>/dev/null && ls -1 *.tsv 2>/dev/null | sed 's/\.tsv$//')"
            COMPREPLY=( $(compgen -W "--profile --post --strict --help $caps" -- "$cur") ) ;;
        listen|unlisten)
            COMPREPLY=( $(compgen -c -- "$cur") ) ;;
        control|uncontrol|import|export)
            COMPREPLY=( $(compgen -o default -- "$cur") ) ;;   # paths
        run|inject|batch)
            case "$prev" in
                --plugin-dir) COMPREPLY=( $(compgen -d -- "$cur") ); return ;;
                --manifest) COMPREPLY=( $(compgen -f -- "$cur") ); return ;;
                --manifest-profile) COMPREPLY=( $(compgen -W "default proposal" -f -- "$cur") ); return ;;
                --name|--min-confidence|--jobs|-j) COMPREPLY=(); return ;;
                --from) COMPREPLY=( $(compgen -f -- "$cur") ); return ;;
            esac
            case "$cur" in
                -*) if [[ "$verb" == batch ]]; then COMPREPLY=( $(compgen -W "$capopts --jobs --from" -- "$cur") )
                    else COMPREPLY=( $(compgen -W "$capopts" -- "$cur") ); fi ;;
                *)  if [[ "$verb" == run ]]; then COMPREPLY=( $(compgen -c -- "$cur") )   # a command to run
                    else COMPREPLY=( $(compgen -f -- "$cur") ); fi ;;                    # a file to inject
            esac ;;
        *) COMPREPLY=() ;;
    esac
}
complete -F _provost_complete provost
