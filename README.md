# wt — Git Worktree Lifecycle Tool

Automates creating, tracking, rebasing, and cleaning up git worktrees for
parallel development workflows. Create isolated branches in seconds, work on
multiple features simultaneously, and merge cleanly with a linear history.

Works great standalone. Works *especially* well with **Claude Code + tmux** — spin up a worktree per Claude task, keep each conversation isolated in its own branch and tmux session, finish or drop when done. See [tmux integration](#tmux-integration-optional) below.

```
wt new "add dark mode toggle"     # create worktree + branch, cd into it
wt finish                         # rebase + fast-forward + clean up
wt sync                           # rebase onto latest base (keep it current)
wt drop                           # abandon without merging
wt list                           # show all active worktrees
```

## Install

```bash
git clone https://github.com/GuidoSantillanID/wt.git
cd wt
./install.sh
```

This symlinks `bin/wt` to `~/.local/bin/wt`. Make sure `~/.local/bin` is on your `PATH`.

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

# Copy node_modules from main checkout (zero-cost on APFS/btrfs)
wt new --with-deps "fix the login bug"

# Create from anywhere by specifying the project name
wt new myapp "add dark mode"

# List all active worktrees across all projects
wt list

# Finish work: rebase onto base branch, fast-forward, clean up
# (run from inside the worktree)
wt finish

# Keep a long-lived worktree current with the base branch
wt sync

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

### `wt new [--with-deps] [project] "<description>"`

Creates a new git worktree with an auto-named branch.

- If run from inside a project, uses the current repo
- If run from outside, pass the project name as the first argument
- If run from inside an existing worktree, creates from the main checkout
- By default, skips all dependency handling — worktree creation is instant with no prompts
- `--with-deps`: opt into dependency handling. For JS projects with `node_modules/` in the main checkout, copies it using copy-on-write cloning (`cp -c` on APFS, `--reflink=auto` on btrfs/XFS) — zero extra disk space on supported filesystems, 10–30× faster than `npm install` on ext4. Otherwise, detects the package manager (pnpm/yarn/npm/uv/poetry/pip) and prompts to install.

### `wt finish [--yes|-y]`

Integrates the worktree back into its base branch. Always produces a linear history — no merge commits.

Pass `--yes` or `-y` to skip all confirmation prompts (useful when running from scripts or Claude Code).

**Safety checks (in order):**
1. Verifies you're in a worktree (not the main checkout) — errors if not
2. Aborts if there are uncommitted changes (`git status` is dirty) — **not** skipped by `--yes`
3. Warns if an editor is still running in this worktree's tmux session (requires `claude_running_in_session()` override; no-op by default) — skipped by `--yes`
4. Confirms: `Rebase wt/<slug> onto <base> and fast-forward? [y/N]` — skipped by `--yes`
5. Fetches remote base branch (best-effort, ignores failure)
6. Rebases worktree branch onto base — aborts and prints manual instructions if there are conflicts
7. Fast-forwards base branch to the rebased tip
8. Removes worktree directory and branch
9. Kills tmux session `<project>/<slug>` if it exists (switches to project main session first if you're running from inside it)
10. `cd`s back to main checkout (via shell wrapper)

> `wt done` still works as an alias for backward compatibility.

### `wt sync`

Rebases the current worktree branch onto the latest base branch from origin. Keeps long-lived worktrees current without finishing them.

**Steps:**
1. Verifies you're in a worktree — errors if not
2. Aborts if there are uncommitted changes
3. Fetches `origin/<base_branch>` (warns on failure, falls back to local ref)
4. Rebases the worktree branch onto `origin/<base_branch>` — aborts and prints manual instructions if there are conflicts
5. Prints success — worktree stays intact, no cleanup

Unlike `wt finish`, sync does not merge into the base, remove the worktree, or change your working directory.

### `wt drop [--yes|-y]`

Abandons a worktree without merging — for dead-end experiments.

Pass `--yes` or `-y` to skip all confirmation prompts.

**Safety checks (in order):**
1. Verifies you're in a worktree
2. Warns if there are uncommitted changes — asks to confirm before proceeding — skipped by `--yes`
3. Warns if an editor is still running in this session (requires `claude_running_in_session()` override) — skipped by `--yes`
4. Final confirmation: `Drop wt/<slug>? (no merge) [y/N]` — skipped by `--yes`

**On success:**
- Worktree directory removed
- Branch force-deleted (`git branch -D` — the branch was never merged)
- Tmux session killed
- `cd`s back to main checkout (via shell wrapper)

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

## Common workflows

### Parallel feature development

```bash
# Window 1: main feature
wt new myapp "implement user auth"

# Window 2 (new tmux window): quick bugfix in parallel
wt new myapp "fix logout redirect"

# Check status of both
wt list

# Finish the bugfix first (from inside its worktree)
wt finish   # rebases onto base, fast-forwards, cleans up

# Continue main feature...
```

### Recovering from a conflict in `wt finish`

If `wt finish` aborts due to a rebase conflict:

```bash
# You're still in the worktree
git rebase <base-branch>   # resolve conflicts (git add + git rebase --continue)
wt finish                  # retry — rebase already done, fast-forward proceeds cleanly
```

### Keeping worktrees visible in tmux

With [tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer), each worktree appears as a separate session automatically. Use your sessionizer keybind to fuzzy-find and switch between:
```
myapp/implement-user-auth
myapp/fix-logout-redirect
```

## Notes

- Worktrees share `.git` but **not** `node_modules`. By default `wt new` skips deps handling entirely. Use `--with-deps` to copy `node_modules/` from the main checkout (JS, CoW) or to be prompted to install (JS without `node_modules/` or non-JS projects).
- The `.wt-meta` file inside each worktree is required by `wt finish` and `wt list`. Don't delete it.
- Branch names are prefixed with `wt/` to keep them namespaced and easy to identify.
- Descriptions are truncated to 50 characters when generating the slug.
- `wt new` excludes `.worktrees/` from `git status` via `.git/info/exclude` (repo-local, not committed). This keeps your `.gitignore` clean. To adopt `wt` as a team tool, add `.worktrees/` to the committed `.gitignore` instead.
- Running `wt new` from inside an existing worktree is safe — it detects the context and creates the new worktree from the main checkout, not nested inside the current one.
- `wt drop` force-deletes the branch without merging. Use it when you want to discard the work entirely.

## Requirements

- bash 4+ (macOS ships with bash 3.2; install via `brew install bash`)
- git 2.5+

## Running tests

```bash
bin/wt-test
bin/wt-test --keep   # preserve temp dir on failure for debugging
```

Tests create a real git repo in `/tmp`, run all commands against it, and clean up.

## Workflow setup (optional)

`wt` works standalone, but it was built for a Ghostty + tmux + Claude Code workflow. The `config/` directory in this repo contains the full stack config (Ghostty, tmux, Claude Code hooks, ccline status line, shell wrappers). `docs/SETUP.md` explains how the pieces connect and has step-by-step installation instructions.

See `docs/SETUP.md` for step-by-step setup. To back up your local configs to this repo, run `./update-config.sh`.
