# Shell functions for the Ghostty + tmux + Claude Code workflow.
# Source this file from ~/.zshrc or ~/.bashrc:
#
#   source /path/to/wt/config/shell-functions.zsh
#
# Also set your project search paths (used by wt new/list/doctor):
#
#   export WT_SEARCH_PATHS=~/Documents/dev:~/Documents/lab

# claude — renames the tmux window while Claude Code is running and marks
# it with @is_claude_running (read by the choose-tree format in tmux.conf).
# Without tmux, falls through to the normal claude command.
function claude() {
  if [[ -n "$TMUX" ]]; then
    local old_name
    old_name=$(tmux display-message -p '#W')
    tmux rename-window "✳ claude"
    tmux set-option -w @is_claude_running 1
    command claude "$@"
    tmux set-option -wu @is_claude_running
    tmux rename-window "$old_name"
  else
    command claude "$@"
  fi
}

# claude-danger-zone — runs Claude Code with all permission prompts skipped.
# Use when you trust the task and want uninterrupted autonomous operation.
alias claude-danger-zone="claude --dangerously-skip-permissions"

# wt — thin wrapper that enables `cd` into/out of worktrees.
# wt new/finish/done/drop print the target path on stdout; this wrapper
# captures it and calls cd. All other wt commands pass through unchanged.
function wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "done" || "$1" == "drop" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}
