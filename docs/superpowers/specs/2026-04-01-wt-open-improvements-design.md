# wt open improvements

## Problem

Four usability gaps with `wt open`:

1. Can't create a second worktree from the same branch — slug collision on the directory name
2. No way to discover available branches from within `wt`
3. `wt open` may not `cd` into the new worktree (shell wrapper config issue)
4. Users unaware that `wt go` / `wt abandon` / `wt list` already handle navigation and cleanup

## Changes

### 1. Optional description parameter

**Signature:** `wt open [<branch>] ["description"]`

Three modes:

| Invocation | Behavior |
|---|---|
| `wt open` | List branches (local + remote), exit |
| `wt open <branch>` | Current behavior: slug from branch name, errors on collision |
| `wt open <branch> "description"` | Slug from description (mirrors `wt new`), avoids collision |

When description is provided:
- Slug derived from description, not branch name
- Work branch: `wt/<slug>`
- `.wt-meta` records the description

### 2. Branch listing (no args)

When called with no arguments:
- Print local branches, then remote-tracking branches (with `origin/` prefix preserved)
- Filter out `wt/*` branches (worktree working branches)
- Filter out `HEAD` detached refs
- Output to **stderr** so the shell wrapper doesn't try to `cd`
- Exit non-zero so the wrapper's `&&` short-circuits

### 3. cd issue

`cmd_open` already prints the path to stdout (line 363). The shell wrapper header already lists `open`. This is a user-side config issue if the local `~/.zshrc` wrapper is outdated.

**Action:** Add a test verifying `cmd_open` prints only the worktree path to stdout. Docs should mention updating the shell wrapper.

### 4. Existing worktree navigation (no code changes)

Already covered by:
- `wt go <branch-or-slug>` — navigate to a worktree
- `wt abandon` — delete a worktree
- `wt list` — see all worktrees

Docs should clarify this for discoverability.

## Out of scope

- Auto-creating local tracking branches from remote refs (user runs `git fetch`/`git checkout` themselves)
- Interactive selection (fzf, etc.)
- New commands or renames
