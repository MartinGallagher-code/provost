#!/bin/bash
################################################################################
## Envoy Suite — Standard Exit Codes
##
## Source this file in any Envoy tool to use consistent exit codes:
##   source "$ENVOY_HOME/lib/exit_codes.sh"
##
## Codes:
##   0  — Success: command completed normally.
##   1  — User error: bad arguments, missing input, invalid tasklist, etc.
##   2  — System error: missing dependency, I/O failure, internal bug.
##  10  — Cancelled: operation cancelled by user (Ctrl-C, interactive abort).
##  11  — Partial: some items succeeded but others failed (batch/pipeline).
##
################################################################################

EXIT_SUCCESS=0
EXIT_USER_ERROR=1
EXIT_SYSTEM_ERROR=2
EXIT_CANCELLED=10
EXIT_PARTIAL=11
