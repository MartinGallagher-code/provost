#!/usr/bin/env bash
#
# sync-extract.sh — vendor the extract engine into glean/ from the canonical
# EnvoyExtract source.
#
# During the migration (proposal 0001, Phases 2–4) EnvoyExtract remains the
# source of truth for the engine + strategies. glean vendors a copy so it is
# self-contained and runnable, and this script refreshes that copy on demand:
#
#     bash glean/tools/sync-extract.sh                 # from repo's EnvoyExtract/
#     ENVOY_EXTRACT_SRC=/path/to/EnvoyExtract bash glean/tools/sync-extract.sh
#     bash glean/tools/sync-extract.sh --runtime-only  # skip tests/ + samples/
#
# Layout produced (mirrors how the engine resolves paths upstream — the engine
# dir has a sibling lib/ of cross-suite shared libraries):
#
#     glean/extract/     envoy-extract, lib/, strategies/, samples/, tests/, tools/
#     glean/lib/         shared suite libs (envoy_*.sh) the engine sources via ../lib
#
# In this standalone repo glean/extract/ is canonical; this script re-vendors
# upstream changes when pointed at an EnvoyExtract checkout (ENVOY_EXTRACT_SRC).
#
# Writes glean/extract/VENDOR.json recording the source git SHA and file counts
# so drift between the vendored copy and upstream is visible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLEAN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_DEST="$GLEAN_DIR/extract"       # engine root; its ../lib is $GLEAN_DIR/lib
SHARED_DEST="$GLEAN_DIR/lib"           # cross-suite shared libs (envoy_*.sh)

# Engine components copied from EnvoyExtract/.
RUNTIME=(envoy-extract lib strategies tools)
TESTDATA=(samples tests)

runtime_only=0
[[ "${1:-}" == "--runtime-only" ]] && runtime_only=1

# --- Resolve the EnvoyExtract source and the shared-lib source ------------
resolve_repo_root () {
    # The dir that contains both EnvoyExtract/ and the shared lib/.
    if [[ -n "${ENVOY_EXTRACT_SRC:-}" ]]; then
        (cd "$ENVOY_EXTRACT_SRC/.." && pwd); return
    fi
    local here="$GLEAN_DIR"
    while [[ "$here" != "/" ]]; do
        if [[ -f "$here/EnvoyExtract/envoy-extract" ]]; then printf '%s\n' "$here"; return; fi
        here="$(dirname "$here")"
    done
    echo "error: could not locate EnvoyExtract/ — set ENVOY_EXTRACT_SRC." >&2
    exit 1
}

REPO_ROOT="$(resolve_repo_root)"
SRC="${ENVOY_EXTRACT_SRC:-$REPO_ROOT/EnvoyExtract}"
SHARED_SRC="$REPO_ROOT/lib"
[[ -f "$SRC/envoy-extract" ]] || { echo "error: $SRC has no envoy-extract" >&2; exit 1; }

echo "sync-extract: engine source = $SRC"
echo "sync-extract: shared source = $SHARED_SRC"
echo "sync-extract: engine dest   = $ENGINE_DEST"
echo "sync-extract: shared dest   = $SHARED_DEST"

components=("${RUNTIME[@]}")
[[ $runtime_only -eq 0 ]] && components+=("${TESTDATA[@]}")

# --- Copy engine components ----------------------------------------------
mkdir -p "$ENGINE_DEST"
for c in "${components[@]}"; do
    if [[ ! -e "$SRC/$c" ]]; then echo "  skip $c (not in source)"; continue; fi
    rm -rf "${ENGINE_DEST:?}/$c"
    cp -R "$SRC/$c" "$ENGINE_DEST/$c"
    if [[ -d "$ENGINE_DEST/$c" ]]; then n=$(find "$ENGINE_DEST/$c" -type f | wc -l | tr -d ' '); else n=1; fi
    printf '  engine %-12s %5s file(s)\n' "$c" "$n"
done
chmod +x "$ENGINE_DEST/envoy-extract" 2>/dev/null || true

# --- Copy the cross-suite shared libs the engine sources via ../lib -------
# Only the *.sh (and exit codes); the shared lib's own tests/ are not needed.
mkdir -p "$SHARED_DEST"
shopt -s nullglob
shared_n=0
for f in "$SHARED_SRC"/*.sh; do
    cp "$f" "$SHARED_DEST/"; shared_n=$((shared_n+1))
done
printf '  shared %-12s %5s file(s)\n' "lib/*.sh" "$shared_n"

# --- Write the vendor manifest -------------------------------------------
src_sha="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
src_desc="$(git -C "$SRC" describe --tags --always --dirty 2>/dev/null || echo unknown)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
strat_n=$(find "$ENGINE_DEST/strategies" -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
total_n=$(( $(find "$ENGINE_DEST" -type f 2>/dev/null | wc -l) + shared_n ))

cat > "$ENGINE_DEST/VENDOR.json" <<EOF
{
  "vendored_from": "EnvoyExtract",
  "source_git_sha": "$src_sha",
  "source_git_describe": "$src_desc",
  "synced_at": "$now",
  "runtime_only": $([[ $runtime_only -eq 1 ]] && echo true || echo false),
  "engine_components": [$(printf '"%s",' "${components[@]}" | sed 's/,$//')],
  "shared_libs": $shared_n,
  "strategy_count": $strat_n,
  "file_count": $total_n,
  "layout": "engine at glean/extract/, shared libs at glean/lib/ (engine's ../lib)",
  "note": "Regenerate with: bash glean/tools/sync-extract.sh. Do not hand-edit vendored files; edit upstream in EnvoyExtract/ (or repo lib/) and re-sync."
}
EOF

echo "sync-extract: wrote $ENGINE_DEST/VENDOR.json (source $src_desc, $strat_n strategies, $total_n files + $shared_n shared libs)"
