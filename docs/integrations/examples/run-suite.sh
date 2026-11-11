#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# A plain shell harness: run every test script in a directory through
# provost-wrap, each one's output filed with its name, the host and the run as
# columns, and exit non-zero if any test failed.
#   run-suite.sh TESTDIR
set -u
here="$(cd "$(dirname -- "$0")" && pwd)"
run="$(date -u +%Y%m%dT%H%M%SZ)"
failed=0
for t in "$1"/*.sh; do
    name="$(basename -- "$t" .sh)"
    "$here/provost-wrap" --name "suite.$name" \
        test="$name" host="$(uname -n)" run.id="$run" -- bash "$t" \
        || { echo "FAIL $name" >&2; failed=$((failed + 1)); }
done
echo "$failed test(s) failed"
(( failed == 0 ))
