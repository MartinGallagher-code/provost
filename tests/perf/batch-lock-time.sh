#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher
#
# batch-lock-time.sh N [PROVOST] — how long one `provost batch` of N inputs
# holds the store lock (PV-024). Not part of any gate: a measurement.
#
# Files N synthetic one-host outputs (a '#% host=' prologue and a 3-column
# CSV row each, the shape quarterdeck files) into a fresh store, while a
# background loop polls for the store's .lock directory every 5 ms. The hold
# is the time from the first poll that saw the lock to the last; the
# resolution is the poll interval plus a fork. Prints one line:
#   N=... total=...s lock_held=...s per_input=...ms
set -u
N="${1:?usage: batch-lock-time.sh N [PROVOST]}"
P="${2:-$(cd "$(dirname "$0")/../.." && pwd)/provost}"
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT
export PROVOST_WORKSPACE="$D/.store" PROVOST_ASYNC=0
mkdir -p "$D/in"
for i in $(seq 1 "$N"); do
    printf '#%% host=h%05d\nName,Load,Mem\nh%05d,0.%d,%d\n' "$i" "$i" "$((i % 10))" "$((i * 7))" > "$D/in/h$i.txt"
done
printf 'a,b\n1,2\n' | "$P" --name warm >/dev/null 2>&1          # make the store first
( while :; do [[ -d "$PROVOST_WORKSPACE/.lock" ]] && date +%s.%N; sleep 0.005; done ) > "$D/polls" &
poller=$!
t0="$(date +%s.%N)"
"$P" batch --context-columns --name load "$D"/in/*.txt > "$D/out" 2>&1 || { cat "$D/out" >&2; kill "$poller"; exit 1; }
t1="$(date +%s.%N)"
kill "$poller"; wait "$poller" 2>/dev/null
awk -v n="$N" -v t0="$t0" -v t1="$t1" -v a="$(head -n 1 "$D/polls")" -v b="$(tail -n 1 "$D/polls")" 'BEGIN {
    printf "N=%d total=%.2fs lock_held=%.2fs per_input=%.1fms\n", n, t1 - t0, b - a, 1000 * (b - a) / n }'
