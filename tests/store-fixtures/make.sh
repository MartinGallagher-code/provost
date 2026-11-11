#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# make.sh PROVOST OUT.tar.gz -- build one fixture store with the provost at
# PROVOST (a checkout's `provost` script) and pack it, .git and all, into
# OUT.tar.gz. The fixtures in this directory were made with the last release
# that wrote each store format (PV-022), so the smoke test opens stores an
# older provost really wrote, not stores this one imagines it wrote:
#   format1.tar.gz  provost 2.0.1  (05966453)
#   format2.tar.gz  provost 2.1.0  (3a8d4f10)
#   format3.tar.gz  provost 2.3.0  (3a0a9ad7)
#   format4.tar.gz  provost 2.16.0 (the release that added this script)
# Run on Linux (GNU tar, coreutils), with a checkout of that release:
#   git worktree add /tmp/v2.0.1 05966453 && bash make.sh /tmp/v2.0.1/provost format1.tar.gz
#
# The same five captures go into every store, through `provost run`, which
# every provost since 2.0 has had: a table (`disks`), the same table again
# (appended), the table with a column added (reconciled), the table with a
# data column named `capture` (reconciled: the case store format 4 put
# right, PV-015), a key: value listing (`sysinfo`), and something held back
# in `unsorted` (a threshold no parse meets).
set -euo pipefail
provost="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
out="$2"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
bin="$work/bin"; mkdir -p "$bin"
cat > "$bin/disks" <<'EOF'
#!/bin/sh
case "${DISKS_MODE:-plain}" in
    plain)   printf 'name  size  used\nsda   500   120\nsdb   1000  640\nsdc   250   20\n' ;;
    again)   printf 'name  size  used\nsdd   2000  10\nsde   750   300\n' ;;
    wider)   printf 'name  size  used  model\nsdf   500   12    WDC\nsdg   250   200   ST\n' ;;
    capture) printf 'name  size  used  capture\nsdh   500   7     snap1\nsdi   500   9     snap2\n' ;;
esac
EOF
cat > "$bin/sysinfo" <<'EOF'
#!/bin/sh
printf 'Hostname: fixture\nKernel: 6.1.0\nUptime: 42 days\nLoad: 0.10\n'
EOF
cat > "$bin/noise" <<'EOF'
#!/bin/sh
printf '~~ %s ~~\n' 'a' '!!' '{[' '))' '..'
EOF
chmod +x "$bin"/*
export HOME="$work/home"; mkdir -p "$HOME"
export PATH="$bin:$PATH" PROVOST_WORKSPACE="$work/store" PROVOST_ASYNC=0 PROVOST_QUIET=1
export GIT_AUTHOR_DATE='2026-11-11T12:00:00Z' GIT_COMMITTER_DATE='2026-11-11T12:00:00Z'
unset PROVOST_HOME
cap () { DISKS_MODE="${1:-plain}" bash "$provost" run "${@:2}" || true; }
cap plain   disks
cap again   disks
cap wider   disks
cap capture disks
cap plain   sysinfo
PROVOST_MIN_CONFIDENCE=101 cap plain noise
# What only a later provost writes, where this one can: an input over the
# cap kept by hash beside the store (2.15.0, PV-021), and an annotation.
if grep -q 'PROVOST_OVERSIZE' "$provost"; then
    PROVOST_MAX_INPUT=48 PROVOST_ARTIFACT_DIR="$work/store.artifacts" cap plain disks
fi
if grep -q 'cmd_annotate' "$provost"; then
    bash "$provost" annotate c0001 fixture=yes || true
fi
rm -rf "$work/store/.lock"
packed=(store); [[ -d "$work/store.artifacts" ]] && packed+=(store.artifacts)
tar -C "$work" --sort=name --owner=0 --group=0 --numeric-owner --mtime='2026-11-11 12:00:00Z' \
    -czf "$out" "${packed[@]}"
