#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${PREFIX}/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$BIN_DIR"

# Remove old copy if present, then symlink
if [[ -f "$BIN_DIR/wt" && ! -L "$BIN_DIR/wt" ]]; then
  rm "$BIN_DIR/wt"
fi
ln -sf "$SCRIPT_DIR/bin/wt" "$BIN_DIR/wt"

echo "Installed wt → $BIN_DIR/wt (symlink)"
echo ""
echo "Make sure $BIN_DIR is on your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "Add the shell wrapper to your shell rc file (~/.zshrc or ~/.bashrc):"
echo ""
echo "  source ~/shell-functions.zsh"
echo "  export WT_SEARCH_PATHS=~/your/projects:~/your/other/projects"
echo ""
echo "Workflow config (Ghostty, tmux, Claude Code):"
echo "  See https://github.com/GuidoSantillanID/cockpit for full setup."
