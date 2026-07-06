#!/usr/bin/env bash
#
# sync-melt.sh — import the extract-output TRANSFORM (tidy melt + schema union)
# into glean/transform/melt.sh from the canonical EnvoyCapture source.
#
#     bash glean/tools/sync-melt.sh
#     ENVOY_CAPTURE_SRC=/path/to/EnvoyCapture bash glean/tools/sync-melt.sh
#
# The transform that reshapes a wide `entry<N>.<field>` extract into a tidy
# one-row-per-record table (`_core_melt_tidy`) — plus the schema-union helpers it
# travels with (`_core_union_header`, `_core_align_rows`) — lives inside
# EnvoyCapture's lib/_core.sh. glean's presenter needs exactly these functions
# and nothing else from that 900-line file, so this script extracts just that
# self-contained block (all pure awk, no capture/git dependencies) into a
# standalone sourceable module. Companion to sync-extract.sh / sync-analyze.sh.
#
# Retired at the Phase-5 hard cut, when glean/transform/ becomes canonical.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLEAN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="$GLEAN_DIR/transform"
DEST="$DEST_DIR/melt.sh"

resolve_src () {
    if [[ -n "${ENVOY_CAPTURE_SRC:-}" ]]; then printf '%s\n' "$ENVOY_CAPTURE_SRC/lib/_core.sh"; return; fi
    local here="$GLEAN_DIR"
    while [[ "$here" != "/" ]]; do
        [[ -f "$here/EnvoyCapture/lib/_core.sh" ]] && { printf '%s\n' "$here/EnvoyCapture/lib/_core.sh"; return; }
        here="$(dirname "$here")"
    done
    echo "error: could not locate EnvoyCapture/lib/_core.sh — set ENVOY_CAPTURE_SRC." >&2; exit 1
}

SRC="$(resolve_src)"
[[ -f "$SRC" ]] || { echo "error: no such file: $SRC" >&2; exit 1; }
mkdir -p "$DEST_DIR"

# Extract from the "_core_union_header" block through the end of "_core_melt_tidy"
# (i.e. up to but excluding the "_core_dataset_append" comment, which is coupled
# to the git store and is NOT part of the transform).
body="$(awk '/^# Union of two TSV header lines/{f=1} /^# Append a TSV row to a dataset/{f=0} f' "$SRC")"
fn_count="$(printf '%s\n' "$body" | grep -cE '^_core_[a-z_]+ \(\)')"
[[ "$fn_count" -ge 3 ]] || { echo "error: expected >=3 transform functions, found $fn_count — upstream layout changed?" >&2; exit 1; }

src_sha="$(git -C "$(dirname "$SRC")" rev-parse HEAD 2>/dev/null || echo unknown)"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
    echo "#!/usr/bin/env bash"
    echo "# glean/transform/melt.sh — VENDORED, do not hand-edit."
    echo "#"
    echo "# The extract-output transform (tidy melt + schema-union helpers), imported"
    echo "# verbatim from EnvoyCapture/lib/_core.sh by glean/tools/sync-melt.sh."
    echo "# Functions: _core_melt_tidy, _core_union_header, _core_align_rows."
    echo "# Source: EnvoyCapture/lib/_core.sh @ $src_sha  (synced $now)"
    echo "# Re-import with: bash glean/tools/sync-melt.sh"
    echo ""
    printf '%s\n' "$body"
} > "$DEST"

echo "sync-melt: wrote $DEST ($fn_count functions, source @ $src_sha)"
