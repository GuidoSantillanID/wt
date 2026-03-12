# Workflow Setup — Ghostty + tmux + Claude Code

A complete guide to the terminal workflow `wt` was designed for. Everything here is optional — `wt` works standalone — but if you use Claude Code heavily, this stack makes parallel multi-task development significantly smoother.

---

## Overview: how the pieces connect

```
Ghostty (terminal)
  └── tmux (session manager)
        ├── session: myapp                  ← main checkout
        ├── session: myapp/add-dark-mode    ← worktree (wt new)
        └── session: myapp/fix-login-bug    ← worktree (wt new)
              └── Claude Code (claude)
```

**Key integration points:**

| Event | Mechanism | Visual result |
|---|---|---|
| Claude Code finishes a task | Stop hook sets `@claude_done` on the tmux window | Green `●` appears in the window tab |
| You switch to that window | tmux hook clears `@claude_done` | Green `●` disappears |
| `claude` command starts | `claude()` wrapper sets `@is_claude_running` | choose-tree shows live pane title |
| `claude` command exits | `claude()` wrapper unsets `@is_claude_running` | choose-tree reverts to window name |
| `wt new` creates a worktree | tmux-sessionizer scans `.worktrees/` | New session auto-appears in `Ctrl+a f` |
| `wt finish` or `wt drop` | `wt` kills the tmux session named `project/slug` | Session disappears from list |

---

## Ghostty

Config file: `~/.config/ghostty/config` (see `config/ghostty/config`)

```
term = xterm=256color
copy-on-select = true
```

- `term = xterm=256color` — sets `$TERM` so inner apps (tmux, editors) get 256-color support
- `copy-on-select = true` — text selected with the mouse is automatically copied to clipboard

**Ghostty + tmux color note:** The tmux config includes `set -ag terminal-overrides ",xterm-ghostty:RGB"`. This tells tmux that when Ghostty is the outer terminal, true color (24-bit RGB) is supported. Without this, 24-bit colors get downsampled to 256.

---

## tmux

Config file: `~/.tmux.conf` (see `config/tmux/tmux.conf`)

### Indexing

```
set -g base-index 1
set -g pane-base-index 1
set-window-option -g pane-base-index 1
set-option -g renumber-windows on
```

Windows and panes start at 1 instead of 0 — more natural to reach with the keyboard. `renumber-windows` keeps window numbers gapless when you close one (e.g. closing window 2 of 3 renumbers window 3 → 2).

---

### Theme & Color

```
set -g @catppuccin_flavor 'mocha'
set -g @catppuccin_window_status_style 'none'
set -g default-terminal "xterm-256color"
set -ag terminal-overrides ",xterm-ghostty:RGB"
```

Catppuccin Mocha is manually installed at `~/.config/tmux/plugins/catppuccin/` (not via TPM) so it can be loaded earlier in the config, before TPM runs. `window_status_style 'none'` disables catppuccin's built-in window status rendering so the custom `window-status-format` takes over.

`default-terminal` sets the `$TERM` tmux reports to inner applications. `terminal-overrides` tells tmux that when the outer terminal is `xterm-ghostty` (Ghostty), it supports true color (RGB) — without this, 24-bit colors would be downsampled.

**Catppuccin variables in styles:** catppuccin exposes variables like `@thm_teal`, `@thm_peach`, etc. These resolve correctly inside format strings (`status-right`, `window-status-format`, `choose-tree -F`) using `#{@thm_x}` syntax. However, standalone style options (`message-style`, `mode-style`, `message-command-style`) are not format strings — they don't expand `#{}` variables, so those must use hardcoded hex values from the catppuccin mocha palette.

---

### Prefix

```
unbind C-b
set -g prefix C-a
bind C-a send-prefix
```

`Ctrl+b` is the default prefix but conflicts with shell readline (move-back-char). `Ctrl+a` is the classic screen prefix and easier to reach. `bind C-a send-prefix` lets you press `Ctrl+a Ctrl+a` to send a literal `^A` to the terminal (e.g. for readline beginning-of-line).

Note: Ghostty maps `Cmd+Left` to `^A` by default (beginning of line), so inside tmux `Cmd+Left` also triggers the prefix.

---

### Mouse

```
set -g mouse on
```

Enables mouse scrolling, pane resizing, and pane selection by click.

---

### Scrollback

```
set -g history-limit 50000
```

Default is 2000 lines, which gets exhausted quickly with verbose Claude Code output. 50k gives enough buffer to scroll back through long sessions.

---

### Status Bar

```
set -g display-time 1000
set -g status on
set -g status-position top
set -g status-left ""
set -g status-right '#{?client_prefix,#[bg=colour1 fg=colour255 bold] PREFIX #[default] ,}#[fg=#{@thm_crust},bg=#{@thm_teal}] session: #S '
set -g status-right-length 100
```

Status bar is at the top. `status-left` is empty — all info is on the right. The right side shows:
- A red `PREFIX` badge when the prefix key is active (useful visual feedback)
- Current session name in teal

`display-time` controls how long tmux messages (e.g. save/restore notifications) stay visible.

---

### Window Names

```
set -g automatic-rename on
set -g automatic-rename-format '#{b:pane_current_path}#{?#{==:#{pane_current_command},zsh},, (#{s/^[0-9][.0-9]*$/claude/:pane_current_command})}'
set -g allow-rename off
```

Window names auto-update based on the current pane. The format:
- `#{b:pane_current_path}` — shows the directory basename (e.g. `instadeep-ui`)
- If the command is `zsh` (plain shell), nothing extra is shown
- Otherwise, the command name is appended in parens — with a substitution: version-like strings (e.g. `5.4`) are replaced with `claude` to handle Claude Code's process name

`allow-rename off` prevents programs from overriding the window name via escape sequences (Claude Code would otherwise inject its own title).

---

### Window Status (Tab Bar)

```
set -g window-status-current-format '#[fg=#{@thm_crust},bg=#{@thm_peach},bold] #I: #W#{?@claude_done, #[fg=#{@thm_green}]●#[fg=#{@thm_crust}],} '
set -g window-status-format '#[fg=#{@thm_text},bg=#{@thm_surface0}] #I: #W#{?@claude_done, #[fg=#{@thm_green}]●,} '
```

Active window: peach background, bold. Inactive windows: muted gray. Both show a green `●` when the `@claude_done` user option is set on that window — used to signal Claude has finished a task.

---

### Splits & New Windows

```
bind c new-window -c "#{pane_current_path}"
bind v split-window -h -c "#{pane_current_path}"
bind h split-window -v -c "#{pane_current_path}"
```

All new windows and splits inherit the current pane's working directory. tmux's default opens in the directory where the session was created, which is rarely what you want.

---

### Sessionizer

```
bind f display-popup -E "tmux-sessionizer"
```

Opens a floating popup running the `tmux-sessionizer` script. Scans project directories and any `.worktrees/` inside them, and lets you fuzzy-search to create or switch sessions. Always use this instead of raw `tmux new-session` to ensure sessions are named consistently.

---

### Plugins

```
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'alexwforsythe/tmux-which-key'
set -g @tmux-which-key-xdg-open 0
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
set -g @resurrect-hook-post-save 'tmux display-message "  session saved"'
set -g @resurrect-hook-post-restore 'tmux display-message "  session restored"'
```

- **tpm** — plugin manager
- **tmux-which-key** — shows a keybinding cheatsheet on `prefix ?`. `xdg-open 0` disables xdg-open integration (not relevant on macOS)
- **tmux-resurrect** — manually save/restore sessions (`prefix Ctrl+s` / `prefix Ctrl+r`). Saves layout, window/pane structure, and working directories. Does not restore running processes.
- **tmux-continuum** — auto-saves every 15 minutes and auto-restores on reboot using resurrect under the hood

---

### Claude Done Indicator

```
set-hook -g after-select-window 'set-option -wu @claude_done'
set-hook -g client-session-changed 'set-option -wu @claude_done'
```

The `@claude_done` user option is set externally (by a Claude Code hook in `settings.json`) when Claude finishes a task. These hooks clear it automatically when you switch to that window or session, so the `●` disappears once you've seen it.

---

### Choose-tree

```
bind s choose-tree -Zs ...
bind w choose-tree -Zw ...
```

Custom session/window picker. The format string renders three types of rows differently:
- **Session rows:** teal, with window count and `(attached)` indicator
- **Window rows:** peach window name. For Claude windows, shows the live pane title (e.g. `* Claude Code`) instead of the static window name — the `*` prefix is Claude Code's own activity indicator. For non-Claude windows, shows the window name. Green `●` shown if `@claude_done` is set.
- **Pane rows:** muted gray, shows current command and pane title

---

### Load Order

```
run ~/.config/tmux/plugins/catppuccin/tmux/catppuccin.tmux
run '~/.tmux/plugins/tpm/tpm'

set -g mode-style 'bg=#6c7086 bold'
set -g message-style 'fg=#11111b bg=#94e2d5'
set -g message-command-style 'fg=#11111b bg=#94e2d5'
```

Load order matters:
1. Catppuccin is loaded first — sets `@thm_*` color variables used throughout the format strings
2. TPM runs next — loads all plugins, some of which override styles
3. `mode-style` / `message-style` / `message-command-style` are set **last** to ensure they aren't overridden by catppuccin or any plugin

These three style options use hardcoded hex (catppuccin mocha values) because style options don't expand `#{}` variables:
- `mode-style`: `#6c7086` = overlay0 (selection background in choose-tree / copy-mode)
- `message-style` / `message-command-style`: `#11111b` fg (crust) on `#94e2d5` bg (teal) — used for the `:` command prompt

---

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+a` | Prefix (also `Cmd+Left` via Ghostty default) |
| `Ctrl+a Ctrl+a` | Send literal `^A` to terminal (readline beginning-of-line) |
| `Ctrl+a v` | Vertical split (opens in current path) |
| `Ctrl+a h` | Horizontal split (opens in current path) |
| `Ctrl+a f` | Sessionizer — fuzzy search + open/switch project session |
| `Ctrl+a s` | List and switch between existing sessions |
| `Ctrl+a w` | List and switch between windows across all sessions |
| `Ctrl+a c` | New window (opens in current directory) |
| `Ctrl+a ,` | Rename window |
| `Ctrl+a 1-9` | Switch to window N (windows start at 1) |
| `Ctrl+a n / p` | Next / previous window |
| `Ctrl+a z` | Zoom pane (toggle fullscreen) |
| `Ctrl+a x` | Kill pane |
| `Ctrl+a &` | Kill window |
| `Ctrl+a d` | Detach session |
| `Ctrl+a $` | Rename session |
| `Ctrl+a [` | Scroll mode (q to exit) |
| `Ctrl+a Ctrl+s` | Save sessions (tmux-resurrect) |
| `Ctrl+a Ctrl+r` | Restore sessions (tmux-resurrect) |
| `Ctrl+a :new-session` | Create a new session |
| `Ctrl+a :kill-session` | Kill current session |

---

### Session Persistence

- **tmux-resurrect** saves session layout and working directories
- **tmux-continuum** auto-saves every 15 minutes and auto-restores on reboot
- Visual feedback shown in status bar on save/restore
- **Saved:** layout, window/pane structure, working directories
- **Not saved:** running processes (servers, Claude, etc.)

---

### Recommended window layout per session

| Window | Purpose |
|--------|---------|
| `1: claude` | Claude Code, full screen |
| `2: web` | `pnpm dev` |
| `3: test` | Test runner (watch mode) |
| `4: lint` | `tsc` / `eslint` |
| `5: git` | Git operations |

---

## Claude Code

### settings.json

Config file: `~/.claude/settings.json` (see `config/claude/settings.json`)

Key settings:

**Hooks** — these are the integration point with tmux:
```json
"Stop": [{ "command": "afplay /System/Library/Sounds/Glass.aiff" },
          { "command": "[ -n \"$TMUX\" ] && tmux set-option -w @claude_done 1 || true" }],
"Notification": [{ "command": "afplay /System/Library/Sounds/Ping.aiff" },
                  { "command": "[ -n \"$TMUX\" ] && tmux set-option -w @claude_done 1 || true" }]
```

- Plays a system sound when Claude finishes or sends a notification
- Sets `@claude_done` on the current tmux window → triggers the green `●` in the tab bar
- The `afplay` commands are **macOS-specific**. On Linux, replace with `paplay` or `aplay`.
- The tmux command is guarded by `[ -n "$TMUX" ]` so it's safe outside tmux

**Status line:** Uses `ccline` at `~/.claude/ccline/ccline` (see ccline section below).

**Other settings:**
- `autoMemoryEnabled: false` — disable automatic memory (manually control what Claude remembers)
- `skipDangerousModePermissionPrompt: true` — skip the confirmation when using `--dangerously-skip-permissions`

---

### CLAUDE.md

Config file: `~/.claude/CLAUDE.md` (see `config/claude/CLAUDE.md`)

Global instructions applied to every Claude Code session. Covers:
- Working relationship style (direct feedback, no timeline estimates)
- Thinking economy (concise internal reasoning)
- Plan mode behavior
- Commit/attribution rules
- ESLint policy
- TypeScript conventions

---

### ccline status line

Config files: `~/.claude/ccline/` (see `config/claude/ccline/`)

`ccline` is a third-party Claude Code status line binary. Install it separately — it's not in this repo.

The config (`config.toml`) shows these segments in the status bar:
- **Directory** — current working directory
- **Git** — branch name
- **Model** — active Claude model
- **Context window** — token usage gauge
- **Usage** — API usage stats (cached for 3 minutes to avoid rate-limiting)

Theme: `cometix` (ships with ccline). The `themes/guido-theme.toml` is a custom theme variant.

---

## Shell Functions

Config file: `config/shell-functions.zsh`

Source this from `~/.zshrc` or `~/.bashrc`:
```bash
source ~/Documents/dev/wt/config/shell-functions.zsh
```

Also set your project search paths:
```bash
export WT_SEARCH_PATHS=~/Documents/dev:~/Documents/lab
```

### `claude()` wrapper

Wraps the `claude` command to integrate with tmux:
1. Saves the current window name
2. Renames the window to `✳ claude`
3. Sets `@is_claude_running` on the window (read by choose-tree format)
4. Runs the actual `claude` command
5. Restores the window name and unsets `@is_claude_running` on exit

Without tmux, falls through to the bare `claude` command.

### `wt()` wrapper

Required for `wt new`, `wt finish`, and `wt drop` to automatically `cd` your shell into/out of worktrees. A subprocess can't change the parent shell's directory — this wrapper captures the path printed to stdout and calls `cd`.

### Auto-attach on terminal open

To automatically attach to tmux when opening a new Ghostty window, add to `~/.zshrc` (after sourcing shell-functions.zsh):
```bash
if [ -z "$TMUX" ]; then
  tmux a || tmux
fi
```

---

## Installation

### 1. Install wt

```bash
git clone https://github.com/GuidoSantillanID/wt.git ~/Documents/dev/wt
cd ~/Documents/dev/wt
./install.sh
```

### 2. Install full workflow config

```bash
./install.sh --config
```

This copies all configs to their destinations (backs up existing files as `*.bak` first) and prints instructions for the shell functions.

### 3. Install tmux dependencies manually

After `install.sh --config`:

```bash
# TPM (tmux plugin manager)
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Catppuccin (must be at this path — loaded before TPM in tmux.conf)
mkdir -p ~/.config/tmux/plugins
git clone https://github.com/catppuccin/tmux ~/.config/tmux/plugins/catppuccin/tmux

# Start tmux and install plugins
tmux
# Inside tmux: Ctrl+a I  (capital I = install plugins)
```

### 4. Install ccline

Download the `ccline` binary from its releases page and place it at `~/.claude/ccline/ccline`:
```bash
mkdir -p ~/.claude/ccline
# Download binary from ccline releases, then:
chmod +x ~/.claude/ccline/ccline
```

### 5. Add shell functions to your shell rc

```bash
echo 'source ~/Documents/dev/wt/config/shell-functions.zsh' >> ~/.zshrc
echo 'export WT_SEARCH_PATHS=~/your/projects:~/your/other/projects' >> ~/.zshrc
source ~/.zshrc
```

### 6. Verify

```bash
wt help            # should print wt usage
wt list            # should print "No active worktrees found"
tmux               # launch tmux, confirm catppuccin theme loads
# Ctrl+a f         # confirm sessionizer opens
```
