# config/

Backups of local machine config files for the Ghostty + tmux + Claude Code workflow that `wt` is built for.

To update these from your local machine, run from the repo root:

```bash
./update-config.sh
```

## Files

| File | Local path | Purpose |
|---|---|---|
| `ghostty/config` | `~/.config/ghostty/config` | Terminal settings |
| `tmux/tmux.conf` | `~/.tmux.conf` | Full tmux config (prefix, theme, status bar, sessionizer) |
| `tmux/tmux-which-key.yaml` | `~/.config/tmux/tmux-which-key.yaml` | tmux-which-key plugin config |
| `tmux/tmux-sessionizer` | `~/.local/bin/tmux-sessionizer` | Fuzzy session switcher (`Ctrl+a f`) |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Global Claude Code instructions |
| `claude/settings.json` | `~/.claude/settings.json` | Claude Code settings: hooks, status line, model |
| `claude/ccline/` | `~/.claude/ccline/` | ccline status bar config and theme |
| `shell-functions.zsh` | sourced from `~/.zshrc` | `wt()` and `claude()` shell wrappers |

`shell-functions.zsh` is sourced directly from the repo — no backup needed.

See `docs/SETUP.md` for the full workflow walkthrough and installation steps.
