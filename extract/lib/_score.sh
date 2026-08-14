#!/bin/bash
################################################################################
## Parse scoring — how good is a candidate parse of an input?
##
## `--multi` cannot know whether a boundary helps until it sees the parse on
## both sides of the decision: splitting `kubectl describe` at its `Conditions:`
## header pre-empts a strategy written to handle the sections together and
## LOSES content, while NOT splitting `iostat -x` keeps only the Device table
## and loses the rest. The two look identical to a splitter that decides before
## detection. They are trivially distinguishable AFTER extraction:
##
##            kubectl describe    iostat -x
##   whole          100%             82%
##   split           94%             99%
##
## So the engine scores candidate segmentations and keeps the best, instead of
## committing to one up front. Two terms, because neither works alone:
##
##   COVERAGE   fraction of the input's significant tokens that survive into
##              some output cell. Catches dropped sections and shredded values.
##              Alone it is gameable: echoing every line as one opaque column
##              scores 100%.
##   TIDINESS   fraction of output cells free of a structural defect — an
##              unsplit column boundary, a separator row kept as data, or a
##              `key: value` pair left sitting inside one cell. These are the
##              checks tests/corpus/prescreen.py applies to review output;
##              scoring them here is what stops coverage being gamed.
##
## The boundary rules PROPOSE a split; the score VETOES it only when the split
## demonstrably loses to the whole-input parse. A tie keeps the split, because
## the rules that produced it (a rule line, a comment run, a count preamble) are
## themselves evidence about the input.
##
## Dependencies: none (pure awk; mawk-safe — no POSIX character classes).
################################################################################

# _score_parse <input-text> <output-field-lines> [n-datasets] -> _SCORE (0..10000)
#
# <output-field-lines> is the engine's own `name value` field stream (STRAT-
# prefixes already stripped), concatenated across every dataset of the
# candidate. Scaled to an integer because bash has no floats.
_score_parse () {
    local _in="$1" _out="$2" _nds="${3:-1}"
    _SCORE=$(awk -v nds="$_nds" '
        # Trim leading/trailing non-alphanumerics; keep the core token so
        # `03/01/2024,` and `03/01/2024` compare equal.
        #
        # CASE-FOLDED, because a parser that normalises a column name is not
        # losing it: bq-ls reads the header `tableId Type` and emits `tableid`
        # and `type`, and comparing case-sensitively scored that as two tokens
        # DROPPED — enough to put the correct whole-input parse (8333) below a
        # split that shredded the table (9545). The question the measure asks
        # is "did this token survive", and case is not part of that.
        function norm(s) {
            gsub(/^[^A-Za-z0-9]+/, "", s)
            gsub(/[^A-Za-z0-9]+$/, "", s)
            return tolower(s)
        }
        function significant(t) { return (t != "" && t ~ /[A-Za-z0-9]/) }
        # Split on underscore as well as whitespace: the engine encodes a space
        # inside a value as `_` (_clean_field), so `Usage_R/U_Rating` must
        # compare equal to `Usage R/U Rating` in the input. Applied to BOTH
        # sides, so the comparison stays symmetric.

        # --- pass 1: the input -------------------------------------------------
        NR == FNR {
            n = split($0, a, /[ \t_]+/)
            for (i = 1; i <= n; i++) {
                t = norm(a[i])
                if (significant(t) && !(t in seen_in)) { seen_in[t] = 1; ntok++ }
            }
            next
        }

        # --- pass 2: the parse -------------------------------------------------
        # Each line is `fieldname value…`; the value is everything after the
        # first space. A valueless line contributes a cell but no tokens.
        {
            if ($0 == "") next
            sp = index($0, " ")
            val = (sp ? substr($0, sp + 1) : "")
            fname = (sp ? substr($0, 1, sp - 1) : $0)
            ncell++

            # Entry-prefixed output (`entryN.field`) carries the row structure:
            # remember how many fields each entry has, so a RAGGED row — one
            # entry with a different field count, which is what a preamble line
            # welded into a table looks like — can be charged below.
            # The caller namespaces each dataset as `d<N>_`, so the entry key is
            # unique across datasets while the dataset it belongs to stays
            # recoverable — raggedness is only meaningful WITHIN one dataset.
            dot = index(fname, ".")
            if (dot > 1) {
                pre = substr(fname, 1, dot - 1)
                if (!(pre in ecount)) {
                    eorder[++nent] = pre
                    us = index(pre, "_")
                    eds[pre] = (us > 1 ? substr(pre, 1, us - 1) : "d0")
                    nper[eds[pre]]++
                }
                ecount[pre]++
            }

            # -- tidiness defects, one charge per cell --
            # A VERBATIM cell is exempt. A `text` dataset is prose the engine
            # deliberately did not parse, so charging it for holding a colon or
            # a double space punishes precisely the decision we want: atlantis
            # keeps `Plan: 2 to add, 0 to change, 0 to destroy.` intact and was
            # docked for it, which put the correct split (7857) below a whole
            # parse (10000) that shredded the same sentence into one column per
            # word — and shredding, the score cannot see at all.
            vname = fname
            sub(/^d[0-9]+_/, "", vname)
            sub(/^entry[0-9]+\./, "", vname)
            verbatim = (vname == "text")
            bad = 0
            # (a) an unsplit column boundary: `a   b` still inside one cell
            if (val ~ /[^ ]  +[^ ]/) bad = 1
            # (b) a separator row kept as data
            probe = val
            gsub(/[ \t|]/, "", probe)
            if (length(probe) >= 3 && probe ~ /^[-=_~*+]+$/) bad = 1
            # (c) a `key: value` pair left sitting inside one cell (not a bare
            #     time `12:30` and not a `scheme://` URL)
            if (val ~ /^[^ ].*: [^ ]/ && val !~ /^[0-9][0-9]?:[0-9][0-9]/ && val !~ /:\/\//) bad = 1
            # (d) a cell that is nothing but a DELIMITER. `|` between two
            #     columns is punctuation, and a parse that emits it as its own
            #     cell has read the frame as data — the reviewer, on eleven AWS
            #     `table` outputs at once: "the pipes are delimiters, and should
            #     not appear in the output". Without this the shredded parse of
            #     an ASCII box outscores the clean one, because the frame lines
            #     it keeps count as recovered content.
            if (val ~ /^[|]+$/) bad = 1
            if (verbatim) bad = 0
            if (bad) nbad++

            n = split(val, b, /[ \t_]+/)
            for (i = 1; i <= n; i++) {
                t = norm(b[i])
                if (significant(t)) seen_out[t] = 1
            }

            # A field NAME taken from the input SURVIVED into the parse just as
            # much as a value did: `entry1.acct alice` keeps both `acct` and
            # `alice`. Counting only values would rank promoting a header word
            # to a column name BELOW dumping that header out as prose, which is
            # backwards. Names the engine invents (lineN, total_entries, the
            # A/B/C placeholders of an unnamed table) are not input tokens, so
            # they are skipped rather than credited.
            nm = fname
            sub(/^d[0-9]+_/, "", nm)
            sub(/^entry[0-9]+\./, "", nm)
            if (nm !~ /^line[0-9]+$/ && nm != "total_entries" && nm != "text" && nm !~ /^[A-Z][A-Z]?$/) {
                n = split(nm, k, /[ \t_.]+/)
                for (i = 1; i <= n; i++) {
                    t = norm(k[i])
                    if (significant(t)) seen_out[t] = 1
                }
            }
        }

        END {
            if (ntok == 0) { print 0; exit }

            # RAGGED ROWS. With >=3 entries, find the modal field count and
            # charge every field of an entry that deviates. A preamble line
            # welded into a table shows up here (`running 3 tests` yields a
            # 3-field entry among 4-field ones) even though its tokens are all
            # present, which coverage alone cannot see.
            for (d in nper) {
                if (nper[d] < 3) continue          # too few rows to call a shape
                for (c in freq) delete freq[c]
                best = 0; modal = 0
                for (i = 1; i <= nent; i++) if (eds[eorder[i]] == d) freq[ecount[eorder[i]]]++
                for (c in freq) if (freq[c] > best || (freq[c] == best && c + 0 > modal)) { best = freq[c]; modal = c + 0 }
                for (i = 1; i <= nent; i++)
                    if (eds[eorder[i]] == d && ecount[eorder[i]] != modal) nbad += ecount[eorder[i]]
            }

            for (t in seen_in) if (t in seen_out) hit++
            coverage = hit / ntok
            tidy = (ncell > 0) ? (1 - (nbad / ncell)) : 1
            # Coverage dominates; tidiness is a half-weight modifier so a parse
            # cannot win by echoing the input as one opaque column. There is no
            # fragmentation penalty: only ONE split candidate is ever scored —
            # the one the boundary rules proposed — so the score never has to
            # discourage arbitrary over-splitting, and penalising dataset count
            # would just fight the evidence those rules represent.
            s = coverage - 0.5 * (1 - tidy)
            if (s < 0) s = 0
            printf "%d\n", s * 10000
        }
    ' <(printf '%s\n' "$_in") <(printf '%s\n' "$_out"))
    [[ "$_SCORE" =~ ^[0-9]+$ ]] || _SCORE=0
}
