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
ln -sf "$SCRIPT_DIR/config/wt-completion.zsh" "$BIN_DIR/wt-completion.zsh"

echo "Installed wt → $BIN_DIR/wt (symlink)"
echo "Installed wt-completion.zsh → $BIN_DIR/wt-completion.zsh (symlink)"

# Warn if bash version is too old
if (( BASH_VERSINFO[0] < 4 )); then
  echo ""
  echo "WARNING: wt requires bash 4+. Current bash: ${BASH_VERSION}"
  echo "macOS: brew install bash"
fi
echo ""
echo "Make sure $BIN_DIR is on your PATH:"
echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
echo "Add the shell wrapper to your shell rc file (~/.zshrc or ~/.bashrc):"
echo ""
echo "  source ~/shell-functions.zsh"
echo ""
echo "Optional: enable tab completion in zsh."
echo "Add this near the end of ~/.zshrc, after your framework or compinit:"
echo ""
echo "  source $BIN_DIR/wt-completion.zsh"
echo ""
echo "  (Oh My Zsh: add after 'source \$ZSH/oh-my-zsh.sh')"
echo ""
echo "Projects are registered automatically when you run 'wt new'."
echo "Registry: \${XDG_CONFIG_HOME:-~/.config}/wt/projects"
echo ""
echo "Workflow config (Ghostty, tmux, Claude Code):"
echo "  See https://github.com/GuidoSantillanID/cockpit for full setup."
