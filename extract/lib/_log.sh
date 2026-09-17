#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Logging functions for envoy-extract
##
## Per ENV-140: error and warning lines follow the suite-wide
## `<tool>: <level>: <message>` convention so log aggregators / grep rules
## can match a single regex across the whole suite.
################################################################################

_log_error () { echo "envoy-extract: error: $*" >&2; }
_log_warn  () { echo "envoy-extract: warning: $*" >&2; }
_log_info  () { echo "[info] $*" >&2; }
_log_debug () { [[ ${_OPT_debug:-0} -eq 1 ]] && echo "[debug] $*" >&2; return 0; }
