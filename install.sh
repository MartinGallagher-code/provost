#!/usr/bin/env bash
#
# install.sh — put `glean` on your PATH.
#
#   bash glean/install.sh                 # symlink into ~/.local/bin
#   PREFIX=/usr/local bash glean/install.sh   # install under /usr/local
#   bash glean/install.sh --uninstall
#
# glean runs in place from this tree (it resolves its bundled extract/analyze/
# transform relative to the script), so "install" just creates a launcher on
# PATH and drops the bash completion + man page. Nothing is copied out of tree.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN="$PREFIX/bin"
COMPDIR="${BASH_COMPLETION_DIR:-$PREFIX/share/bash-completion/completions}"
MANDIR="$PREFIX/share/man/man1"

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$BIN/glean" "$COMPDIR/glean" "$MANDIR/glean.1"
    echo "uninstalled glean launcher, completion, and man page from $PREFIX"
    exit 0
fi

mkdir -p "$BIN" "$COMPDIR" "$MANDIR"
ln -sf "$SCRIPT_DIR/glean" "$BIN/glean"
cp -f "$SCRIPT_DIR/completions/glean.bash" "$COMPDIR/glean"
cp -f "$SCRIPT_DIR/man/glean.1" "$MANDIR/glean.1"

echo "installed:"
echo "  launcher   : $BIN/glean -> $SCRIPT_DIR/glean"
echo "  completion : $COMPDIR/glean"
echo "  man page   : $MANDIR/glean.1"
case ":$PATH:" in
    *":$BIN:"*) ;;
    *) echo; echo "note: $BIN is not on your PATH — add it:"; echo "  export PATH=\"$BIN:\$PATH\"" ;;
esac
echo
echo "verify with:  glean doctor"
