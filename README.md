# wt — Git Worktree Lifecycle Tool

Automates creating, tracking, rebasing, and cleaning up git worktrees for
parallel development workflows. Create isolated branches in seconds, work on
multiple features simultaneously, and merge cleanly with a linear history.

Works great standalone. Works *especially* well with **Claude Code + tmux** — spin up a worktree per Claude task, keep each conversation isolated in its own branch and tmux session, finish or abandon when done. See [tmux integration](#tmux-integration-optional) below.

```
wt new "add dark mode toggle"     # create worktree + branch, cd into it
wt open feature/my-branch         # branch off an existing branch into a worktree
wt finish                         # rebase + fast-forward + clean up
wt sync                           # merge local base into worktree (LLM-friendly)
wt retarget [branch]              # change which branch this worktree targets
wt abandon                        # abandon without merging
wt pr                             # push branch + open GitHub PR
wt status                         # show current worktree info
wt list                           # show all active worktrees
wt go wt/add-dark-mode-toggle     # navigate to an existing worktree
```

## Install

```bash
git clone https://github.com/GuidoSantillanID/wt.git
cd wt
./install.sh
```

This symlinks `bin/wt` to `~/.local/bin/wt`. Make sure `~/.local/bin` is on your `PATH`.

### Shell wrapper

Add this to `~/.zshrc` or `~/.bashrc` so that `wt new`, `wt finish`, `wt abandon`, `wt go`, and `wt open` automatically `cd` your shell into the right directory:

```bash
# zsh (~/.zshrc):
function wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" || "$1" == "go" || "$1" == "open" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}

# bash (~/.bashrc) — identical syntax, just a different file:
wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" || "$1" == "go" || "$1" == "open" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}
```

### Tab completion (zsh)

`install.sh` also symlinks `config/wt-completion.zsh` to `~/.local/bin/wt-completion.zsh`. Add this near the **end** of `~/.zshrc`, after your framework init or `compinit`:

```zsh
# Oh My Zsh users: add after the `source $ZSH/oh-my-zsh.sh` line
# Manual zshrc users: add after your `compinit` call
source ~/.local/bin/wt-completion.zsh
```

This enables:
- `wt <tab>` — subcommand list
- `wt go <tab>` — branch names from all registered worktrees
- `wt open <tab>` — local branch names
- `wt abandon <tab>` — branch names + flags
- `wt finish/pr/doctor <tab>` — flags

File I/O uses only zsh builtins (no `grep`/`cut` forks per worktree), so completion stays fast (~5ms) regardless of how many worktrees you have.

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

# Branch off an existing feature branch into a worktree
wt open feature/my-branch

# List all active worktrees across all projects
wt list

# Finish work: rebase onto base branch, fast-forward, clean up
# (run from inside the worktree)
wt finish

# Merge local base into worktree (keep it current, LLM-friendly conflict output)
wt sync

# Change which branch this worktree will merge into
wt retarget main           # switch to main
wt retarget                # interactive picker

# Abandon work without merging
wt abandon

# Drop even if there are unpushed commits (non-skippable gate)
wt abandon --force --yes

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
- **`wt new`**: creates a `wt/<slug>` branch off the current branch, tracks it as `base_branch` in `.wt-meta`
- **`wt open`**: creates a `wt/<slug>` branch off an existing named branch, with that branch as `base_branch`
- Both support the full lifecycle: `finish`, `abandon`, `sync`, `retarget`, `pr`
- A `.wt-meta` file in each worktree stores metadata (base branch, description, timestamps)
- `.worktrees/` and `.wt-meta` are excluded from git via `.git/info/exclude` (never committed)
- `wt finish` integrates the worktree branch into its base (rebase or squash, auto-detected), fast-forwards the base, and removes the worktree and branch
- `wt abandon` removes the worktree and branch without merging

## Commands reference

### `wt new "<description>"`

Creates a new git worktree with an auto-named branch.

- Must be run from inside a git repo (or a worktree of one)
- If run from inside an existing worktree, creates from the main checkout — the new worktree's base branch is the **main checkout's current branch**, not the branch of the worktree you're in. `wt` prints a message showing which branch that is so you can verify.
- Registers the project automatically on first use
- Prints a reminder to install dependencies if needed (worktrees don't share `node_modules`/`venv`)

### `wt open <branch>`

Creates a worktree branching off an existing local branch — for working on top of feature branches in parallel with full lifecycle support.

- The branch must exist locally (run `git fetch` first if needed)
- Creates a `wt/<slug>` branch off the target, with `base_branch` set to the target
- Full lifecycle works: `finish` merges work back into the target branch, `abandon` drops only the working branch (target branch is untouched), `sync` pulls updates from the target branch
- `wt go`, `wt list`, `wt status`, `wt doctor`, `wt retarget`, and `wt pr` all work

```bash
wt open feature/my-branch        # creates wt/feature-my-branch off feature/my-branch
wt open GP-123-fix-login          # works with any branch naming convention
```

### `wt finish [--force]`

Integrates the worktree back into its base branch and cleans up. No confirmation prompts — the only interactive gate is untracked files (data loss warning).

Pass `--force` to override the untracked-files safety gate.

**Strategy (auto-detected):**
- **No merge commits** (clean history): rebases onto base and fast-forwards → linear history
- **Merge commits present** (from `wt sync`): squash-merges into base → single commit on base, avoids re-encountering conflicts

**Steps (in order):**
1. Verifies you're in a worktree (not the main checkout) — errors if not
2. Aborts if there are tracked uncommitted changes
3. Warns if there are untracked files (they will be permanently deleted) — only `--force` bypasses
4. Detects strategy (rebase vs squash) based on merge commits in `<base>..HEAD`
   - **Squash path**: requires base to be an ancestor of HEAD (i.e. `wt sync` was run). If base has new commits since the last `wt sync`, errors with a prompt to run `wt sync` again.
   - **Rebase path**: fetches remote base (best-effort). Rebases — SIGINT-trapped; aborts cleanly on Ctrl+C; aborts and prints manual instructions on conflict.
5. Fast-forwards base branch to the integrated tip (checks all worktrees, not just main)
6. Removes worktree directory and branch
7. Inside tmux: prints a reminder to close the current window
8. `cd`s back to main checkout (via shell wrapper)


### `wt sync`

Merges the **local** base branch into the current worktree branch. Keeps long-lived worktrees current without finishing them. Designed for LLM-assisted conflict resolution — when conflicts occur, shows file-level context (conflicted lines, commit history for both sides) so the LLM can resolve clear cases autonomously and ask for guidance on ambiguous ones.

**Steps:**
1. Verifies you're in a worktree — errors if not
2. Errors if a merge or rebase is already in progress
3. Aborts if there are uncommitted tracked changes (untracked files are allowed)
4. Errors if the base branch ref doesn't exist locally
5. If already up to date (base is an ancestor of HEAD), exits with success
6. Runs `git merge <base_branch>` — exits on success
7. On conflict: lists conflicted files with line numbers and commit context, exits 1

**When conflicts occur (LLM flow):**
1. Read each conflicted file — both sides of every `<<<<<<<`/`=======`/`>>>>>>>` marker
2. If the resolution is clear: resolve and explain what was done
3. If the resolution requires product/business knowledge: explain both sides and ask the user
4. `git add <resolved-files>`, then `git merge --continue`
5. To abort: `git merge --abort`

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

### `wt abandon [--yes|-y] [--force]`

Abandons a worktree without merging — for dead-end experiments.

Pass `--yes` or `-y` to skip routine confirmation prompts.

Pass `--force` to override the non-skippable unpushed-commits safety gate.

**Safety checks (in order):**
1. Verifies you're in a worktree
2. Warns if there are uncommitted changes — asks to confirm before proceeding — skipped by `--yes`
3. **Non-skippable:** warns if the branch has commits not in the base branch (unpushed work that will be lost) — prompts even with `--yes`; only `--force` bypasses
4. Final confirmation: `Drop wt/<slug>? (no merge) [y/N]` — skipped by `--yes`

**On success:**
- Worktree directory removed
- Branch force-deleted (`git branch -D` — the branch was never merged)
- Inside tmux: prints a reminder to close the current window
- `cd`s back to main checkout (via shell wrapper)

### `wt pr [--draft] [--yes|-y]`

Pushes the worktree branch and opens a GitHub PR. Requires the [GitHub CLI](https://cli.github.com).

**Steps:**
1. Verifies you're in a worktree — errors if not
2. Aborts if there are uncommitted changes
3. Shows current base branch with a hint to use `wt retarget` to change it
4. If no merge commits in `<base>..HEAD`: fetches and rebases onto `origin/<base_branch>` — pauses on conflicts. If merge commits are present (from `wt sync`): skips rebase to avoid re-encountering resolved conflicts.
5. Pushes to origin with `--force-with-lease` (needed after rebase rewrites history)
6. If a PR already exists for this branch, prints the URL and returns
7. Auto-generates the PR body from commits on the branch (`git log --oneline` as a bullet list)
8. Confirms PR creation, then runs `gh pr create` targeting the base branch
9. Prints the PR URL to stdout (pipeable)

Pass `--draft` to create a draft PR. Pass `--yes`/`-y` to skip all confirmation prompts.

The worktree stays alive after `wt pr` — keep pushing updates. Use `wt abandon` when the PR is merged or abandoned.

### `wt status`

Shows info about the current worktree: branch, base branch, description, commits ahead, working tree status, and age. If `gh` is installed and the repo has a GitHub remote, also shows the PR URL if one is open.

All output goes to stderr. No flags needed.

### `wt list`

Shows all active worktrees across all registered projects:

```
myapp
  wt/add-dark-mode          3 ahead  clean       2h ago  "add dark mode"
  wt/fix-login-bug          0 ahead  2 dirty     1d ago  "fix the login bug"
  wt/feature-payments       0 ahead  clean       0m ago  "feature/payments"
```

### `wt go <branch-or-slug>`

Navigates to an existing worktree. Useful after reopening a shell.

- Accepts the branch name (`wt/fix-login-bug`) or just the slug (`fix-login-bug`)
- Matching is exact and case-sensitive; branch match takes priority over slug match
- If multiple worktrees match, lists them and exits with an error

### `wt doctor [--dry-run]`

Scans for and interactively fixes:

- Orphaned `wt/*` branches (no matching worktree dir)
- Orphaned `.worktrees/` directories (not registered as git worktrees)
- Missing `.wt-meta` files — offers to repair by inferring values from git state
- Corrupt `.wt-meta` files (missing required fields) — offers to repair
- Missing `.git/info/exclude` entries
- Stale git worktree registrations
- Stale registry entries (projects that no longer exist on disk)

Pass `--dry-run` to report all issues without fixing anything.

## tmux integration (optional)

`wt` works without tmux. When run inside a tmux session, `wt finish` and `wt abandon` print a bold reminder to close the current window after cleanup completes. Your session is never killed automatically — you stay in control of your tmux layout.

### Claude Code + tmux workflow

This is the sweet spot `wt` was designed for. With [tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer) (or similar), each worktree becomes its own tmux window or session automatically:

```bash
# Start a Claude task in isolation (from inside the project dir)
cd myapp
wt new "implement dark mode"
# → creates myapp/.worktrees/implement-dark-mode/
# → open a new tmux window there and run `claude` — fully isolated branch

# While Claude works, start another task in parallel
wt new "fix login redirect"
# → separate worktree, separate branch, separate window

# Claude finishes dark mode → rebase + clean up
cd myapp/.worktrees/implement-dark-mode
wt finish   # rebases, fast-forwards, reminds you to close the window, cd's back

# All tasks visible at a glance
wt list
```

Each Claude Code conversation gets its own branch and its own working tree. No context bleeding between tasks.

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

### Working on existing feature branches in parallel

Use `wt open` when you already have feature branches and want to work on them in isolation:

```bash
# Main checkout is on feature-A, want to also work on feature-B
wt open feature/payment-api       # creates wt/feature-payment-api off feature/payment-api

# Work on it, make commits on the wt/ branch
# When done, merge work back into feature/payment-api
wt finish

# Or abandon without merging (feature/payment-api stays untouched)
wt abandon
```

### Recovering from a conflict in `wt finish`

If `wt finish` aborts due to a rebase conflict:

```bash
# Merge base into worktree instead (LLM-friendly conflict output)
wt sync                    # merge base into worktree (Claude resolves conflicts)
wt finish                  # squash path auto-detected — no rebase, no re-conflict
```

### Keeping worktrees visible in tmux

With [tmux-sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer), each worktree appears as a separate session automatically. Use your sessionizer keybind to fuzzy-find and switch between:
```
myapp/implement-user-auth
myapp/fix-logout-redirect
```

## Notes

- Worktrees share `.git` but **not** `node_modules` or virtual environments. `wt new` reminds you to install dependencies.
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
