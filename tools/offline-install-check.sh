#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# offline-install-check.sh -- install provost from an offline bundle and use it.
#
# Usage: tools/offline-install-check.sh BUNDLE_DIR [PYTHON]
#
# What an air-gapped host does with the bundle (docs/offline-install.md), as a
# test: check SHA256SUMS, make a venv with PYTHON (default python3), pip
# install provost with --no-index from the bundle alone, then run
# `provost --version` (it must be the bundle's version) and one capture.
#
# PROVOST_OFFLINE_EXPECT_NO_NETWORK=1 first proves the network is really off
# (a connection to pypi.org must fail), so a test that passes cannot have
# fetched anything. tools/offline-install-test.sh runs this inside a
# container started with --network none and sets it.
set -euo pipefail

bundle="${1:?usage: offline-install-check.sh BUNDLE_DIR [PYTHON]}"
py="${2:-python3}"
bundle="$(cd "$bundle" && pwd)"

say() { printf '== %s\n' "$*"; }

if [[ "${PROVOST_OFFLINE_EXPECT_NO_NETWORK:-0}" == 1 ]]; then
    say "the network is off"
    if "$py" -c 'import socket; socket.create_connection(("pypi.org", 443), 5)' 2>/dev/null; then
        echo "FAIL: reached pypi.org; this test must run with no network" >&2
        exit 1
    fi
fi

say "SHA256SUMS"
(cd "$bundle" && sha256sum -c SHA256SUMS)

whl="$(cd "$bundle" && ls provost-*-py3-none-any.whl)"
want="${whl#provost-}"; want="${want%%-*}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "pip install --no-index from the bundle ($("$py" --version 2>&1))"
"$py" -m venv "$work/venv"
"$work/venv/bin/python" -m pip install --no-index --find-links "$bundle" provost

say "provost --version"
got="$("$work/venv/bin/provost" --version)"
echo "$got"
[[ "$got" == *"$want"* ]] || { echo "FAIL: expected version $want" >&2; exit 1; }

say "one capture"
export PROVOST_HOME="$work/home"
export PATH="$work/venv/bin:$PATH"
printf 'Filesystem Size Used\n/dev/sda1 50G 20G\n' | provost
provost ls | grep -q aligned-columns || { echo "FAIL: the capture was not filed" >&2; provost ls >&2; exit 1; }
provost show aligned-columns
provost doctor

say "ok: provost $want installed and ran with nothing but the bundle"
