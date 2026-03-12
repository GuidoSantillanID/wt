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
#
# wt new automatically launches claude --dangerously-skip-permissions after
# creating and cd-ing into the worktree. Pass --no-claude to skip.
function wt() {
  local skip_claude=0
  local args=()
  for arg in "$@"; do
    if [[ "$arg" == "--no-claude" ]]; then
      skip_claude=1
    else
      args+=("$arg")
    fi
  done

  if [[ "${args[1]}" == "new" || "${args[1]}" == "finish" || "${args[1]}" == "done" || "${args[1]}" == "drop" ]]; then
    local dir
    dir=$(command wt "${args[@]}") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "${args[@]}"
  fi

  if [[ $skip_claude -eq 0 && "${args[1]}" == "new" && -n "$dir" ]]; then
    claude --dangerously-skip-permissions
  fi
}
