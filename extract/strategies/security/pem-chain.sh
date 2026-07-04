#!/bin/bash
## Name: pem-chain
## Description: Extract fields from PEM certificate chain files
## Version: 1.0
## Priority: 18
## Sample: samples/pem-chain/basic.pem

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Reject JSON
    _is_json "$text" && return 1

    # Must contain BEGIN and END CERTIFICATE markers
    [[ "$text" == *"-----BEGIN CERTIFICATE-----"* ]] || return 1
    [[ "$text" == *"-----END CERTIFICATE-----"* ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local _cert_num=0
    local _in_cert=0
    local _cert_content=""
    local _cert_type=""

    while IFS= read -r line; do
        # Start of certificate block
        if [[ "$line" == "-----BEGIN "* ]]; then
            _in_cert=1
            _cert_content=""
            # Extract type from BEGIN marker
            local _marker="${line#-----BEGIN }"
            _cert_type="${_marker%-----}"
            _cert_type="${_cert_type// /_}"
            continue
        fi

        # End of certificate block
        if [[ "$line" == "-----END "* ]]; then
            _cert_num=$((_cert_num + 1))
            _in_cert=0

            result+="cert${_cert_num}.type ${_cert_type}"$'\n'

            # Calculate size (length of base64 content)
            local _b64_len=${#_cert_content}
            result+="cert${_cert_num}.size ${_b64_len}"$'\n'

            # Try openssl if available
            if command -v openssl >/dev/null 2>&1; then
                local _pem="-----BEGIN CERTIFICATE-----"$'\n'"${_cert_content}"$'\n'"-----END CERTIFICATE-----"
                local _subject _issuer _not_before _not_after _serial

                _subject=$(printf '%s\n' "$_pem" | openssl x509 -noout -subject 2>/dev/null) || true
                if [[ -n "$_subject" ]]; then
                    _subject="${_subject#subject=}"
                    _subject="${_subject#subject= }"
                    while [[ "$_subject" == " "* ]]; do _subject="${_subject# }"; done
                    _subject="${_subject// /_}"
                    [[ -n "$_subject" ]] && result+="cert${_cert_num}.subject ${_subject}"$'\n'
                fi

                _issuer=$(printf '%s\n' "$_pem" | openssl x509 -noout -issuer 2>/dev/null) || true
                if [[ -n "$_issuer" ]]; then
                    _issuer="${_issuer#issuer=}"
                    _issuer="${_issuer#issuer= }"
                    while [[ "$_issuer" == " "* ]]; do _issuer="${_issuer# }"; done
                    _issuer="${_issuer// /_}"
                    [[ -n "$_issuer" ]] && result+="cert${_cert_num}.issuer ${_issuer}"$'\n'
                fi

                _serial=$(printf '%s\n' "$_pem" | openssl x509 -noout -serial 2>/dev/null) || true
                if [[ -n "$_serial" ]]; then
                    _serial="${_serial#serial=}"
                    _serial="${_serial// /_}"
                    [[ -n "$_serial" ]] && result+="cert${_cert_num}.serial ${_serial}"$'\n'
                fi

                _not_before=$(printf '%s\n' "$_pem" | openssl x509 -noout -startdate 2>/dev/null) || true
                if [[ -n "$_not_before" ]]; then
                    _not_before="${_not_before#notBefore=}"
                    _not_before="${_not_before// /_}"
                    [[ -n "$_not_before" ]] && result+="cert${_cert_num}.not_before ${_not_before}"$'\n'
                fi

                _not_after=$(printf '%s\n' "$_pem" | openssl x509 -noout -enddate 2>/dev/null) || true
                if [[ -n "$_not_after" ]]; then
                    _not_after="${_not_after#notAfter=}"
                    _not_after="${_not_after// /_}"
                    [[ -n "$_not_after" ]] && result+="cert${_cert_num}.not_after ${_not_after}"$'\n'
                fi
            fi

            _cert_content=""
            continue
        fi

        # Accumulate base64 content
        if [[ $_in_cert -eq 1 ]]; then
            _cert_content="${_cert_content}${line}"
        fi
    done <<< "$text"

    if [[ $_cert_num -gt 0 ]]; then
        result+="total_certificates ${_cert_num}"$'\n'
    fi

    echo "$result"
}
