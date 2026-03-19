# wt — Git Worktree Lifecycle Tool

Automates creating, tracking, rebasing, and cleaning up git worktrees for
parallel development workflows. Create isolated branches in seconds, work on
multiple features simultaneously, and merge cleanly with a linear history.

Works great standalone. Works *especially* well with **Claude Code + tmux** — spin up a worktree per Claude task, keep each conversation isolated in its own branch and tmux session, finish or abandon when done. See [tmux integration](#tmux-integration-optional) below.

```
wt new "add dark mode toggle"     # create worktree + branch, cd into it
wt finish                         # rebase + fast-forward + clean up
wt sync                           # rebase onto latest base (keep it current)
wt retarget [branch]              # change which branch this worktree targets
wt abandon                        # abandon without merging
wt pr                             # push branch + open GitHub PR
wt status                         # show current worktree info
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

Add this to `~/.zshrc` or `~/.bashrc` so that `wt new`, `wt finish`, and `wt abandon` automatically `cd` your shell into the right directory:

```bash
# zsh (~/.zshrc):
function wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}

# bash (~/.bashrc) — identical syntax, just a different file:
wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}
```

## Project registry

`wt` tracks projects automatically. Run `wt new` from inside any git repo — it registers that project in `~/.config/wt/projects`. `wt list` and `wt doctor` read the registry; no manual config needed.

When the last worktree in a project is cleaned up and no `wt/*` branches remain, the project is automatically removed from the registry.

**Override the registry path** (useful for CI or custom setups):
```bash
export WT_REGISTRY=~/my-custom-registry
```

The registry is a plain text file — one absolute project path per line.

## Cheat sheet

```bash
# Create a worktree from inside a project directory
wt new "fix the login bug"

# Copy node_modules from main checkout (zero-cost on APFS/btrfs)
wt new --with-deps "fix the login bug"

# List all active worktrees across all projects
wt list

# Finish work: rebase onto base branch, fast-forward, clean up
# (run from inside the worktree)
wt finish

# Keep a long-lived worktree current with the base branch
wt sync

# Change which branch this worktree will merge into
wt retarget main           # switch to main
wt retarget                # interactive picker

# Abandon work without merging
wt abandon

# Push branch and open a GitHub PR (requires gh CLI)
wt pr

# Open a draft PR
wt pr --draft

# Show current worktree info (branch, base, ahead, age)
wt status

# Diagnose and fix orphaned branches/dirs
wt doctor
```

## How it works

- Worktrees are created at `<project>/.worktrees/<slug>/`
- Branch names: `wt/<slug>` (auto-generated from your description)
- A `.wt-meta` file in each worktree stores metadata (base branch, description, timestamps)
- `.worktrees/` and `.wt-meta` are excluded from git via `.git/info/exclude` (never committed)
- `wt finish` rebases the worktree branch onto its base, fast-forwards the base, and removes the worktree and branch — leaving a linear history
- `wt abandon` removes the worktree and branch without merging

## Commands reference

### `wt new [--with-deps] "<description>"`

Creates a new git worktree with an auto-named branch.

- Must be run from inside a git repo (or a worktree of one)
- If run from inside an existing worktree, creates from the main checkout — the new worktree's base branch is the **main checkout's current branch**, not the branch of the worktree you're in. `wt` prints a message showing which branch that is so you can verify.
- Registers the project automatically on first use
- By default, skips all dependency handling — worktree creation is instant with no prompts
- `--with-deps`: opt into dependency handling. For JS projects with `node_modules/` in the main checkout, copies it using copy-on-write cloning (`cp -c` on APFS, `--reflink=auto` on btrfs/XFS) — zero extra disk space on supported filesystems, 10–30× faster than `npm install` on ext4. Otherwise, detects the package manager (pnpm/yarn/npm/uv/poetry/pip) and prompts to install.

### `wt finish [--yes|-y] [--force]`

Integrates the worktree back into its base branch. Always produces a linear history — no merge commits.

Pass `--yes` or `-y` to skip all confirmation prompts (useful when running from scripts or Claude Code).

Pass `--force` to bypass the PR-open guard and finish locally even when a GitHub PR is still open.

**Safety checks (in order):**
1. Verifies you're in a worktree (not the main checkout) — errors if not
2. Aborts if there are tracked uncommitted changes — **not** skipped by `--yes`
3. Warns if there are untracked files (they will be permanently deleted) — auto-accepted by `--yes`
4. Warns if an editor is still running in this worktree's tmux session (requires `claude_running_in_session()` override; no-op by default) — skipped by `--yes`
5. If `gh` is installed: checks for a GitHub PR on the current branch
   - **PR merged**: confirms cleanup (skipped with `--yes`), removes worktree + branch without rebasing, returns
   - **PR open**: errors unless `--force` is passed; with `--force`, proceeds to local rebase flow
   - **No PR / gh unavailable**: continues with local rebase flow below
6. Confirms: `Rebase wt/<slug> onto <base> and fast-forward? [y/N]` — skipped by `--yes`
7. Fetches remote base branch (best-effort, ignores failure)
8. Rebases worktree branch onto base — aborts and prints manual instructions if there are conflicts
9. Fast-forwards base branch to the rebased tip (checks all worktrees, not just main)
10. Removes worktree directory and branch
11. Kills tmux session `<project>/<slug>` if it exists (switches to project main session first if you're running from inside it)
12. `cd`s back to main checkout (via shell wrapper)


### `wt sync`

Rebases the current worktree branch onto the latest base branch from origin. Keeps long-lived worktrees current without finishing them.

**Steps:**
1. Verifies you're in a worktree — errors if not
2. Aborts if there are uncommitted changes
3. Fetches `origin/<base_branch>` (warns on failure, falls back to local ref)
4. Rebases the worktree branch onto `origin/<base_branch>` — aborts and prints manual instructions if there are conflicts
5. Prints success — worktree stays intact, no cleanup

Unlike `wt finish`, sync does not merge into the base, remove the worktree, or change your working directory.

### `wt retarget [branch]`

Changes the base branch recorded in `.wt-meta` — no git operations, metadata only. All subsequent `wt finish`, `wt sync`, and `wt pr` commands will use the new base.

If `branch` is given, it must exist locally or as `origin/<branch>`. If omitted, shows an interactive picker listing remote branches (falls back to local branches if no remote).

```bash
# Change to a specific branch
wt retarget main

# Interactive picker
wt retarget
```

After retargeting, run `wt sync` if you want to rebase the working branch onto the new base immediately.

### `wt abandon [--yes|-y]`

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

### `wt pr [--draft] [--yes|-y]`

Pushes the worktree branch and opens a GitHub PR. Requires the [GitHub CLI](https://cli.github.com).

**Steps:**
1. Verifies you're in a worktree — errors if not
2. Aborts if there are uncommitted changes
3. Prompts to confirm or change the base branch (skipped with `--yes`). If changed, updates `.wt-meta` so future `wt pr`/`wt sync`/`wt finish` use the new base.
4. Fetches and rebases onto `origin/<base_branch>` (same as `wt sync`) — pauses on conflicts
5. Pushes to origin with `--force-with-lease` (needed after rebase rewrites history)
6. If a PR already exists for this branch, prints the URL and returns
7. Auto-generates the PR body from commits on the branch (`git log --oneline` as a bullet list)
8. Confirms PR creation, then runs `gh pr create` targeting the base branch
9. Prints the PR URL to stdout (pipeable)

Pass `--draft` to create a draft PR. Pass `--yes`/`-y` to skip all confirmation prompts.

The worktree stays alive after `wt pr` — keep pushing updates. Use `wt finish` or `wt abandon` when the PR is merged or abandoned.

### `wt status`

Shows info about the current worktree: branch, base branch, description, commits ahead, working tree status, and age. If `gh` is installed and the repo has a GitHub remote, also shows the PR URL if one is open.

All output goes to stderr. No flags needed.

### `wt list`

Shows all active worktrees across all registered projects:

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

`wt` works without tmux. When run inside a tmux session, cleanup commands (`wt finish`, `wt abandon`) will additionally kill the tmux session named `<project>/<slug>` if it exists.

### Claude Code + tmux workflow

This is the sweet spot `wt` was designed for. With [tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer) (or similar), each worktree becomes its own tmux session automatically:

```bash
# Start a Claude task in isolation (from inside the project dir)
cd myapp
wt new "implement dark mode"
# → creates myapp/.worktrees/implement-dark-mode/
# → tmux-sessionizer picks it up as session "myapp/implement-dark-mode"
# → run `claude` in that session — fully isolated branch

# While Claude works, start another task in parallel
wt new "fix login redirect"
# → separate worktree, separate branch, separate tmux session

# Claude finishes dark mode → rebase + clean up
cd myapp/.worktrees/implement-dark-mode
wt finish   # rebases, fast-forwards, kills tmux session, cd's back

# All tasks visible at a glance
wt list
```

Each Claude Code conversation gets its own branch, its own working tree, and its own tmux session. No context bleeding between tasks.

If you want `wt finish`/`wt abandon` to check whether your editor is still running before proceeding, override the `claude_running_in_session` function. For example, if you use a tmux option `@is_editor_running` to track this:

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
# Window 1: main feature (from inside the project dir)
cd myapp && wt new "implement user auth"

# Window 2 (new tmux window): quick bugfix in parallel
cd myapp && wt new "fix logout redirect"

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
- Projects are auto-registered in `~/.config/wt/projects` on first `wt new` and auto-removed when the last worktree is cleaned up.
- `wt abandon` force-deletes the branch without merging. Use it when you want to discard the work entirely.

## Requirements

- bash 4+ (macOS ships with bash 3.2; install via `brew install bash`)
- git 2.5+

## Running tests

```bash
bash bin/wt-test < /dev/null
bash bin/wt-test --keep < /dev/null   # preserve temp dir on failure for debugging
```

Tests create a real git repo in `/tmp`, run all commands against it, and clean up. Redirect stdin from `/dev/null` to prevent interactive prompts from blocking.

## Workflow setup (optional)

`wt` works standalone, but it was built for a Ghostty + tmux + Claude Code workflow. See the [cockpit](https://github.com/GuidoSantillanID/cockpit) repo for the full stack config (Ghostty, tmux, Claude Code hooks, ccline status line, shell wrappers) and step-by-step setup guide.
