#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## CSV preprocessing for provost-analyze
##
## Provides RFC 4180-compliant CSV-to-TSV conversion. Handles:
##   - Quoted fields with embedded delimiters
##   - Escaped quotes ("" inside quoted fields)
##   - Embedded newlines inside quoted fields (replaced with literal \n)
##   - UTF-8 BOM stripping
##
## The preprocessor runs once before analysis, producing a clean TSV file
## where no field contains a tab. All downstream AWK blocks continue to
## work unchanged with -F"\t".
##
## Reads:  (function arguments only)
## Writes: _STRIP_BOM_RESULT
################################################################################

# Strip UTF-8 BOM if present (EF BB BF).
# Works on a temp copy so the original file is never modified.
# Sets _STRIP_BOM_RESULT to the working file path (temp copy if BOM was
# found, or the original path if no BOM was present).
strip_bom () {
    local file="$1"
    local first3
    first3=$(head -c 3 "$file" | od -An -tx1 | tr -d ' \n')
    if [[ "$first3" == "efbbbf" ]]; then
        local tmp
        tmp=$(mktemp "${TMPDIR:-/tmp}/mda-bom.XXXXXX")
        cleanup_files+=("$tmp")
        tail -c +4 "$file" > "$tmp"
        _STRIP_BOM_RESULT="$tmp"
    else
        _STRIP_BOM_RESULT="$file"
    fi
}

# Fast check: does the file contain any double-quote characters?
# If not, no RFC 4180 preprocessing is needed.
needs_csv_preprocess () {
    local file="$1"
    grep -q '"' "$file"
}

# Convert CSV (with quoting) to clean TSV.
# Args: input_file delimiter
# Output: TSV to stdout
csv_to_tsv () {
    local file="$1"
    local delim="$2"
    awk -v delim="$delim" '
    BEGIN {
        OFS = "\t"
        state = 0   # 0=start-of-field, 1=in-quoted, 2=in-unquoted
        field = ""
        ncols = 0
        row = 0
    }
    {
        line = $0
        len = length(line)
        i = 1
        while (i <= len) {
            ch = substr(line, i, 1)
            if (state == 0) {
                # Start of a new field
                if (ch == "\"") {
                    state = 1
                    field = ""
                    i++
                } else if (ch == delim) {
                    # Empty unquoted field
                    fields[++ncols] = field
                    field = ""
                    i++
                } else {
                    state = 2
                    field = ch
                    i++
                }
            } else if (state == 1) {
                # Inside a quoted field
                if (ch == "\"") {
                    # Check for escaped quote ""
                    if (i < len && substr(line, i+1, 1) == "\"") {
                        field = field "\""
                        i += 2
                    } else {
                        # End of quoted field
                        state = 0
                        fields[++ncols] = field
                        field = ""
                        i++
                        # Skip the delimiter after the closing quote
                        if (i <= len && substr(line, i, 1) == delim) {
                            i++
                            state = 0
                        }
                    }
                } else {
                    field = field ch
                    i++
                }
            } else if (state == 2) {
                # Inside an unquoted field
                if (ch == delim) {
                    fields[++ncols] = field
                    field = ""
                    state = 0
                    i++
                } else {
                    field = field ch
                    i++
                }
            }
        }
        # End of physical line
        if (state == 1) {
            # Still inside a quoted field — embedded newline
            field = field "\\n"
        } else {
            # End of record
            if (state == 2 || state == 0) {
                fields[++ncols] = field
            }
            # Emit the record as TSV (replace any tabs in field values with spaces)
            row++
            for (f = 1; f <= ncols; f++) {
                gsub(/\t/, " ", fields[f])
                if (f > 1) printf "\t"
                printf "%s", fields[f]
            }
            printf "\n"
            # Reset for next record
            ncols = 0
            field = ""
            state = 0
            delete fields
        }
    }
    END {
        # Handle last record if file does not end with newline
        if (ncols > 0 || field != "") {
            fields[++ncols] = field
            for (f = 1; f <= ncols; f++) {
                gsub(/\t/, " ", fields[f])
                if (f > 1) printf "\t"
                printf "%s", fields[f]
            }
            printf "\n"
        }
    }
    ' "$file"
}
