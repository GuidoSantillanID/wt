# wt go — Design Spec

**Date:** 2026-03-25

## Problem

After closing a shell, there is no way to navigate back to an existing worktree without running `wt list`, reading the path, and `cd`-ing manually.

## Solution

Add `wt go <identifier>` command that prints the worktree path to stdout so the shell wrapper can `cd` into it — same pattern as `wt new`, `wt finish`, `wt abandon`.

## Command

```
wt go <branch-or-slug>
```

**Identifier matching** (exact, case-sensitive):
- Matches against `branch` field in `.wt-meta` (e.g. `wt/fix-shell-dir`)
- Also matches against `slug` field (e.g. `fix-shell-dir`)
- Branch match takes priority; falls back to slug

**Outcomes:**
- Single match → print worktree path to stdout; exit 0
- No match → error to stderr; exit 1
- Multiple matches → list matches to stderr; exit 1

## Implementation

### `cmd_go()` in `bin/wt`

1. Require exactly one argument; error if missing
2. Iterate all registered projects' worktrees (same loop as `cmd_list`)
3. For each worktree with a valid `.wt-meta`, collect matches where `branch == arg` or `slug == arg`
4. Single match: `echo "$wt_dir"` to stdout, exit 0
5. No match: `error "No worktree found for: '$arg'"`, exit 1
6. Multiple matches: list each match path to stderr, `error "Ambiguous: multiple matches for '$arg'"`, exit 1

### Shell wrapper update

Add `go` to the cd-capturing branch:

```bash
if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" || "$1" == "go" ]]; then
```

Update all relevant docs: comment block at the top of `bin/wt` (both zsh and bash examples), `wt help` output, `README.md`, `CONTRIBUTING.md`, `docs/DEVELOPMENT.md`.

### Registry loop

Use the same empty-array guard as `cmd_list` (Bash 3.2 compat):
```bash
for project_root in "${REGISTERED_PROJECTS[@]+"${REGISTERED_PROJECTS[@]}"}"; do
```

### Dispatch

Add to `main()`:
```bash
go) cmd_go "$@" ;;
```

## Tests

- `wt go wt/<slug>` — capture stdout with `2>/dev/null`; assert `stdout == worktree_path`; exit 0 (branch match)
- `wt go <slug>` — capture stdout with `2>/dev/null`; assert `stdout == worktree_path`; exit 0 (slug match)
- `wt go nonexistent` — exits non-zero; stderr contains "No worktree found"
- `wt go` (no arg) — exits non-zero; stderr contains usage error
- Multiple matches — requires two separate git repos both registered in the same `WT_REGISTRY`, each with a worktree sharing the same slug; assert exit non-zero and stderr lists both paths
- `wt help` output — assert stdout contains `wt go`

## Out of Scope

- Fuzzy/partial matching
- Interactive picker
