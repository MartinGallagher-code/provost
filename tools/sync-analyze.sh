#!/usr/bin/env bash
#
# sync-analyze.sh — vendor the analyze engine into glean/analyze/ from the
# canonical EnvoyAnalyze source (companion to sync-extract.sh).
#
#     bash glean/tools/sync-analyze.sh
#     ENVOY_ANALYZE_SRC=/path/to/EnvoyAnalyze bash glean/tools/sync-analyze.sh
#     bash glean/tools/sync-analyze.sh --runtime-only   # skip tests/ + samples/
#
# The analyze engine sources the same cross-suite shared libs (envoy_*.sh) via
# its ../lib as the extract engine, so it reuses the vendored glean/lib/ (which
# this script also refreshes). Layout produced:
#
#     glean/analyze/   envoy-analyze, lib/, profiles/, samples/, tests/
#     glean/lib/       shared suite libs (also maintained by sync-extract.sh)
#
# The big pipeline/ dir and the browse/dashboard tools are intentionally NOT
# vendored — glean only needs the analyze engine (its completions/schemas/docs
# ARE vendored so the engine test suite passes).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLEAN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_DEST="$GLEAN_DIR/analyze"
SHARED_DEST="$GLEAN_DIR/lib"

RUNTIME=(envoy-analyze lib profiles schemas completions docs)
TESTDATA=(samples tests)
runtime_only=0
[[ "${1:-}" == "--runtime-only" ]] && runtime_only=1

resolve_repo_root () {
    if [[ -n "${ENVOY_ANALYZE_SRC:-}" ]]; then (cd "$ENVOY_ANALYZE_SRC/.." && pwd); return; fi
    local here="$GLEAN_DIR"
    while [[ "$here" != "/" ]]; do
        [[ -f "$here/EnvoyAnalyze/envoy-analyze" ]] && { printf '%s\n' "$here"; return; }
        here="$(dirname "$here")"
    done
    echo "error: could not locate EnvoyAnalyze/ — set ENVOY_ANALYZE_SRC." >&2; exit 1
}

REPO_ROOT="$(resolve_repo_root)"
SRC="${ENVOY_ANALYZE_SRC:-$REPO_ROOT/EnvoyAnalyze}"
SHARED_SRC="$REPO_ROOT/lib"
[[ -f "$SRC/envoy-analyze" ]] || { echo "error: $SRC has no envoy-analyze" >&2; exit 1; }

echo "sync-analyze: engine source = $SRC"
echo "sync-analyze: engine dest   = $ENGINE_DEST"

components=("${RUNTIME[@]}")
[[ $runtime_only -eq 0 ]] && components+=("${TESTDATA[@]}")

mkdir -p "$ENGINE_DEST"
for c in "${components[@]}"; do
    [[ -e "$SRC/$c" ]] || { echo "  skip $c (not in source)"; continue; }
    rm -rf "${ENGINE_DEST:?}/$c"
    cp -R "$SRC/$c" "$ENGINE_DEST/$c"
    if [[ -d "$ENGINE_DEST/$c" ]]; then n=$(find "$ENGINE_DEST/$c" -type f | wc -l | tr -d ' '); else n=1; fi
    printf '  engine %-12s %5s file(s)\n' "$c" "$n"
done
chmod +x "$ENGINE_DEST/envoy-analyze" 2>/dev/null || true

# Refresh shared libs (idempotent with sync-extract.sh — same source/dest).
mkdir -p "$SHARED_DEST"; shopt -s nullglob; shared_n=0
for f in "$SHARED_SRC"/*.sh; do cp "$f" "$SHARED_DEST/"; shared_n=$((shared_n+1)); done
printf '  shared %-12s %5s file(s)\n' "lib/*.sh" "$shared_n"

src_sha="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
src_desc="$(git -C "$SRC" describe --tags --always --dirty 2>/dev/null || echo unknown)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
total_n=$(( $(find "$ENGINE_DEST" -type f 2>/dev/null | wc -l) + shared_n ))

cat > "$ENGINE_DEST/VENDOR.json" <<EOF
{
  "vendored_from": "EnvoyAnalyze",
  "source_git_sha": "$src_sha",
  "source_git_describe": "$src_desc",
  "synced_at": "$now",
  "runtime_only": $([[ $runtime_only -eq 1 ]] && echo true || echo false),
  "engine_components": [$(printf '"%s",' "${components[@]}" | sed 's/,$//')],
  "shared_libs": $shared_n,
  "file_count": $total_n,
  "note": "Regenerate with: bash glean/tools/sync-analyze.sh. Do not hand-edit; edit upstream in EnvoyAnalyze/ (or repo lib/) and re-sync."
}
EOF
echo "sync-analyze: wrote $ENGINE_DEST/VENDOR.json (source $src_desc, $total_n files + $shared_n shared)"
