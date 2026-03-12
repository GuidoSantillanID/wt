#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${PREFIX}/bin"

mkdir -p "$BIN_DIR"
cp bin/wt "$BIN_DIR/wt"
chmod +x "$BIN_DIR/wt"

echo "Installed wt to $BIN_DIR/wt"
echo ""
echo "Make sure $BIN_DIR is on your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "Add the shell wrapper to your shell rc file (~/.zshrc or ~/.bashrc):"
echo ""
echo '  function wt() {'
echo '    if [[ "$1" == "new" || "$1" == "finish" || "$1" == "done" || "$1" == "drop" ]]; then'
echo '      local dir'
echo '      dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"'
echo '    else'
echo '      command wt "$@"'
echo '    fi'
echo '  }'
echo ""
echo "Configure search paths (optional):"
echo "  export WT_SEARCH_PATHS=~/src:~/projects"
echo "Or create ~/.config/wt/config with one directory per line."
