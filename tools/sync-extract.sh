#!/usr/bin/env bash
#
# sync-extract.sh — vendor the extract engine into glean/lib/extract/ from the
# canonical EnvoyExtract source.
#
# During the migration (proposal 0001, Phases 2–4) EnvoyExtract remains the
# source of truth for the engine + strategies. glean vendors a copy so it is
# self-contained and runnable, and this script refreshes that copy on demand:
#
#     bash glean/tools/sync-extract.sh                 # from repo's EnvoyExtract/
#     ENVOY_EXTRACT_SRC=/path/to/EnvoyExtract bash glean/tools/sync-extract.sh
#     bash glean/tools/sync-extract.sh --runtime-only  # skip tests/ + samples/
#
# After the Phase-5 hard cut, EnvoyExtract is deleted and glean/lib/extract/
# becomes canonical; this script is retired at that point.
#
# It writes glean/lib/extract/VENDOR.json recording the source git SHA and file
# counts so drift between the vendored copy and upstream is visible.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLEAN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$GLEAN_DIR/lib/extract"

# Components copied from the source. Order matters only for reporting.
RUNTIME=(envoy-extract lib strategies)
TESTDATA=(samples tests)

runtime_only=0
[[ "${1:-}" == "--runtime-only" ]] && runtime_only=1

# --- Resolve the EnvoyExtract source -------------------------------------
resolve_src () {
    if [[ -n "${ENVOY_EXTRACT_SRC:-}" ]]; then
        [[ -f "$ENVOY_EXTRACT_SRC/envoy-extract" ]] || {
            echo "error: ENVOY_EXTRACT_SRC=$ENVOY_EXTRACT_SRC has no envoy-extract" >&2; exit 1; }
        (cd "$ENVOY_EXTRACT_SRC" && pwd); return
    fi
    # Walk up from this script looking for a sibling EnvoyExtract/.
    local here="$GLEAN_DIR"
    while [[ "$here" != "/" ]]; do
        if [[ -f "$here/EnvoyExtract/envoy-extract" ]]; then
            printf '%s\n' "$here/EnvoyExtract"; return
        fi
        here="$(dirname "$here")"
    done
    echo "error: could not locate EnvoyExtract/ — set ENVOY_EXTRACT_SRC." >&2
    exit 1
}

SRC="$(resolve_src)"
echo "sync-extract: source = $SRC"
echo "sync-extract: dest   = $DEST"

components=("${RUNTIME[@]}")
[[ $runtime_only -eq 0 ]] && components+=("${TESTDATA[@]}")

mkdir -p "$DEST"
for c in "${components[@]}"; do
    if [[ ! -e "$SRC/$c" ]]; then
        echo "  skip $c (not in source)"; continue
    fi
    # Deterministic refresh: drop the old copy, copy fresh (preserves mode bits).
    rm -rf "${DEST:?}/$c"
    cp -R "$SRC/$c" "$DEST/$c"
    if [[ -d "$DEST/$c" ]]; then
        n=$(find "$DEST/$c" -type f | wc -l | tr -d ' ')
    else
        n=1
    fi
    printf '  copied %-12s %5s file(s)\n' "$c" "$n"
done
chmod +x "$DEST/envoy-extract" 2>/dev/null || true

# --- Write the vendor manifest -------------------------------------------
src_sha="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || echo unknown)"
src_desc="$(git -C "$SRC" describe --tags --always --dirty 2>/dev/null || echo unknown)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
strat_n=$(find "$DEST/strategies" -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
total_n=$(find "$DEST" -type f 2>/dev/null | wc -l | tr -d ' ')

cat > "$DEST/VENDOR.json" <<EOF
{
  "vendored_from": "EnvoyExtract",
  "source_git_sha": "$src_sha",
  "source_git_describe": "$src_desc",
  "synced_at": "$now",
  "runtime_only": $([[ $runtime_only -eq 1 ]] && echo true || echo false),
  "components": [$(printf '"%s",' "${components[@]}" | sed 's/,$//')],
  "strategy_count": $strat_n,
  "file_count": $total_n,
  "note": "Regenerate with: bash glean/tools/sync-extract.sh. Do not hand-edit vendored files; edit upstream in EnvoyExtract/ and re-sync until the Phase-5 hard cut."
}
EOF

echo "sync-extract: wrote $DEST/VENDOR.json (source $src_desc, $strat_n strategies, $total_n files)"
