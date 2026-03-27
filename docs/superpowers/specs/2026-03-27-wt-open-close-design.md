# wt open / wt close — Design Spec

## Problem

When working on multiple feature branches in parallel, you need each branch in its own worktree. The current `wt new` creates an intermediate `wt/<slug>` branch that must be merged back — unnecessary overhead when you just want to check out an existing branch.

## Solution

Two new commands: `wt open <branch>` and `wt close`. A new `type` field in `.wt-meta` distinguishes "open" worktrees (existing branch, no merge lifecycle) from "managed" worktrees (created by `wt new`, full lifecycle).

## Approach: Distinct lifecycle with a type field

### `wt open <branch>`

Check out an existing local branch into a worktree.

1. Validate `<branch>` exists locally (`git rev-parse --verify`)
2. Validate `<branch>` isn't already checked out (in main or another worktree)
3. Slugify the branch name for worktree dir (e.g., `feature/login` -> `feature-login`)
4. Create worktree: `git worktree add .worktrees/<slug> <branch>`
5. Write `.wt-meta`:
   - `type=open`
   - `branch=<branch>` (actual branch name, no `wt/` prefix)
   - `project=<basename>`
   - `project_root=<abs path>`
   - `slug=<slug>`
   - `created=<timestamp>`
   - `description=<branch>` (branch name as description)
   - No `base_branch` field
6. Register project in registry
7. Add `.worktrees/` to `.git/info/exclude`
8. Print worktree path to stdout (shell wrapper `cd`s)

### `wt close`

Remove a worktree created by `wt open`. Branch stays as-is.

1. Must be inside a worktree with `.wt-meta`
2. Must have `type=open` — refuse otherwise ("this is a managed worktree, use `wt finish` or `wt abandon`")
3. Warn if uncommitted tracked changes (require `--force`)
4. Warn if untracked files (require `--force`)
5. `git worktree remove --force <path>`
6. Unregister project if no worktrees remain
7. Print main worktree path to stdout

### Guards on existing commands

- `wt finish`: if `type=open` -> error "This is an open worktree. Use `wt close` to remove it."
- `wt abandon`: same guard
- `wt sync`: same guard (no base branch to sync from)
- `wt retarget`: same guard (no base branch to retarget)

### Commands that work unchanged

- `wt list`: reads `.wt-meta`, shows `[open]` marker for open worktrees
- `wt go`: matches on `branch` or `slug` fields
- `wt status`: reads `.wt-meta`
- `wt doctor`: validates `.wt-meta` presence

### `wt list` display

```
myproject
  feature/login          3 ahead  clean  2h ago  "feature/login"   [open]
  wt/fix-sidebar         5 ahead  dirty  1h ago  "fix sidebar"
```

### `.wt-meta` type field

- `type=open` — created by `wt open`, no merge lifecycle
- Existing worktrees (created by `wt new`) have no `type` field; treated as managed (implicit default)

### Edge cases

- `wt open main` — allowed
- `wt open wt/some-slug` — allowed but unusual
- Branch doesn't exist locally — error with message suggesting `git fetch`
- Branch already checked out — error

### No aliases

`wt open` and `wt close` have no aliases.
