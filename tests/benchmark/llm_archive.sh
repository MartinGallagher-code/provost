# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
# shellcheck shell=bash

################################################################################
## Sourced by llm_round.sh and judge_round.sh (PV-042), after they set $root.
## The benchmark rounds' LLM-written templates, their notes and API logs left
## the tree in 2.22.1; LLM_ARCHIVE is the commit that last holds them, and
## README.md ("LLM run records") says what is there and how to restore it.
##
## need_templates DIR[:DIR...]: return when every directory named holds a
## template (*.json); otherwise say which is missing or empty, give the
## command that restores it from the archive commit (for a directory that
## commit holds), and exit 2. A run offered no template would otherwise read
## every input untemplated and report that as the round's result.
################################################################################

LLM_ARCHIVE=d9c32f046ca1d9457a3ecd7439c2dcf410f85c34
# the template directories that commit holds (git ls-tree -d at it)
LLM_ARCHIVED=" tests/benchmark/round4/llm-templates tests/benchmark/round4/llm-templates-f2
 tests/benchmark/round4/llm-templates-learn tests/benchmark/round4/llm-templates-learn-cleanup
 tests/benchmark/round4/llm-templates-learn-cleanup-repaired
 tests/benchmark/round4/llm-templates-learn-repaired tests/benchmark/round4/llm-templates-repaired
 tests/benchmark/round5/llm-templates-learn tests/benchmark/round5/llm-judge/revised "

need_templates () {
    local d abs parent rel bad=() restore=() _ds
    IFS=: read -ra _ds <<< "$1"
    [[ ${#_ds[@]} -gt 0 ]] || bad+=("")
    for d in ${_ds[@]+"${_ds[@]}"}; do
        [[ -n "$d" && -d "$d" ]] && compgen -G "$d/*.json" > /dev/null && continue
        bad+=("$d")
        # the directory's path from the top of the checkout, if it is in it
        parent="$(cd -- "$(dirname -- "$d")" 2>/dev/null && pwd)" || continue
        abs="$parent/$(basename -- "$d")"
        rel="${abs#"$root"/}"
        [[ "$LLM_ARCHIVED" == *[[:space:]]"$rel"[[:space:]]* ]] && restore+=("$rel")
    done
    [[ ${#bad[@]} -eq 0 ]] && return 0
    {
        for d in "${bad[@]}"; do
            if [[ -z "$d" ]]; then echo "${0##*/}: no templates directory given"
            elif [[ -d "$d" ]]; then echo "${0##*/}: no templates (*.json) in $d"
            else echo "${0##*/}: no such templates directory: $d"; fi
        done
        if [[ ${#restore[@]} -gt 0 ]]; then
            echo "The benchmark rounds' LLM-written templates are no longer in the tree"
            echo "(PV-042, 2.22.1): they are kept at commit ${LLM_ARCHIVE:0:8}. To restore,"
            echo "from the top of the checkout:"
            for rel in "${restore[@]}"; do
                echo "  git archive $LLM_ARCHIVE $rel | tar -x"
            done
            echo "(a shallow clone first needs: git fetch --depth=1 origin $LLM_ARCHIVE)."
            echo "tests/benchmark/README.md, \"LLM run records\", lists what is there."
        fi
        echo "Or name a directory of templates with --templates DIR."
    } >&2
    exit 2
}
