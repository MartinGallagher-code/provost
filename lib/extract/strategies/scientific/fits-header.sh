#!/bin/bash
## Name: fits-header
## Description: Extract key metadata from FITS header dumps (fitsheader output)
## Version: 1.0
## Priority: 10
## Sample: samples/fits-header/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"SIMPLE"* ]] && hits=$((hits + 1))
    [[ "$text" == *"BITPIX"* ]] && hits=$((hits + 1))
    [[ "$text" == *"NAXIS"* ]] && hits=$((hits + 1))
    [[ "$text" == *"FITS"* ]] && hits=$((hits + 1))
    [[ "$text" == *"END"* ]] && hits=$((hits + 1))
    [[ "$text" == *"EXTEND"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]] && [[ "$text" == *"BITPIX"* ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 3 ]] && [[ "$text" == *"NAXIS"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # FITS header cards have format: KEYWORD = value / comment
    # or: KEYWORD = 'string value' / comment
    local num_extensions=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Parse KEYWORD = value lines
        # Standard FITS: columns 1-8 keyword, col 9 '=', col 10 ' ', cols 11-80 value/comment
        local keyword=""
        local value=""

        if [[ "$line" =~ ^([A-Z0-9_-]+)\ *=\ *(.*) ]]; then
            keyword="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"

            # Strip inline comment (after /)
            if [[ "$value" == *"'"*"'"* ]]; then
                # String value: extract between quotes
                if [[ "$value" =~ \'([^\']*)\' ]]; then
                    value="${BASH_REMATCH[1]}"
                    # Trim trailing spaces from string values
                    while [[ "$value" == *" " ]]; do value="${value% }"; done
                fi
            else
                # Numeric or logical value: strip comment after /
                value="${value%%/*}"
                # Trim spaces
                while [[ "$value" == " "* ]]; do value="${value# }"; done
                while [[ "$value" == *" " ]]; do value="${value% }"; done
            fi
        else
            continue
        fi

        [[ -z "$keyword" || -z "$value" ]] && continue

        case "$keyword" in
            SIMPLE)
                result+="simple ${value}"$'\n'
                ;;
            BITPIX)
                result+="bitpix ${value}"$'\n'
                ;;
            NAXIS)
                result+="naxis ${value}"$'\n'
                ;;
            NAXIS1)
                result+="naxis1 ${value}"$'\n'
                ;;
            NAXIS2)
                result+="naxis2 ${value}"$'\n'
                ;;
            NAXIS3)
                result+="naxis3 ${value}"$'\n'
                ;;
            NAXIS4)
                result+="naxis4 ${value}"$'\n'
                ;;
            OBJECT)
                result+="object ${value}"$'\n'
                ;;
            TELESCOP)
                result+="telescope ${value}"$'\n'
                ;;
            INSTRUME)
                result+="instrument ${value}"$'\n'
                ;;
            DATE-OBS)
                result+="date_obs ${value}"$'\n'
                ;;
            EXPTIME)
                result+="exptime ${value}"$'\n'
                ;;
            FILTER)
                result+="filter ${value}"$'\n'
                ;;
            BUNIT)
                result+="bunit ${value}"$'\n'
                ;;
            CRVAL1)
                result+="crval1 ${value}"$'\n'
                ;;
            CRVAL2)
                result+="crval2 ${value}"$'\n'
                ;;
            CTYPE1)
                result+="ctype1 ${value}"$'\n'
                ;;
            CTYPE2)
                result+="ctype2 ${value}"$'\n'
                ;;
            EQUINOX)
                result+="equinox ${value}"$'\n'
                ;;
            EXTEND)
                result+="extend ${value}"$'\n'
                ;;
            XTENSION)
                num_extensions=$((num_extensions + 1))
                result+="extension${num_extensions}.type ${value}"$'\n'
                ;;
        esac
    done <<< "$text"

    [[ $num_extensions -gt 0 ]] && result+="num_extensions ${num_extensions}"$'\n'

    echo "$result"
}
