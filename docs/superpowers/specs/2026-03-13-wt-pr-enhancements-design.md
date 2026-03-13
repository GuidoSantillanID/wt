# wt pr enhancements — Design Spec

**Date:** 2026-03-13
**Status:** Implemented

## Problem

`wt pr` had two friction points for established projects:

1. The base branch came from `.wt-meta` with no way to change it interactively
2. The PR body was always empty — reviewers had no context on what commits are in the PR

## Design decisions

### Base branch: interactive confirm/replace

When running `wt pr` interactively (no `--yes`), prompt to confirm or change the base branch. If changed, update `.wt-meta` so future `wt pr`/`wt sync`/`wt finish` use the new base.

- Lists remote branches from `git branch -r --list 'origin/*'`, strips HEAD refs, presents as numbered list
- Skipped with `--yes`

### PR title: unchanged

The `.wt-meta` description is used as-is. No prompt. The description is close enough for quick iteration and can be edited on GitHub after creation.

### PR body: auto-generated from commits

After rebasing, generate a bullet list from `git log --oneline --reverse base..HEAD`. Passed to `gh pr create --body`. No prompt — used directly in all modes including `--yes`.

```
- abc1234 fix redirect on login
- def5678 add test coverage
```

Falls back to empty string if git log fails.

## What was considered and rejected

- **Title prompt (confirm/replace):** Adds a y/N gate that most users would skip. The `.wt-meta` description is "good enough" as a starting point; editing the title on GitHub is lower friction than a terminal prompt.
- **Body editing via `$EDITOR`:** Multi-line editing in a terminal prompt is painful. Auto-generate and let the user edit on GitHub.
- **Template-based body:** Adds complexity (detecting/parsing `.github/PULL_REQUEST_TEMPLATE.md`). Git log is always available and always relevant.

## Implementation

- `bin/wt` — `cmd_pr`: base branch selection block (interactive), body generation (always)
- `bin/wt-test` — tests for base branch change, `--yes` skip, body content
- `README.md` — updated `wt pr` command reference
