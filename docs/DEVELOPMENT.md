# wt — Development & Architecture

> Design reference for contributors and for a future Go/Rust port. Covers architecture, all command algorithms, design history, and bug log.

---

## Architecture & Design

### Data model: `.wt-meta`

A plain `key=value` text file written to the root of each worktree. No quoting — values are plain text, no newlines allowed.

```
base_branch=dev
created=2026-03-10T14:30:00
description=fix the sidebar overflow bug
project=my-app
project_root=/home/user/projects/my-app
slug=fix-the-sidebar-overflow-bug
branch=wt/fix-the-sidebar-overflow-bug
```

**Reading:** `grep "^key=" file | head -1 | cut -d= -f2-` — no eval, no injection risk. All seven fields are required for `wt finish`/`wt drop`. `wt list` needs `branch`, `base_branch`, `description`, `project`, `created`.

This file is the source of truth for `wt finish`/`wt drop` (knows where to merge back) and `wt list` (knows the task description). The file is excluded from `git status` via `.git/info/exclude` (worktree-local gitignore), so it doesn't inflate the dirty count.

**Go/Rust note:** Parse with a simple line scanner. Split on first `=`. Store as a struct:

```rust
struct WtMeta {
    base_branch: String,
    created: String,          // ISO8601, parse with chrono
    description: String,
    project: String,
    project_root: PathBuf,
    slug: String,
    branch: String,
}
```

### File layout convention

```
<project_root>/
  .git/                       # main checkout .git dir
  .worktrees/
    <slug>/
      .git                    # file (worktree pointer, not a dir)
      .wt-meta                # metadata
      ... (full working tree)
```

The `.worktrees/` dir is excluded from git via `.git/info/exclude` (not `.gitignore`). This keeps it repo-local and out of committed history. Same for `.wt-meta`.

**Why `info/exclude`?** `.gitignore` would be committed, requiring every team member to have it. `info/exclude` is per-repo-clone and never committed. `wt` appends both patterns only if not already present (idempotent).

### Slug generation

```
"Fix the Sidebar Overflow Bug!" → "fix-the-sidebar-overflow-bug"
```

Algorithm:
1. Lowercase
2. Strip everything except `[a-z0-9 -]`
3. Collapse spaces → single `-`
4. Truncate to 50 chars
5. Strip trailing `-`

Bash implementation:
```bash
slug=$(echo "$desc" \
  | tr '[:upper:]' '[:lower:]' \      # lowercase
  | sed 's/[^a-z0-9 -]//g' \          # strip special chars
  | tr -s ' ' '-' \                   # spaces to hyphens
  | cut -c1-50 \                      # max 50 chars
  | sed 's/-$//')                     # strip trailing hyphen
```

**Go/Rust note:** Use a regex or char filter. Watch out for Unicode — the bash version uses `tr '[:upper:]' '[:lower:]'` which is locale-aware; explicit ASCII lowercase is safer and matches actual usage.

### Configuration system

```
Priority 1: WT_SEARCH_PATHS env var (colon-separated)
Priority 2: ${XDG_CONFIG_HOME:-~/.config}/wt/config (one path per line, # comments, blank lines ok)
Priority 3: ~/src  ~/projects  ~/repos  ~/code
```

The search paths tell `wt` where to look for projects by name (`wt new myapp "desc"`) and where to scan for active worktrees (`wt list`, `wt doctor`).

Implemented as `_load_search_paths()` called at startup.

**Go/Rust note:** Simple struct with a `Vec<PathBuf>` field. Load at startup. Expand `~` to `$HOME` (Go: `os.UserHomeDir()`; Rust: `dirs::home_dir()`). For config file path, use `os.UserConfigDir()` / `dirs::config_dir()`.

### Shell wrapper (the cd trick)

A subprocess can't change the parent shell's working directory. The shell wrapper works around this:

```bash
function wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "done" || "$1" == "drop" ]]; then
    local dir
    dir=$(command wt "$@") && [[ -n "$dir" ]] && cd "$dir"
  else
    command wt "$@"
  fi
}
```

The binary prints the target path on stdout. The wrapper captures it and calls `cd`. All other output (UI messages) goes to stderr.

**Go/Rust note:** This wrapper is required regardless of implementation language. The binary must:
- Print worktree path to stdout on `new` (new worktree path)
- Print main worktree path to stdout on `finish`/`drop` (for cd-back)
- Print nothing to stdout for `list`, `doctor`, `help`
- Print all UI (info, success, warn, error) to **stderr**

### Color/output system

```bash
if [[ -t 1 ]]; then  # check stdout fd 1 (not stderr) — wt list writes to stdout
  RED/YELLOW/GREEN/CYAN/BOLD/RESET = ANSI codes
else
  all = ""  # clean output when piped
fi
```

**Why stdout, not stderr?** `wt list` writes its table to stdout. Piping `wt list | grep` must not leak ANSI codes. Other commands write UI to stderr only, so `-t 2` would be fine for them — but using `-t 1` uniformly is simpler and correct for the piping case.

**Go/Rust note:** Use `isatty(1)` (stdout). Libraries: Go → `github.com/mattn/go-isatty`; Rust → `atty` or `is-terminal` crate.

### External dependencies

| Dependency | Usage | Notes |
|---|---|---|
| `git` | All operations | Requires 2.5+ for `git worktree` |
| `tmux` | Session kill on cleanup; `display-message -p '#S'` | Optional — all tmux paths are guarded by `[[ -n "${TMUX:-}" ]]` |
| `find` | `wt list`, `wt doctor` — scan for `.wt-meta` files | POSIX `find` — no GNU extensions used |
| `date` | `human_age()` — timestamp to seconds | GNU `date -d` or BSD `date -j -f` |
| `sed`, `tr`, `cut` | `slugify()`, `read_meta()` | POSIX |

A Go/Rust port eliminates all of these as external processes except `git`.

---

## Command implementations

### `wt new [project] "<description>"`

```
1. Parse args: 0 args → error; 1 arg → description (use git rev-parse --show-toplevel); 2 args → project name + description
2. If project arg: find_project() — search each WT_SEARCH_PATHS entry for $base/$name/.git (dir or file)
3. Resolve main worktree: if inside a worktree (.git is a file), call get_main_worktree() to get the actual root
4. Slugify description → branch = "wt/<slug>", worktree_path = "<project_root>/.worktrees/<slug>"
5. Conflict checks: worktree dir exists? → error; branch exists? → error
6. Capture base_branch = $(git symbolic-ref --short HEAD)
7. mkdir -p <project_root>/.worktrees
8. Add ".worktrees/" to <project_root>/.git/info/exclude (if not present)
9. git worktree add <worktree_path> -b <branch>
10. Write .wt-meta
11. Add ".wt-meta" to GIT_COMMON_DIR/info/exclude (if not present)
12. Detect package manager: uv.lock → uv, poetry.lock → poetry, requirements.txt/pyproject.toml → pip; package.json + pnpm-lock.yaml → pnpm, yarn.lock → yarn, else → npm
13. If package manager detected: warn + prompt to install
14. Print worktree_path to stdout (shell wrapper uses this to cd)
```

### `wt finish [--yes|-y]`

```
1. git rev-parse --show-toplevel → repo_root
2. Verify: repo_root/.git is a FILE (not a dir) → you're in a worktree; dir → error "main checkout"
3. Read .wt-meta: base_branch, branch, description, project, project_root, slug
4. Validate: no uncommitted changes (git status --porcelain)  ← not skipped by --yes
5. [if TMUX] Check claude_running_in_session (stubbed to false by default) → warn + confirm  ← skipped by --yes
6. Confirm: "Rebase <branch> onto <base_branch> and fast-forward?"  ← skipped by --yes
7. get_main_worktree()
8. git fetch origin <base_branch> (best-effort, ignore failure)
9. git rebase <base_branch>  (in repo_root context)
   → on conflict: git rebase --abort; print manual instructions; exit 1
10. Fast-forward:
    a. Try: git fetch . HEAD:<base_branch> (works if base_branch not checked out here)
    b. Fallback: git -C <main_wt> merge --ff-only <branch> (if main_wt is on base_branch)
    c. Else: print manual instructions; exit 1
11. _cleanup_worktree(repo_root, branch, main_wt, project, slug, force=true)
12. Print main_wt to stdout (shell wrapper uses this to cd back)
```

### `wt sync`

```
1. git rev-parse --show-toplevel → repo_root
2. Verify: repo_root/.git is a FILE → in a worktree; dir → error "main checkout"
3. Read .wt-meta: base_branch, branch, description
4. Validate: no uncommitted changes (git status --porcelain)
5. git fetch origin <base_branch> (warn on failure, continue)
6. Resolve rebase target:
   - if origin/<base_branch> ref exists → use it (ensures remote state)
   - else fall back to local <base_branch>
7. git rebase <rebase_target>
   → on conflict: git rebase --abort; print manual instructions; exit 1
8. Print success — no stdout output, no cleanup
```

Key difference from `wt finish`: rebases onto `origin/<base_branch>` (not local), no confirmation, no fast-forward, no cleanup, no cd.

### `wt drop [--yes|-y]`

```
1-3. Same as finish (verify worktree, read meta, validate slug/branch)
4. [if dirty] warn + confirm "drop anyway?"  ← skipped by --yes
5. [if TMUX] claude_running_in_session check  ← skipped by --yes
6. Confirm: "Drop <branch>? (no merge)"  ← skipped by --yes
7. get_main_worktree()
8. _cleanup_worktree(repo_root, branch, main_wt, project, slug, force=true)
9. Print main_wt to stdout
```

### `_cleanup_worktree` (shared)

```
1. git -C <main_wt> worktree remove <repo_root> --force
2. git -C <main_wt> branch -D <branch>  (force=true → -D; force=false → -d)
3. [if TMUX]
   a. session_name = "<project>/<slug>" (dots → underscores)
   b. if tmux session exists:
      - if current session == session_name: switch to "<project>" session first (else warn, return)
      - tmux kill-session -t <session_name>
```

### `wt list`

```
1. For each search path in PROJECT_SEARCH_PATHS:
   find <base> -maxdepth 4 -name ".wt-meta" -path "*/.worktrees/*" | sort
2. For each .wt-meta found:
   - Read: branch, base_branch, description, project, created
   - Skip if branch is empty or git rev-parse fails (stale worktree)
   - dirty_count = wc -l < (git status --porcelain)
   - ahead = git rev-list --count <base_branch>..HEAD
   - age = human_age(created)
   - Group by project name (print project header when it changes)
   - printf the row
3. If nothing found: print "No active worktrees found." to stderr
```

**Columns:** `branch (40ch) | ahead | dirty/clean | age | "description"`

### `wt doctor`

```
For each search path:
  For each direct subdir of <base> (find -maxdepth 1 -mindepth 1 -type d):
    Skip if: not a git repo (.git dir missing) OR no .worktrees/ dir

    Check 1 — Orphaned wt/* branches:
      git branch --list 'wt/*' → for each branch, check if .worktrees/<slug>/ exists
      → offer to git branch -D

    Check 2 — Orphaned worktree dirs:
      for each .worktrees/*/: check if it's in `git worktree list --porcelain`
      → offer to rm -rf

    Check 3 — Corrupt .wt-meta:
      for each .worktrees/*/.wt-meta: verify base_branch, branch, slug non-empty
      → report only (no auto-fix)

    Check 4 — Missing .worktrees/ in info/exclude
      → offer to append

    Check 5 — Missing .wt-meta in info/exclude
      → offer to append

    Check 6 — Stale git worktree registrations:
      git worktree list --porcelain → paths not in main worktree that don't exist on disk
      → offer to git worktree prune + branch -D for each stale slug

    Print result per project (only projects with issues unless it's the first)
```

**fd trick:** The outer project loop uses `fd 4` and inner branch/worktree loops use `fd 5`. This keeps `fd 0` (stdin) free for `confirm()` interactive prompts. Go/Rust doesn't need this — use an iterator + synchronous stdin read.

### `human_age()` — cross-platform timestamp→age

```bash
now=$(date +%s)
then=$(date -d "$ts" +%s 2>/dev/null) \        # GNU date (Linux)
  || then=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null) \  # BSD date (macOS)
  || then="$now"
diff=$(( now - then ))
```

**Go:** `time.Parse("2006-01-02T15:04:05", ts)` + `time.Since()`
**Rust:** `chrono::NaiveDateTime::parse_from_str(ts, "%Y-%m-%dT%H:%M:%S")` + `.signed_duration_since()`

Output format: `Xm ago`, `Xh ago`, `Xd ago`, `Xw ago` (< 1h, < 1d, < 7d, ≥ 7d).

### `get_main_worktree()`

```bash
git worktree list --porcelain | awk '/^worktree / { if (first=="") first=$2 } END { print first }'
```

The first entry in `git worktree list --porcelain` is always the main worktree. Works even when called from inside a linked worktree.

### `find_project()`

Searches each `PROJECT_SEARCH_PATHS` entry for `$base/$name` where `.git` is either a directory (main checkout) or a file (linked worktree — unusual but valid). Returns the first match.

---

## Safety invariants

1. **Never merge with uncommitted changes** — always check `git status --porcelain` before rebase/ff
2. **Always fast-forward (never --no-ff)** — preserves linear history
3. **Rebase before fast-forward** — handles base drift; if rebase fails, abort and print manual instructions
4. **Never eval `.wt-meta` values** — parse with string split, never shell-eval
5. **`info/exclude` over `.gitignore`** — keep `.worktrees/` and `.wt-meta` out of committed gitignore
6. **stdout is reserved for path output** — all UI to stderr; the shell wrapper depends on this contract
7. **tmux operations are always optional** — guard every tmux call with an "are we in tmux?" check

---

## Known edge cases

| # | Edge case | Handling |
|---|---|---|
| 1 | `wt new` from inside a worktree | Detect `.git` file vs dir; redirect to main checkout via `get_main_worktree()` |
| 2 | Base branch checked out in main worktree during ff | Can't `git fetch . HEAD:<base>` (ref locked); fall back to `git -C $main_wt merge --ff-only` |
| 3 | `wt finish`/`drop` from same tmux session being killed | Switch to project main session first; if no other session exists, warn and skip kill |
| 4 | `wt new` with apostrophes in description | Slugify strips them; `.wt-meta` preserves them verbatim (no shell quoting) |
| 5 | `wt list` with dirty worktrees | Color the dirty count yellow; `.wt-meta` excluded via `info/exclude` so it doesn't count |
| 6 | `wt doctor` on repos that never used `wt` | Skip repos without a `.worktrees/` dir |
| 7 | `read_meta` on missing key | Returns empty string via `|| true` — never exits non-zero |
| 8 | `wt list` performance | `-maxdepth 4` on find — `.wt-meta` is always at exactly depth 4 from search base |
| 9 | `git branch -d` after rebase | Branch guaranteed linear, but use `-D` always — avoids failure when main_wt is on a different branch |
| 10 | `git branch --list` output format | Strips `"  "` prefix (non-current), `"* "` (current), `"+ "` (checked out in another worktree — skip) |

---

## Design history

### Problem statement

Parallel Claude Code development in Ghostty → tmux requires creating multiple git worktrees. The pain points before this tool:

1. **Tedious setup** — `git worktree add`, mkdir, manual branch naming, no tmux integration. High friction kills flow.
2. **Opaque naming** — Claude Code's built-in worktrees create random names (e.g. `worktree/asda-asda-asda`). No way to tell what work is in which branch.
3. **Lost changes on cleanup** — No safety checks before removing worktrees. Easy to forget to merge before running cleanup.
4. **Fragmented merge flow** — No standard way to merge back, keep in sync with main/dev, then remove both worktree and branch atomically.
5. **Sessionizer disconnect** — The tmux-sessionizer didn't surface worktrees from non-standard paths.

### Existing environment (at design time)

- **Terminal stack**: Ghostty → tmux (prefix Ctrl+a) → multiple sessions/windows
- **tmux-sessionizer**: `~/.local/bin/tmux-sessionizer` — scans `~/Documents/dev` and `~/Documents/lab`, depth 3 for `.worktrees/*`, creates tmux sessions named `project/branch`
- **claude() wrapper** in `.zshrc`: renames tmux window to "✳ claude", sets `@is_claude_running`, restores on exit
- **Claude Code hooks**: `@claude_done` flag + audio notifications on stop
- **Previous system**: Conductor (`~/conductor/`) — city-named worktrees in a separate directory tree. Abandoned because: required a separate UI, weaker Claude Code integration.

### Approaches considered

**Approach 1: Single bash script (CHOSEN)**
`~/.local/bin/wt` — ~700 lines of bash + thin zsh wrapper in `.zshrc`.

Trade-offs:
- (+) Zero deps, single file, debuggable with `bash -x`
- (+) All UI output goes to stderr; stdout is clean for returning paths to the zsh wrapper
- (-) Bash string processing slightly fragile for edge cases (unicode, quotes in descriptions)
- (-) No per-project config

**Approach 2: Bash + config + zsh completions**
Same script + `~/.config/wt/config` + `_wt` completion function. More files (3 vs 1), per-project merge target config, history log. Not chosen because the extra complexity wasn't needed for the first version.

**Approach 3: Full zsh plugin**
`~/.oh-my-zsh/custom/plugins/wt/` with modular files. Best UX (native `cd`, prompt integration, pure zsh string ops). Not chosen for v1 — too much upfront complexity. Viable upgrade path if Approach 1 proves limiting.

### Key design decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Worktree location | `<project>/.worktrees/<slug>/` | sessionizer already scans this path |
| Branch naming | `wt/<auto-slug>` from description | readable, namespaced, no manual naming |
| Merge target | branch active at creation (stored in `.wt-meta`) | survives shell sessions, explicit over implicit |
| Integration strategy | rebase onto base, then fast-forward | always linear history; no merge commits |
| Dependency install | prompt (not default) | pnpm/npm install can be slow; user decides |
| Claude running check | warn + confirm, don't block | safety without being obstructive |
| Dirty check | abort | never lose uncommitted work silently |
| Sessionizer | zero changes needed | `.worktrees/*` already scanned at depth 3 |

### Merge flow detail

The hardest part of the implementation. Options evaluated:

1. **`git fetch . HEAD:$target`** (fast-forward from worktree itself) — cleanest, no checkout needed. Works only if ff is possible.
2. **`git -C $main_wt merge --no-ff wt/$slug`** — requires main worktree to have `$target` checked out. Need to detect this.
3. **Temp worktree for merging** — robust but complex. Skipped for v1.
4. **`git update-ref`** — low-level, risky if user doesn't understand what happened.

Chosen for v1: try (1) first. On ff failure, check if main worktree has target checked out and use (2). On conflict, abort and print manual instructions.

Changed in v7: replaced with rebase + fast-forward strategy. Old: ff-first, `--no-ff` fallback. New: `git rebase <base>` → `git fetch . HEAD:<base>` (ff). Always linear history, handles base drift cleanly.

```
Old: ff → --no-ff fallback → conflict abort
New: rebase onto base → guaranteed ff → conflict abort (at rebase stage)
```

---

## Bug & iteration log

### v1 fixes (post-initial-implementation)

Ten issues found and fixed before first use:

1. **Dead function removed** — `main_worktree_path()` was unused; deleted
2. **stdout/stderr separation** — All `info()`/`success()` output now goes to stderr; stdout is reserved for path output to the zsh `cd` wrapper
3. **Safe `.wt-meta` parsing** — Values single-quoted on write; `read_meta()` (grep/sed) replaces `source` — no eval, no injection risk
4. **`wt done` cd-back** — zsh wrapper now handles `done` the same as `new`; `cmd_done` prints main worktree path on stdout for the wrapper to cd into
5. **Lockfile detection fixed** — Checks `${worktree_path}/pnpm-lock.yaml` instead of project root (worktrees have their own file copies)
6. **Nested worktree detection** — `wt new` from inside a worktree now resolves to the real main checkout instead of creating a nested worktree
7. **ff failure reason shown** — Removed `2>/dev/null` from fast-forward attempt; actual git error shown as warning before fallback
8. **Auto-gitignore** — `wt new` appends `.worktrees/` to `.gitignore` if missing
9. **Self-kill protection** — `wt done` switches to project main tmux session before killing the current one; warns gracefully if no other session exists
10. **Flexible find depth** — `wt list` no longer hardcodes `-mindepth 4 -maxdepth 4`; uses path pattern matching instead

### v3 fixes (second review pass)

11. **`.wt-meta` quoting incompatibility** — v2 used shell-style `'\''` escaping for single quotes but `read_meta()` used dumb sed stripping, not shell parsing. Fixed by removing all quoting — plain `key=value`, values read with `cut -d= -f2-`
12. **`.wt-meta` inflated dirty count** — Every worktree showed "1 dirty" because `.wt-meta` was untracked. Fixed by appending `.wt-meta` to `.git/info/exclude` (worktree-local gitignore, doesn't affect repo)
13. **Color detection on wrong fd** — Colors were set based on stderr being a terminal (`-t 2`), but `wt list` writes to stdout. Piping `wt list | ...` leaked escape codes. Fixed by checking stdout (`-t 1`)
14. **`find_project` didn't verify git repo** — Would silently accept any directory; git errors were confusing. Fixed by checking for `.git` dir or file before returning
15. **Added `wt drop`** — New command to abandon a worktree without merging. Uses `git branch -D` (force). Same safety checks as `wt done` (dirty warning, Claude check, confirm)
16. **Better ff failure message** — When fast-forward fails because target is checked out elsewhere, now shows which worktree has it checked out instead of a raw git error

### v4 fixes (TDD coverage pass — 2026-03-11)

Expanded `wt-test` from 38 → 53 tests covering previously untested paths. Two tool bugs surfaced:

17. **FF branch not deleted when main_wt is on a different branch** — `_cleanup_worktree` used `git branch -d` (safe-delete), which checks if the branch is merged into the *currently checked out* branch in `$main_wt`. After a fast-forward merge where `$main_wt` was temporarily on `main` (not `dev`), `-d` failed silently. Fixed by always using `-D` (force-delete) in `cmd_done` — the branch is guaranteed merged at that point.
18. **`git merge --no-ff` and `git branch -d/-D` output leaked to stdout** — These git commands printed summaries to stdout, polluting the path returned to the zsh `cd` wrapper. Fixed by appending `>&2` to both in `_cleanup_worktree` and the `--no-ff` merge call.

### v5 fixes (first real-world walkthrough — 2026-03-12)

Two bugs found during manual walkthrough:

19. **`wt drop` didn't cd back after removing worktree** — Zsh wrapper only intercepted `new` and `done` for the `cd` behavior. `cmd_drop` already printed `$main_wt` on stdout (same as `cmd_done`), but the wrapper silently discarded it. Fixed by adding `"drop"` to the condition in the zsh wrapper.
20. **`wt list` took ~12s** — `find` had no depth limit, traversing all of `~/Documents/dev` and `~/Documents/lab` including `node_modules`, `.next`, build caches, etc. `.wt-meta` is always at exactly depth 4 from the search base (`<base>/<project>/.worktrees/<slug>/.wt-meta`). Fixed by adding `-maxdepth 4`.

### v6: `wt doctor` (2026-03-12)

State health check with interactive fixes. Scans `PROJECT_SEARCH_PATHS` for real-world drift that `wt-test` can't catch (orphaned branches/dirs, corrupt `.wt-meta`, stale git registrations, missing `info/exclude` entries).

**Design:**
- Implemented as `cmd_doctor` in the main `wt` script (shares all helpers: `read_meta`, color functions, `confirm`)
- Uses fd 4 (project loop) and fd 5 (branch/worktree loops) to keep fd 0 free for `confirm()` interactive prompts
- Groups output by project; skips projects with no `.worktrees/` dir
- 6 checks: orphaned branches, orphaned dirs, corrupt meta (report only), missing excludes ×2, stale registrations

Bugs found during implementation:

21. **`read_meta` returned non-zero on missing keys** — `grep | head | cut` pipeline exits with grep's status (1) when the key is absent. Under `set -euo pipefail`, `m_branch=$(read_meta ...)` then caused an immediate script exit, producing empty `wt doctor` output for corrupt `.wt-meta` entries. Fixed by appending `|| true` to the pipeline in `read_meta`.
22. **Checks 4 & 5 fired on every git repo** — The `info/exclude` checks ran for all repos in `PROJECT_SEARCH_PATHS`, flagging dozens of repos that had never used `wt`. Fixed by adding `[[ -d "${project_root}/${WORKTREES_DIR}" ]] || continue` at the top of the project loop.

### v7: `wt finish` + rebase strategy (2026-03-12)

Two changes shipped together:

**1. `wt done` → `wt finish`**
`done` is not a standard CLI verb. `finish` has `git flow finish` precedent and better describes the lifecycle action. `done` kept as a hidden alias for backward compat.

**2. Merge strategy → rebase + fast-forward**
Old: ff-first, `--no-ff` fallback. Created merge commits when base had moved.
New: `git rebase <base>` → `git fetch . HEAD:<base>` (ff). Always linear history.

If `base_branch` is checked out in the main worktree, falls back to `git -C $main_wt merge --ff-only $branch` (safe since rebase guarantees linearity).

### v8: Public repo + portability cleanup (2026-03-12)

Extracted `wt` into a standalone public GitHub repo. Goal: anyone can clone and run in 2 minutes.

23. **Configurable search paths** — Replaced hardcoded paths with a three-tier config system: `WT_SEARCH_PATHS` env var → `~/.config/wt/config` → defaults. Implemented as `_load_search_paths()` called at startup.
24. **Cross-platform date parsing** — `human_age()` now tries GNU `date -d` first (Linux), falls back to BSD `date -j -f` (macOS).
25. **`claude_running_in_session()` stubbed to `false`** — Removed personal tmux option check. Function now always returns false. Documented as an override hook.
26. **Removed personal doc references** — Lines referencing local dev files removed from header and help output. README replaces the usage guide.
27. **Python package manager detection improved** — Added `uv.lock` → `uv` and `poetry.lock` → `poetry` detection before the `pip` fallback. Order: `uv.lock → poetry.lock → requirements.txt → pyproject.toml`.
28. **Shell wrapper documented for both zsh and bash** — Header now shows both `.zshrc` and `.bashrc` forms.
29. **`wt-test` switched to `WT_SEARCH_PATHS`** — Test suite now uses `WT_SEARCH_PATHS="$test_base" bash "$WT"` instead of `HOME="$FAKE_HOME" bash "$WT"`.
30. **New tests added (69 → 71):** config env var; `human_age()` output format validation.
31. **CI added** — `.github/workflows/test.yml` runs `bin/wt-test` on `macos-latest` and `ubuntu-latest` on every push/PR. macOS step installs bash 4+ via brew.
32. **Repo structure finalized:**
    ```
    wt/
      bin/wt              # the tool
      bin/wt-test         # test suite
      install.sh          # symlinks bin/wt to ~/.local/bin/wt
      README.md
      LICENSE             # MIT
      .github/workflows/test.yml
    ```

### v9: `--yes`/`-y` flag for `wt finish` and `wt drop` (2026-03-12)

**Problem:** `confirm()` calls `read -r response` from stdin. Claude Code's Bash tool has no interactive stdin — `read` gets EOF, confirmation always fails, `wt finish`/`wt drop` always abort.

**Fix:** Add `--yes`/`-y` flag to both commands. When set, all `confirm()` calls are bypassed. The dirty-file check in `cmd_finish` is `error()` not `confirm()`, so it is intentionally **not** skipped — never auto-merge dirty work. The dirty-file check in `cmd_drop` **is** skipped — deliberately dropping dirty work is the point of `--yes` on drop.

33. **`wt finish --yes` / `wt drop --yes`** — Non-interactive flag skips confirmation prompts. Local `auto_yes=0` variable parsed at top of each function; `confirm()` calls wrapped in `if (( auto_yes == 0 ))`. Tests expanded from 79 → 95.

---

## Porting guide

### Why migrate, and why Go or Rust?

The bash implementation works well and has no known bugs after 8 iterations. A migration would be motivated by:
- Bash string handling is fragile around Unicode and edge-case descriptions
- No structured error type system (every failure is an `error()` call that prints and exits)
- Parallelizing `wt list` across many worktrees requires awkward process substitution
- Distributing a bash script to non-Unix platforms is a dead end

**Why not Python or Node?** Both require a runtime to be installed and version-pinned. `wt` is a system tool that needs to work in minimal environments (CI containers, fresh machines, dotfile bootstrapping). A single compiled binary with zero runtime dependencies is a better fit.

**Go** is the pragmatic choice. Fast compile times, trivial `git` CLI shell-outs, excellent cross-compilation (`GOOS=darwin/linux GOARCH=arm64/amd64`), and `cobra` for subcommand CLIs is battle-tested. The resulting binary is ~5MB. Concurrency is easy to add for parallelizing `wt list`. Standard library covers everything else.

**Rust** is the higher-investment choice. Zero-cost abstractions and a smaller binary, but the async/ownership model adds complexity for what is fundamentally a sequential, I/O-bound CLI. The payoff would be marginal for this tool's size. Rust makes more sense if `wt` grows to do heavier git introspection (parsing pack files, walking object graphs) where the `git2` crate's raw performance matters.

**Recommended path:** Go first. The bash → Go translation is mechanical (each function maps to a function, `exec.Command("git", ...)` replaces shell-outs), the test suite maps directly to `testing.T` subtests, and the concurrency story is simple. Revisit Rust only if distribution size or native git library integration becomes a hard requirement.

### Go port considerations

**CLI framework:** `cobra` — standard, good subcommand support, generates help automatically.

**Git operations:** Shell out to `git` (simplest, same as bash). Using `libgit2` (via `go-git`) is viable for reads but the rebase workflow is complex enough that shelling out is safer and matches user expectations (same git behavior, same `.gitconfig` hooks).

**Concurrency:** `wt list` runs sequentially in bash. A Go port could parallelize the per-worktree status checks (goroutines per meta file found) for a significant speedup on large installations.

**Config file path:** Use XDG explicitly: `filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "wt", "config")` with fallback to `~/.config/wt/config`.

**Color:** `github.com/fatih/color` or manual ANSI with `isatty` check.

**Testing:** Replace `wt-test` with Go tests that create temp git repos using `os.MkdirTemp` + `exec.Command("git", ...)`. Each `section()` becomes a `t.Run()`.

### Rust port considerations

**CLI framework:** `clap` with derive macros — clean subcommand definition.

**Git:** Shell out to `git` for simplicity. The `git2` crate (libgit2 binding) is powerful but rebase is not exposed — you'd still shell out for that.

**Config:** `dirs::config_dir()` gives the XDG config dir. `dirs::home_dir()` for `~` expansion.

**Color:** `colored` or `termcolor` crate with `is-terminal` for the tty check.

**Error handling:** Use `anyhow` for the main binary (simple propagation) and `thiserror` for structured error types. Most errors are "print and exit 1" so `anyhow` is sufficient.

**Testing:** `tempfile::TempDir` + `std::process::Command` to drive real git repos.

### Test coverage map (bash → port)

The bash `wt-test` has 71 tests as of v8. Each maps to a unit/integration test in a port:

| Test section | What it tests |
|---|---|
| wt help | command dispatch + help output |
| config — WT_SEARCH_PATHS | env var overrides default search paths |
| wt new — basic creation | dir created, meta written, stdout=path |
| wt new — .wt-meta contents | all 7 fields written correctly |
| wt new — single quotes | slugify strips apostrophes; description preserved verbatim |
| git status — .wt-meta excluded | info/exclude written correctly for both patterns |
| wt list — output | branch/clean/description columns present |
| wt list — age display | human_age() returns valid format |
| wt list — no ANSI when piped | tty check works |
| wt new — conflicts | duplicate worktree/branch → error |
| wt new — from inside worktree | redirects to main checkout |
| wt new — project-name arg | two-arg form from outside repo |
| wt new — nonexistent project | clear error message |
| wt finish — dirty check | blocks on uncommitted changes |
| wt finish — from main checkout | error message |
| wt drop — dirty double-confirm | two prompts for dirty worktree |
| wt drop — clean | single confirm, stdout=main_wt |
| wt finish — rebase + ff | rebase + fast-forward happy path |
| wt finish — diverged base | rebase handles base drift, linear history |
| wt finish --yes | skips confirmation, no stdin pipe |
| wt drop --yes | clean worktree, no stdin pipe |
| wt drop --yes (dirty) | skips dirty + main confirms |
| wt drop -y | short flag works |
| wt list — empty | "No active worktrees" message |
| wt doctor — clean | "all good" |
| wt doctor — orphaned branch | detect + fix |
| wt doctor — orphaned dir | detect + fix |
| wt doctor — corrupt meta | detect only |
| wt doctor — missing excludes | detect + fix |
| wt doctor — stale registration | detect + fix |

---

## Future ideas

- **`wt log`**: history of finished/dropped worktrees (currently no persistent log)
- **Per-project config** (`~/.config/wt/config`): default merge target, branch prefix, auto-tmux flag
- **Shell completions**: `wt new <TAB>` lists projects from search paths
- **Upgrade to Approach 3** (zsh plugin): if per-project config, completions, and prompt integration become needed
- **Conflict resolution flow**: offer to open `$EDITOR` with conflict markers or launch Claude in the worktree with conflict context
