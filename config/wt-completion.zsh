# =============================================================================
# wt-completion.zsh — Zsh tab completion for the wt worktree tool
# =============================================================================
#
# Source this file from ~/.zshrc AFTER the wt shell wrapper and AFTER compinit:
#
#   source /path/to/wt-completion.zsh
#
# Or after installation (install.sh symlinks it to ~/.local/bin/):
#
#   source ~/.local/bin/wt-completion.zsh
#
# Performance: helpers use only zsh builtins (no grep/cut/git forks per worktree).
# One subshell is spawned per completion call to capture branch list output.
# =============================================================================

# ─── Helpers (pure builtins, no forks) ───────────────────────────────────────

# _wt_read_meta_field FILE KEY
#   Sets REPLY to the value of KEY in a .wt-meta file.
#   Uses only builtins: while read + parameter expansion (no grep/cut).
_wt_read_meta_field() {
  local _file=$1 _key=$2 _line
  REPLY=''
  while IFS= read -r _line || [[ -n $_line ]]; do
    if [[ $_line == ${_key}=* ]]; then
      REPLY=${_line#${_key}=}
      return 0
    fi
  done < "$_file"
  return 1
}

# _wt_list_branches
#   Prints one branch name per line for every registered worktree.
#   Reads WT_REGISTRY (default: ~/.config/wt/projects), then scans
#   <project>/.worktrees/*/.wt-meta for the "branch" field.
#   Pure builtins: no grep, no cut, no subprocesses.
_wt_list_branches() {
  local _registry=${WT_REGISTRY:-${XDG_CONFIG_HOME:-$HOME/.config}/wt/projects}
  [[ -f $_registry ]] || return 0

  local _project _meta _branch
  while IFS= read -r _project || [[ -n $_project ]]; do
    [[ -z $_project ]] && continue
    [[ -d ${_project}/.worktrees ]] || continue
    # (N) glob qualifier: no error if no matches
    for _meta in ${_project}/.worktrees/*/.wt-meta(N); do
      [[ -f $_meta ]] || continue
      REPLY=''
      _wt_read_meta_field "$_meta" "branch" || true
      [[ -n $REPLY ]] && print -- "$REPLY"
    done
  done < "$_registry"
}

# ─── Completion dispatcher ────────────────────────────────────────────────────

_wt() {
  local state
  local -a subcommands
  subcommands=(
    'new:create a worktree with auto-named branch'
    'finish:integrate worktree into base, clean up'
    'sync:merge local base branch into worktree'
    'retarget:change this worktree'"'"'s base branch'
    'abandon:abandon worktree without merging'
    'pr:push branch and open a GitHub PR'
    'status:show current worktree info'
    'list:show all worktrees across projects'
    'go:navigate to an existing worktree'
    'doctor:check and repair worktree health'
    'help:show help'
  )

  _arguments -C \
    '1:subcommand:->subcmd' \
    '*::args:->args' \
    && return

  case $state in
    subcmd)
      _describe 'wt subcommand' subcommands
      ;;
    args)
      case ${words[1]} in
        go)
          local -a branches
          branches=( ${(f)"$(_wt_list_branches)"} )
          _describe 'worktree branch' branches
          ;;
        abandon)
          local -a branches
          branches=( ${(f)"$(_wt_list_branches)"} )
          _arguments \
            '(-y --yes)'{-y,--yes}'[skip confirmation prompts]' \
            '--force[override safety gates]' \
            '1:branch:->branch' \
            && return
          if [[ $state == branch ]]; then
            _describe 'worktree branch' branches
          fi
          ;;
        finish)
          _arguments \
            '(-y --yes)'{-y,--yes}'[skip confirmation prompts]' \
            '--force[override safety gates]'
          ;;
        pr)
          _arguments \
            '--draft[open as draft PR]' \
            '(-y --yes)'{-y,--yes}'[skip confirmation prompts]'
          ;;
        doctor)
          _arguments '--dry-run[show what would happen without changes]'
          ;;
        retarget)
          local -a localbranches
          localbranches=( ${(f)"$(git branch --format='%(refname:short)' 2>/dev/null)"} )
          _describe 'local branch' localbranches
          ;;
      esac
      ;;
  esac
}

# Register with zsh completion system (no-op if compinit not loaded)
if (( $+functions[compdef] )); then
  compdef _wt wt
fi
