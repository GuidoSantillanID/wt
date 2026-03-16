# Registry-Based Worktree Discovery

**Date:** 2026-03-13
**Status:** Draft

## Problem

`wt list` discovers worktrees by scanning `PROJECT_SEARCH_PATHS` (`~/src`, `~/projects`, `~/repos`,
`~/code` by default) with `find -maxdepth 4`. Projects outside these paths are invisible to `wt list`
and `wt doctor`, even though `wt new` happily creates worktrees in them (via `git rev-parse
--show-toplevel`).

## Solution

Replace path scanning with a project registry. `wt new` registers each project root; `wt list` and
`wt doctor` read the registry. When the last worktree in a project is cleaned up and no `wt/*`
branches remain, the project is auto-unregistered.

## Registry File

- Path: `${XDG_CONFIG_HOME:-$HOME/.config}/wt/projects`
- Format: one absolute path per line, no quoting, no comments
- Override: `WT_REGISTRY` env var (for tests and CI)
- Example:
  ```
  /Users/guido/Documents/dev/wt
  /Users/guido/src/myapp
  ```

## API Changes

### Removed

- `PROJECT_SEARCH_PATHS` array
- `WT_SEARCH_PATHS` env var
- `~/.config/wt/config` config file (path-per-line format)
- `_load_search_paths()` function
- `find_project()` function
- `wt new <project-name> <desc>` two-arg form — project names are ambiguous (basename collisions,
  no canonical location). Users must `cd` into the repo and run `wt new <desc>`.

### Added

- `REGISTRY_FILE` constant — `${WT_REGISTRY:-${XDG_CONFIG_HOME:-$HOME/.config}/wt/projects}`
- `_load_registry()` — reads `REGISTRY_FILE` into `REGISTERED_PROJECTS` array; called at top level.
  Creates parent dir if needed. Returns empty array if file doesn't exist.
- `_register_project(path)` — appends `path` to `REGISTRY_FILE` if not already present
  (`grep -qxF` check, then append)
- `_unregister_project(path)` — removes `path` from `REGISTRY_FILE` (grep -v + temp file + mv)
- `WT_REGISTRY` env var — overrides the registry file path (for test isolation and CI)

### Modified

- `cmd_new` — calls `_register_project($project_root)` after resolving project root. Two-arg form
  removed; only `wt new <desc>` from inside a repo. Argument parsing: `$# == 1` is the only valid
  non-flag arg count.
- `cmd_list` — iterates `REGISTERED_PROJECTS`, finds `.wt-meta` files via
  `<root>/.worktrees/*/.wt-meta` glob (no recursive `find`).
- `cmd_doctor` — iterates `REGISTERED_PROJECTS` instead of scanning search paths.
- `_cleanup_worktree` — after removing worktree, checks if `.worktrees/` is empty AND no `wt/*`
  branches remain in the project. If both true, calls `_unregister_project`.
- `cmd_help` — remove project arg from `wt new` usage, remove search-path config docs, add registry
  info.

## Documentation Updates

All of these must be updated to reflect the registry change:

- `bin/wt` header comment (references `WT_SEARCH_PATHS`, `~/.config/wt/config`)
- `bin/wt` `cmd_help()` (references search paths, two-arg `wt new`)
- `README.md` "Configure search paths" section → replace with registry docs
- `docs/DEVELOPMENT.md` — references `PROJECT_SEARCH_PATHS`, `WT_SEARCH_PATHS`, `find_project()`,
  `_load_search_paths()` in ~15 places
- `install.sh` — prints `export WT_SEARCH_PATHS=...` guidance; update to mention `WT_REGISTRY` or
  remove

## Test Changes

- `wt()` helper: replace `WT_SEARCH_PATHS="$test_base"` with `WT_REGISTRY="$registry_file"` pointing
  at a temp file. All test invocations using `WT_SEARCH_PATHS` updated similarly.
- Remove `config — WT_SEARCH_PATHS env var` test section
- Add tests:
  - Registry populated after `wt new` (project root appears in file)
  - Project unregistered after last worktree removed via `wt finish`/`wt drop`
  - Project NOT unregistered if `wt/*` branches still exist (orphan case)
  - `wt list` finds worktrees via registry
  - `wt new` with two args errors out
  - Auto-unregister fires when both conditions met (empty `.worktrees/` + no `wt/*` branches)
- Update all test invocations that use `WT_SEARCH_PATHS`

## Edge Cases

- Registry file doesn't exist yet → `_load_registry` returns empty array, `_register_project`
  creates it
- Project root in registry no longer exists on disk → `cmd_list` skips silently; `cmd_doctor` offers
  to unregister the stale entry
- Concurrent writes → unlikely (human-driven CLI); grep-check + append is sufficient
- `wt new` from a worktree → resolves to main checkout (existing behavior), registers that path
- Orphaned `wt/*` branches after worktree cleanup → project stays registered; `wt doctor` can still
  find and clean them
