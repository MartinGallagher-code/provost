#!/bin/bash
## Name: openssl
## Description: Extract fields from openssl x509 -text certificate output
## Version: 1.0
## Priority: 15
## Sample: samples/openssl/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Contains "Certificate:" and "Issuer:" or "Subject:" patterns
    [[ "$text" == *"Certificate:"* ]] || return 1
    if [[ "$text" == *"Issuer:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Subject:"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        # Version
        if [[ "$trimmed" == "Version:"* ]]; then
            local version="${trimmed#Version:}"
            while [[ "$version" == " "* ]]; do version="${version# }"; done
            version="${version%% *}"
            result+="version ${version}"$'\n'
            continue
        fi

        # Serial Number
        if [[ "$trimmed" == "Serial Number:"* ]]; then
            local serial="${trimmed#Serial Number:}"
            while [[ "$serial" == " "* ]]; do serial="${serial# }"; done
            result+="serial_number ${serial}"$'\n'
            continue
        fi

        # Signature Algorithm
        if [[ "$trimmed" == "Signature Algorithm:"* ]]; then
            local sig_alg="${trimmed#Signature Algorithm:}"
            while [[ "$sig_alg" == " "* ]]; do sig_alg="${sig_alg# }"; done
            result+="signature_algorithm ${sig_alg}"$'\n'
            continue
        fi

        # Issuer
        if [[ "$trimmed" == "Issuer:"* ]]; then
            local issuer="${trimmed#Issuer:}"
            while [[ "$issuer" == " "* ]]; do issuer="${issuer# }"; done
            result+="issuer ${issuer}"$'\n'
            continue
        fi

        # Not Before
        if [[ "$trimmed" == "Not Before:"* ]]; then
            local not_before="${trimmed#Not Before:}"
            while [[ "$not_before" == " "* ]]; do not_before="${not_before# }"; done
            result+="not_before ${not_before}"$'\n'
            continue
        fi

        # Not After
        if [[ "$trimmed" == "Not After"* ]]; then
            local not_after="${trimmed#Not After}"
            # Remove possible leading space and colon
            while [[ "$not_after" == " "* ]]; do not_after="${not_after# }"; done
            not_after="${not_after#:}"
            while [[ "$not_after" == " "* ]]; do not_after="${not_after# }"; done
            result+="not_after ${not_after}"$'\n'
            continue
        fi

        # Subject
        if [[ "$trimmed" == "Subject:"* ]]; then
            local subject="${trimmed#Subject:}"
            while [[ "$subject" == " "* ]]; do subject="${subject# }"; done
            result+="subject ${subject}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
