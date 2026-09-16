#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

# CI: bundle.txt must be a faithful snapshot of the tracked tree.
#
# Two failure modes, both invisible to `git status` and both of which have
# actually shipped:
#
#   STALE LIST  merge.sh is not rerun after a merge adds files, so the bundle
#               is missing them.
#   JUNK        merge.sh bundles the WORKING TREE, not `git ls-files`, so any
#               untracked-but-present build artifact (.coverage, .pytest_cache/,
#               __pycache__/*.pyc) gets swept in — gitignored, so nothing else
#               reports it.
#
# A third mode is subtler and a file-list comparison alone will NOT catch it:
#
#   STALE CONTENT  a tracked file is EDITED after the bundle is generated. The
#                  file list still matches perfectly; only the bytes differ.
#
# So this checks both the list and the content. merge.sh records a sha256 per
# entry in its ===META: line, which makes the content check cheap: hash each
# tracked file and compare against what the bundle recorded, with no need to
# expand the bundle.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

[ -f bundle.txt ] || { echo "bundle.txt not found"; exit 2; }

bundled=$(mktemp); tracked=$(mktemp); recorded=$(mktemp); actual=$(mktemp)
trap 'rm -f "$bundled" "$tracked" "$recorded" "$actual"' EXIT

# Section headers are ===FILE:, ===FILE-ESC: or ===FILE-B64: followed by the
# path and a trailing ===; the ===META: line that follows carries the sha256.
# (DIR/LINK sections are not git-tracked files: git stores no empty
# directories, and this repo has no symlinks.)
awk '
    /^===FILE/ {
        path = $0
        sub(/^===FILE[^:]*: /, "", path)
        sub(/===$/, "", path)
        next
    }
    /^===META:/ && path != "" {
        if (match($0, /sha256=[0-9a-f]+/)) {
            sha = substr($0, RSTART + 7, RLENGTH - 7)
            print sha "  " path
        }
        path = ""
    }
' bundle.txt | LC_ALL=C sort -k2 > "$recorded"

sed 's/^[0-9a-f]*  //' "$recorded" | LC_ALL=C sort > "$bundled"
git ls-files | grep -v '^bundle.txt$' | LC_ALL=C sort > "$tracked"

rc=0

# ---- 1. the file list ----------------------------------------------------
missing=$(comm -13 "$bundled" "$tracked")
extra=$(comm -23 "$bundled" "$tracked")

if [ -n "$missing" ]; then
    rc=1
    echo "STALE — tracked but NOT in the bundle ($(printf '%s\n' "$missing" | wc -l)):"
    printf '%s\n' "$missing" | sed 's/^/    /' | head -20
    [ "$(printf '%s\n' "$missing" | wc -l)" -gt 20 ] && echo "    ... and more"
    echo
fi

if [ -n "$extra" ]; then
    rc=1
    echo "JUNK — in the bundle but NOT tracked by git ($(printf '%s\n' "$extra" | wc -l)):"
    printf '%s\n' "$extra" | sed 's/^/    /' | head -20
    [ "$(printf '%s\n' "$extra" | wc -l)" -gt 20 ] && echo "    ... and more"
    echo "  Untracked files present in the working tree when merge.sh ran."
    echo "  They are gitignored, so 'git status' looks clean."
    echo
fi

# ---- 2. the content ------------------------------------------------------
# Only meaningful for files present on both sides; list problems are already
# reported above.
if [ -z "$missing" ] && [ -z "$extra" ]; then
    # sha256sum --check would abort on the first missing file; hashing the
    # tracked set directly and diffing is simpler and reports every drift.
    LC_ALL=C sort "$tracked" | tr '\n' '\0' \
        | xargs -0 sha256sum 2>/dev/null \
        | sed 's|  \./|  |' | LC_ALL=C sort -k2 > "$actual"

    drift=$(comm -13 <(LC_ALL=C sort "$recorded") <(LC_ALL=C sort "$actual") \
            | sed 's/^[0-9a-f]*  //' | LC_ALL=C sort -u)

    if [ -n "$drift" ]; then
        rc=1
        echo "STALE CONTENT — bundled copy differs from the working tree ($(printf '%s\n' "$drift" | wc -l)):"
        printf '%s\n' "$drift" | sed 's/^/    /' | head -20
        [ "$(printf '%s\n' "$drift" | wc -l)" -gt 20 ] && echo "    ... and more"
        echo "  The file list matches, so only the CONTENT is out of date —"
        echo "  these files were edited after the bundle was generated."
        echo
    fi
fi

if [ $rc -eq 0 ]; then
    echo "bundle.txt is current: $(wc -l < "$tracked") tracked file(s), list and content both match."
    exit 0
fi

cat <<'EOF'
To fix, from a CLEAN tree:
    git clean -Xdn          # review gitignored junk first
    git clean -Xdf          # remove it
    bash ../shared_tools/scripts/merge.sh bundle.txt .
    bash tests/check-bundle-current.sh
EOF
exit 1
