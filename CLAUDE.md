# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`wt` is a single-file bash CLI (`bin/wt`, ~1130 lines) that automates git worktree lifecycle: create, sync, finish (rebase+ff+cleanup), drop, PR, list, doctor. Designed for parallel Claude Code + tmux workflows.

## Commands

```bash
# Run full test suite (stdin must be closed to avoid interactive prompt hangs)
bash bin/wt-test < /dev/null

# Preserve temp dir on failure for debugging
bash bin/wt-test --keep < /dev/null
```

Requires bash 4+ (`brew install bash` on macOS). CI runs on macOS + Ubuntu.

## Architecture

### Stdout/stderr contract

Commands that change directories (`new`, `finish`, `drop`) print **only the target path** to stdout. The shell wrapper (`function wt()` in user's rc file) captures this for `cd`. **All UI** (info, success, warn, error) goes to stderr. `wt list` is the exception — its table goes to stdout (for piping). Breaking this contract breaks the shell wrapper.

### Data model: `.wt-meta`

Plain `key=value` file in each worktree root. Seven fields: `base_branch`, `created`, `description`, `project`, `project_root`, `slug`, `branch`. Read with `read_meta()` (grep+cut, never eval). Source of truth for `finish`/`drop`/`sync`/`pr`/`status`.

### Registry

`~/.config/wt/projects` (override: `WT_REGISTRY` env var). One absolute path per line. Auto-registered on `wt new`, auto-unregistered when last worktree+branch cleaned up. `wt list` and `wt doctor` iterate the registry.

### Command dispatch

`main()` at bottom of `bin/wt` dispatches to `cmd_<name>()` functions. Aliases: `done`→`finish`, `st`→`status`, `ls`→`list`.

### Tests

`bin/wt-test` is an integration suite that creates real git repos in `/tmp`. Test framework: `section()` groups, `assert_eq`/`assert_contains`/`assert_not_contains`/`assert_file_exists`/`assert_dir_exists`. Every test invocation uses `WT_REGISTRY="$registry_file"` for isolation.

## Shell Conventions

- `set -euo pipefail` throughout
- Bash 3.2 empty-array guard: `"${arr[@]+"${arr[@]}"}"` (macOS system bash is 3.2)
- Never `eval` or `source` `.wt-meta` — parse with `grep | head | cut`
- `confirm()` reads from stdin — use `--yes`/`-y` flags or `< /dev/null` in scripts/CI
- Color detection checks stdout (`-t 1`), not stderr, because `wt list` pipes through stdout
- `fd 5` trick in `cmd_doctor` keeps stdin free for `confirm()` during inner loops

## TDD (Test-Driven Development)

Always use the **superpowers:test-driven-development** skill when implementing any feature or bugfix. Write tests first, then implement.

## Test Integrity

Tests define expected behavior. If a test fails, the implementation is wrong — not the test. Never weaken, skip, or delete tests to make them pass. Fix the code instead.

## Documentation is Mandatory

Every feature or change must update **all** relevant docs before the work is considered complete:

- `README.md` — command reference and usage examples
- `docs/DEVELOPMENT.md` — architecture and internals
- `CONTRIBUTING.md` — contributor instructions
- Inline help text in `bin/wt` (the comment block at the top and any `wt help` output)
