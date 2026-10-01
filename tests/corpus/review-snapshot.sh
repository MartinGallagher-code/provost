#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# Regenerate tests/corpus/review-output/: one tidy TSV per corpus input, made by
# the extract engine in --generic mode (the same mode as expected/) followed by
# the tidy melt. It is a REVIEW snapshot for prescreen.py and manual review, not
# the golden set -- tests/corpus/expected/ stays the CI-enforced goldens.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 2

out=tests/corpus/review-output
mkdir -p "$out"
# shellcheck source=/dev/null
source transform/melt.sh

for f in tests/corpus/inputs/*.txt; do
    name="$(basename "$f" .txt)"
    wide="$(bash extract/envoy-extract --generic --emit-meta -f tsv --max-strategies 1 "$f" 2>/dev/null)"
    _core_melt_tidy "$wide" > "$out/$name.tsv"
done
echo "review snapshot: $(find "$out" -name '*.tsv' | wc -l) files in $out"
