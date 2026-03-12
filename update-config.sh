#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

copy_if_exists() {
  local src="$1"
  local dest="$2"
  if [[ -e "$src" ]]; then
    cp "$src" "$dest"
    echo "  updated $dest"
  else
    echo "  skipped $dest (not found: $src)"
  fi
}

echo "Updating config backups from local machine..."
echo ""

copy_if_exists "$HOME/.config/ghostty/config"                       "$CONFIG_DIR/ghostty/config"
copy_if_exists "$HOME/.tmux.conf"                                    "$CONFIG_DIR/tmux/tmux.conf"
copy_if_exists "$HOME/.config/tmux/tmux-which-key.yaml"             "$CONFIG_DIR/tmux/tmux-which-key.yaml"
copy_if_exists "$HOME/.local/bin/tmux-sessionizer"                  "$CONFIG_DIR/tmux/tmux-sessionizer"
copy_if_exists "$HOME/.claude/CLAUDE.md"                            "$CONFIG_DIR/claude/CLAUDE.md"
copy_if_exists "$HOME/.claude/settings.json"                        "$CONFIG_DIR/claude/settings.json"
copy_if_exists "$HOME/.claude/ccline/config.toml"                   "$CONFIG_DIR/claude/ccline/config.toml"
copy_if_exists "$HOME/.claude/ccline/models.toml"                   "$CONFIG_DIR/claude/ccline/models.toml"
copy_if_exists "$HOME/.claude/ccline/themes/wt-theme.toml"          "$CONFIG_DIR/claude/ccline/themes/wt-theme.toml"

echo ""
git -C "$SCRIPT_DIR" diff --stat config/ || true
