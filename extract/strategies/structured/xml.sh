#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: xml
## Description: Extract element text content and attribute key/value pairs from XML/HTML
## Version: 1.0
## Priority: 20
## Sample: samples/xml-elements/basic.xml

# Merges xml-elements and xml-attributes strategies.
# Elements pass:    <tag>content</tag>    -> "tagname content"
# Attributes pass:  <tag attr="value">    -> "tagname.attr value"
# Both passes run sequentially; a single XML file gets both element and attribute fields.
#
# Record mode comes first. When one element is plainly a RECORD — it occurs
# at least twice, every occurrence at the same depth, each carrying two or more
# attributes — the document is a list of those, and each becomes a row:
#
#   <testsuite name="pytest" tests="3">
#     <testcase classname="t.fabric" name="test_bw" time="0.01"/>
#     <testcase classname="t.fabric" name="test_lat" time="0.02">
#       <failure message="too slow" type="AssertionError">assert 1.9 &lt; 1.5</failure>
#     </testcase>
#   </testsuite>
#
# gives one row per <testcase>: its attributes (classname, name, time), the
# parent's identifying attribute (testsuite.name, so rows from several suites
# stay apart), and every descendant's attributes and text under the
# descendant's tag (failure.message, failure.type, failure). Text is
# entity-decoded and its whitespace runs (multi-line tracebacks) folded to
# single spaces. This is JUnit XML from any producer (pytest, ReFrame, Maven,
# ctest) and other XML reports built the same way. Config trees, whose repeated
# elements nest at several depths (Spring <bean>/<property>), and HTML, whose
# repeated elements carry at most one attribute, keep the flat passes below.

# _xml_records TEXT — print the record-mode extraction, or nothing when no
# element qualifies. mawk-safe awk: the input is split on '<' into tags and
# the text that follows each, with a stack of open elements.
_xml_records () {
    printf '%s\n' "$1" | awk '
    function decode(s) {
        gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s); gsub(/&quot;/, "\"", s)
        gsub(/&apos;/, "\047", s); gsub(/&#10;/, " ", s); gsub(/&#13;/, " ", s)
        gsub(/&amp;/, "\\&", s)
        return s
    }
    function fold(s) {
        gsub(/[ \t\r\n]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
        return s
    }
    { buf = buf $0 "\n" }
    END {
        # CDATA may hold a bare "<": escape it before splitting on "<".
        out = ""
        while ((p = index(buf, "<![CDATA[")) > 0) {
            rest = substr(buf, p + 9); q = index(rest, "]]>")
            if (q == 0) break
            cd = substr(rest, 1, q - 1); gsub(/&/, "\\&amp;", cd); gsub(/</, "\\&lt;", cd)
            out = out substr(buf, 1, p - 1) cd; buf = substr(rest, q + 3)
        }
        buf = out buf
        n = split(buf, part, "<")
        ne = 0; sp = 0
        for (i = 2; i <= n; i++) {
            piece = part[i]; gt = index(piece, ">")
            if (gt == 0) continue
            tag = substr(piece, 1, gt - 1); txt = substr(piece, gt + 1)
            c = substr(tag, 1, 1)
            if (c == "?" || c == "!") { if (sp > 0) etxt[stk[sp]] = etxt[stk[sp]] " " txt; continue }
            if (c == "/") { if (sp > 0) sp--; if (sp > 0) etxt[stk[sp]] = etxt[stk[sp]] " " txt; continue }
            self = (substr(tag, length(tag), 1) == "/")
            if (self) tag = substr(tag, 1, length(tag) - 1)
            name = tag; sub(/[ \t\r\n].*/, "", name)
            if (name == "") continue
            ne++; ename[ne] = name; edepth[ne] = sp; eparent[ne] = (sp > 0 ? stk[sp] : 0)
            na = 0; at = substr(tag, length(name) + 1)
            while (match(at, /[A-Za-z_:][A-Za-z0-9_:.-]*[ \t\r\n]*=[ \t\r\n]*("[^"]*"|\047[^\047]*\047)/)) {
                kv = substr(at, RSTART, RLENGTH); at = substr(at, RSTART + RLENGTH)
                eq = index(kv, "="); k = substr(kv, 1, eq - 1); v = substr(kv, eq + 1)
                gsub(/[ \t\r\n]/, "", k); sub(/^[ \t\r\n]*/, "", v)
                v = substr(v, 2, length(v) - 2)
                na++; ak[ne, na] = k; av[ne, na] = decode(fold(v))
            }
            enat[ne] = na
            if (self) { etxt[ne] = ""; if (sp > 0) etxt[stk[sp]] = etxt[stk[sp]] " " txt }
            else { sp++; stk[sp] = ne; etxt[ne] = txt }
        }
        # Choose the record element: >=2 occurrences, one depth, >=2 attributes each.
        for (e = 1; e <= ne; e++) {
            nm = ename[e]; cnt[nm]++
            if (!(nm in dep)) { dep[nm] = edepth[e]; ok[nm] = 1 }
            if (edepth[e] != dep[nm] || enat[e] < 2) ok[nm] = 0
        }
        best = ""
        for (nm in cnt) {
            if (!ok[nm] || cnt[nm] < 2) continue
            if (best == "" || cnt[nm] > cnt[best] || (cnt[nm] == cnt[best] && dep[nm] < dep[best])) best = nm
        }
        if (best == "") exit 0
        entry = 0
        for (e = 1; e <= ne; e++) {
            if (ename[e] != best) continue
            entry++; delete seen
            for (a = 1; a <= enat[e]; a++) emit(entry, ak[e, a], av[e, a])
            p = eparent[e]
            if (p > 0) for (a = 1; a <= enat[p]; a++)
                if (ak[p, a] == "name" || ak[p, a] == "id") emit(entry, ename[p] "." ak[p, a], av[p, a])
            t = decode(fold(etxt[e])); if (t != "") emit(entry, best, t)
            # descendants: every later element whose parent chain reaches e
            for (d = e + 1; d <= ne && edepth[d] > edepth[e]; d++) {
                for (a = 1; a <= enat[d]; a++) emit(entry, ename[d] "." ak[d, a], av[d, a])
                t = decode(fold(etxt[d])); if (t != "") emit(entry, ename[d], t)
            }
        }
        if (entry > 0) printf "total_entries %d\n", entry
    }
    function emit(en, k, v,    key) {
        if (v == "") return
        gsub(/[^A-Za-z0-9_.:-]/, "_", k)
        key = k; if (key in seen) { seen[k]++; key = k "_" seen[k] } else seen[key] = 1
        printf "entry%d.%s %s\n", en, key, v
    }'
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Accept if input looks like XML with elements (opening + closing tags)
    if [[ "$text" == *"<"[a-zA-Z]* && "$text" == *"</"[a-zA-Z]* ]]; then
        return 0
    fi

    # Accept if input has tags with attributes: <tagname attr="
    if [[ "$text" =~ \<[a-zA-Z][a-zA-Z0-9_-]*[[:space:]] ]] && [[ "$text" =~ [a-zA-Z][a-zA-Z0-9_-]*=\" ]]; then
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # --- Record mode (see the header): one row per repeated record element ---
    local records
    records="$(_xml_records "$text")"
    if [[ -n "$records" ]]; then
        printf '%s\n' "$records"
        return
    fi

    # --- Pass 1: element text content ---
    # Match <tag...>content</tag> where content is on the same line
    local elem_matches
    elem_matches=$(echo "$text" | grep -oE '<[a-zA-Z][a-zA-Z0-9_-]*[^>]*>[^<]+</[a-zA-Z][a-zA-Z0-9_-]*>' 2>/dev/null) || true

    _fr_lines "$elem_matches"
    for match in "${_FR_LINES[@]}"; do
        [[ -z "$match" ]] && continue

        local tagname="${match#<}"
        tagname="${tagname%% *}"
        tagname="${tagname%%>*}"
        tagname="${tagname%%/*}"

        local content="${match#*>}"
        content="${content%%<*}"

        local trimmed="$content"
        while [[ "$trimmed" == " "* || "$trimmed" == "	"* ]]; do trimmed="${trimmed#?}"; done
        while [[ "$trimmed" == *" " || "$trimmed" == *"	" ]]; do trimmed="${trimmed%?}"; done
        [[ -z "$trimmed" ]] && continue

        local clean_content="${trimmed}"
        [[ -z "$tagname" ]] && continue

        result+="${tagname} ${clean_content}"$'\n'
    done

    # --- Pass 2: tag attribute key/value pairs ---
    local attr_tags
    attr_tags=$(echo "$text" | grep -oE '<[a-zA-Z][a-zA-Z0-9_-]*[^>]*>' 2>/dev/null) || true

    _fr_lines "$attr_tags"
    for tag in "${_FR_LINES[@]}"; do
        [[ -z "$tag" ]] && continue

        # Skip XML declarations and comments
        case "$tag" in
            '<?'*|'<!--'*) continue ;;
        esac

        local tagname="${tag#<}"
        tagname="${tagname%% *}"
        tagname="${tagname%%/*}"
        tagname="${tagname%%>*}"

        local attrs
        attrs=$(echo "$tag" | grep -oE '[a-zA-Z][a-zA-Z0-9_-]*="[^"]*"' 2>/dev/null) || true

        _fr_lines "$attrs"
        for attr in "${_FR_LINES[@]}"; do
            [[ -z "$attr" ]] && continue

            local attr_name="${attr%%=*}"
            local attr_value="${attr#*=\"}"
            attr_value="${attr_value%\"}"

            [[ -z "$attr_name" ]] && continue
            [[ -z "$attr_value" ]] && continue

            result+="${tagname}.${attr_name} ${attr_value}"$'\n'
        done
    done

    echo "$result"
}
