# wt — Git Worktree Lifecycle Tool

Automates creating, tracking, rebasing, and cleaning up git worktrees for
parallel development workflows. Create isolated branches in seconds, work on
multiple features simultaneously, and merge cleanly with a linear history.

Works great standalone. Works *especially* well with **Claude Code + tmux** — spin up a worktree per Claude task, keep each conversation isolated in its own branch and tmux session, finish or drop when done. See [tmux integration](#tmux-integration-optional) below.

```
wt new "add dark mode toggle"     # create worktree + branch, cd into it
wt finish                         # rebase + fast-forward + clean up
wt drop                           # abandon without merging
wt list                           # show all active worktrees
```

## Install

```bash
git clone https://github.com/your-username/wt.git
cd wt
./install.sh
```

This copies `bin/wt` to `~/.local/bin/wt`. Make sure `~/.local/bin` is on your `PATH`.

### Shell wrapper

Add this to `~/.zshrc` or `~/.bashrc` so that `wt new`, `wt finish`, and `wt drop` automatically `cd` your shell into the right directory:

```bash
# zsh (~/.zshrc):
function wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "done" || "$1" == "drop" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}

# bash (~/.bashrc) — identical syntax, just a different file:
wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "done" || "$1" == "drop" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}
```

## Configure search paths

`wt` needs to know where your projects live to find them by name. Configure in order of precedence:

**1. Environment variable** (colon-separated, like `PATH`):
```bash
export WT_SEARCH_PATHS=~/src:~/projects:~/work
```

**2. Config file** (`~/.config/wt/config`, one path per line):
```
~/src
~/projects
~/work
```

**3. Default** (if neither is set):
```
~/src  ~/projects  ~/repos  ~/code
```

## Cheat sheet

```bash
# Create a worktree from inside a project directory
wt new "fix the login bug"

# Create from anywhere by specifying the project name
wt new myapp "add dark mode"

# List all active worktrees across all projects
wt list

# Finish work: rebase onto base branch, fast-forward, clean up
# (run from inside the worktree)
wt finish

# Abandon work without merging
wt drop

# Diagnose and fix orphaned branches/dirs
wt doctor
```

## How it works

- Worktrees are created at `<project>/.worktrees/<slug>/`
- Branch names: `wt/<slug>` (auto-generated from your description)
- A `.wt-meta` file in each worktree stores metadata (base branch, description, timestamps)
- `.worktrees/` and `.wt-meta` are excluded from git via `.git/info/exclude` (never committed)
- `wt finish` rebases the worktree branch onto its base, fast-forwards the base, and removes the worktree and branch — leaving a linear history
- `wt drop` removes the worktree and branch without merging

## Commands reference

### `wt new [project] "<description>"`

Creates a new git worktree with an auto-named branch.

- If run from inside a project, uses the current repo
- If run from outside, pass the project name as the first argument
- If run from inside an existing worktree, creates from the main checkout
- Detects package manager (pnpm/yarn/npm/uv/poetry/pip) and offers to install deps

### `wt finish`

Integrates the worktree back into its base branch.

1. Checks for uncommitted changes (blocks if any)
2. Prompts for confirmation
3. Fetches remote base branch (best-effort)
4. Rebases worktree branch onto base
5. Fast-forwards base branch to rebased tip
6. Removes worktree directory and branch
7. `cd`s back to main checkout (via shell wrapper)

### `wt drop`

Abandons a worktree without merging.

1. Warns about uncommitted changes (prompts)
2. Removes worktree directory and branch
3. `cd`s back to main checkout (via shell wrapper)

### `wt list`

Shows all active worktrees across all configured search paths:

```
myapp
  wt/add-dark-mode          3 ahead  clean       2h ago  "add dark mode"
  wt/fix-login-bug          0 ahead  2 dirty     1d ago  "fix the login bug"
```

### `wt doctor`

Scans for and interactively fixes:

- Orphaned `wt/*` branches (no matching worktree dir)
- Orphaned `.worktrees/` directories (not registered as git worktrees)
- Corrupt `.wt-meta` files
- Missing `.git/info/exclude` entries
- Stale git worktree registrations

## tmux integration (optional)

`wt` works without tmux. When run inside a tmux session, cleanup commands (`wt finish`, `wt drop`) will additionally kill the tmux session named `<project>/<slug>` if it exists.

### Claude Code + tmux workflow

This is the sweet spot `wt` was designed for. With [tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer) (or similar), each worktree becomes its own tmux session automatically:

```bash
# Start a Claude task in isolation
wt new myapp "implement dark mode"
# → creates myapp/.worktrees/implement-dark-mode/
# → tmux-sessionizer picks it up as session "myapp/implement-dark-mode"
# → run `claude` in that session — fully isolated branch

# While Claude works, start another task in parallel
wt new myapp "fix login redirect"
# → separate worktree, separate branch, separate tmux session

# Claude finishes dark mode → rebase + clean up
cd myapp/.worktrees/implement-dark-mode
wt finish   # rebases, fast-forwards, kills tmux session, cd's back

# All tasks visible at a glance
wt list
```

Each Claude Code conversation gets its own branch, its own working tree, and its own tmux session. No context bleeding between tasks.

If you want `wt finish`/`wt drop` to check whether your editor is still running before proceeding, override the `claude_running_in_session` function. For example, if you use a tmux option `@is_editor_running` to track this:

```bash
# In your shell rc, after sourcing the wt wrapper:
claude_running_in_session() {
  local val
  val=$(tmux show-option -t "$1" -wv @is_editor_running 2>/dev/null || echo "")
  [[ "$val" == "1" ]]
}
```

## Requirements

- bash 4+ (macOS ships with bash 3.2; install via `brew install bash`)
- git 2.5+

## Running tests

```bash
bin/wt-test
bin/wt-test --keep   # preserve temp dir on failure for debugging
```

Tests create a real git repo in `/tmp`, run all commands against it, and clean up.
