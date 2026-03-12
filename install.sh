#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="${PREFIX}/bin"

INSTALL_CONFIG=false
if [[ "${1:-}" == "--config" ]]; then
  INSTALL_CONFIG=true
fi

# ── wt binary ────────────────────────────────────────────────────────────────

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

if [[ "$INSTALL_CONFIG" == false ]]; then
  echo ""
  echo "Tip: run './install.sh --config' to also install the full Ghostty + tmux + Claude Code workflow config."
  exit 0
fi

# ── workflow config ───────────────────────────────────────────────────────────

echo ""
echo "Installing workflow config..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

backup_and_copy() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" ]]; then
    cp "$dest" "${dest}.bak"
    echo "  Backed up $dest → ${dest}.bak"
  fi
  cp "$src" "$dest"
  echo "  Installed $dest"
}

backup_and_copy "$CONFIG_DIR/ghostty/config"              "$HOME/.config/ghostty/config"
backup_and_copy "$CONFIG_DIR/tmux/tmux.conf"              "$HOME/.tmux.conf"
backup_and_copy "$CONFIG_DIR/tmux/tmux-which-key.yaml"    "$HOME/.config/tmux/tmux-which-key.yaml"
backup_and_copy "$CONFIG_DIR/tmux/tmux-sessionizer"       "$BIN_DIR/tmux-sessionizer"
chmod +x "$BIN_DIR/tmux-sessionizer"
backup_and_copy "$CONFIG_DIR/claude/CLAUDE.md"            "$HOME/.claude/CLAUDE.md"
backup_and_copy "$CONFIG_DIR/claude/settings.json"        "$HOME/.claude/settings.json"
backup_and_copy "$CONFIG_DIR/claude/ccline/config.toml"   "$HOME/.claude/ccline/config.toml"
backup_and_copy "$CONFIG_DIR/claude/ccline/models.toml"   "$HOME/.claude/ccline/models.toml"
backup_and_copy "$CONFIG_DIR/claude/ccline/themes/guido-theme.toml" \
                "$HOME/.claude/ccline/themes/guido-theme.toml"

echo ""
echo "Shell functions — add to ~/.zshrc or ~/.bashrc:"
echo ""
echo "  source $SCRIPT_DIR/config/shell-functions.zsh"
echo "  export WT_SEARCH_PATHS=~/your/projects:~/your/other/projects"
echo ""
echo "Next steps:"
echo "  1. Customize the search paths in config/tmux/tmux-sessionizer (lines 8-9)"
echo "  2. Install tmux plugins:"
echo "       git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
echo "       mkdir -p ~/.config/tmux/plugins"
echo "       git clone https://github.com/catppuccin/tmux ~/.config/tmux/plugins/catppuccin/tmux"
echo "       # Then inside tmux: Ctrl+a I"
echo "  3. Install ccline — see docs/SETUP.md for the download link"
echo "  4. See docs/SETUP.md for the full workflow walkthrough"
