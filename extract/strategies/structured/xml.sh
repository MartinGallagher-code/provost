#!/bin/bash
## Name: xml
## Description: Extract element text content and attribute key/value pairs from XML/HTML
## Version: 1.0
## Priority: 20
## Sample: samples/xml-elements/basic.xml

# Merges xml-elements and xml-attributes strategies.
# Elements pass:    <tag>content</tag>    -> "tagname content"
# Attributes pass:  <tag attr="value">    -> "tagname.attr value"
# Both passes run sequentially; a single XML file gets both element and attribute fields.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

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

    # --- Pass 1: element text content ---
    # Match <tag...>content</tag> where content is on the same line
    local elem_matches
    elem_matches=$(echo "$text" | grep -oE '<[a-zA-Z][a-zA-Z0-9_-]*[^>]*>[^<]+</[a-zA-Z][a-zA-Z0-9_-]*>' 2>/dev/null) || true

    while IFS= read -r match; do
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
    done <<< "$elem_matches"

    # --- Pass 2: tag attribute key/value pairs ---
    local attr_tags
    attr_tags=$(echo "$text" | grep -oE '<[a-zA-Z][a-zA-Z0-9_-]*[^>]*>' 2>/dev/null) || true

    while IFS= read -r tag; do
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

        while IFS= read -r attr; do
            [[ -z "$attr" ]] && continue

            local attr_name="${attr%%=*}"
            local attr_value="${attr#*=\"}"
            attr_value="${attr_value%\"}"

            [[ -z "$attr_name" ]] && continue
            [[ -z "$attr_value" ]] && continue

            result+="${tagname}.${attr_name} ${attr_value}"$'\n'
        done <<< "$attrs"
    done <<< "$attr_tags"

    echo "$result"
}
