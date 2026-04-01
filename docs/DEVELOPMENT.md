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

**Reading:** `grep "^key=" file | head -1 | cut -d= -f2-` — no eval, no injection risk. All seven fields are required for `wt finish`/`wt abandon`. `wt list` needs `branch`, `base_branch`, `description`, `project`, `created`.

`wt open` creates the same format — `base_branch` is set to the target branch, `branch` is the new `wt/<slug>` branch. The slug comes from either the branch name (default) or a user-provided description (second positional argument). Both `wt new` and `wt open` worktrees support the full lifecycle (`finish`, `abandon`, `sync`, `retarget`, `pr`).

This file is the source of truth for `wt finish`/`wt abandon` (knows where to merge back) and `wt list` (knows the task description). The file is excluded from `git status` via `.git/info/exclude` (worktree-local gitignore), so it doesn't inflate the dirty count.

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

### Registry system

```
Registry file: ${XDG_CONFIG_HOME:-~/.config}/wt/projects
Override:      WT_REGISTRY env var (for tests and CI)
Format:        one absolute project path per line, no quoting
```

The registry tells `wt` which projects are active. `wt new` registers each project root automatically. `wt list` and `wt doctor` read the registry — no manual path configuration needed.

Auto-unregister: when `_cleanup_worktree` runs, if `.worktrees/` is empty/absent AND no `wt/*` branches remain, the project is removed from the registry.

Functions:
- `_load_registry()` — reads file into `REGISTERED_PROJECTS` array; called at startup
- `_register_project(path)` — appends path if not present (idempotent)
- `_unregister_project(path)` — removes path; deletes file if empty

**Go/Rust note:** Load at startup into `Vec<PathBuf>`. File path via `os.UserConfigDir()` / `dirs::config_dir()`. No `~` expansion needed — paths are stored as absolute.

### Shell wrapper (the cd trick)

A subprocess can't change the parent shell's working directory. The shell wrapper works around this:

```bash
function wt() {
  if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" || "$1" == "go" ]]; then
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
- Print worktree path to stdout on `go` (for cd-into)
- Print main worktree path to stdout on `finish`/`drop` (for cd-back)
- Print nothing to stdout for `list`, `doctor`, `help`
- Print all UI (info, success, warn, error) to **stderr**

### Tab completion (`config/wt-completion.zsh`)

A pure-zsh completion script. File I/O uses only builtins (no `grep`/`cut` forks per worktree). One subshell is spawned per completion call to capture the branch list — negligible cost (~1ms).

**Why avoid external forks?** Completion runs on every `<tab>` press. Calling `command wt` would parse 1400+ lines of bash and fork `grep|head|cut` pipelines per worktree — ~100-250ms per keypress. Builtins bring this to ~5ms.

**Two internal helpers:**

```zsh
_wt_read_meta_field FILE KEY  # sets REPLY via while-read + ${line#key=}, returns 1 if not found
_wt_list_branches             # reads registry → scans .wt-meta files → prints branch names
```

**Registry and meta paths:** same as the main binary — `${WT_REGISTRY:-~/.config/wt/projects}` and `<project>/.worktrees/*/.wt-meta`. The `(N)` glob qualifier suppresses errors on missing directories.

**`compdef` guard:** the helpers are always defined (so `bin/wt-completion-test` can source and test them), but `compdef _wt wt` runs only when `compdef` is available (i.e., after `compinit`).

**Tests:** `bin/wt-completion-test` is a zsh script that creates real `.wt-meta` files in `/tmp` and tests the helpers directly. It does not test `compadd` wiring — that requires live completion state and is verified manually.

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
| `tmux` | Detect if running inside tmux (via `$TMUX`) to show window-close hint | Optional — guarded by `[[ -n "${TMUX:-}" ]]` |
| `find` | `wt doctor` — inner checks only (branch/worktree loops) | POSIX `find` — no GNU extensions used |
| `date` | `human_age()` — timestamp to seconds | GNU `date -d` or BSD `date -j -f` |
| `sed`, `tr`, `cut` | `slugify()`, `read_meta()` | POSIX |

A Go/Rust port eliminates all of these as external processes except `git`.

---

## Command implementations

### `wt new "<description>"`

```
1. Parse args: 0 args → error; 1 arg → description (use git rev-parse --show-toplevel); 2+ args → error
2. Resolve project root: git rev-parse --show-toplevel
3. Resolve main worktree: if inside a worktree (.git is a file), call get_main_worktree() to get the
   actual root; print info "Detected worktree context — branching from main checkout (<branch>): <path>"
   NOTE: the new worktree's base is always the main checkout's HEAD, not the current worktree's branch
4. _register_project(project_root)
5. Slugify description → branch = "wt/<slug>", worktree_path = "<project_root>/.worktrees/<slug>"
6. Conflict checks: worktree dir exists? → error; branch exists? → error
7. Capture base_branch = $(git symbolic-ref --short HEAD)
8. mkdir -p <project_root>/.worktrees
9. Add ".worktrees/" to <project_root>/.git/info/exclude (if not present)
10. git worktree add <worktree_path> -b <branch>
11. Write .wt-meta
12. Add ".wt-meta" to GIT_COMMON_DIR/info/exclude (if not present)
13. Print generic dependency hint
14. Print worktree_path to stdout (shell wrapper uses this to cd)
```

### `wt open [<branch>] ["description"]`

Three modes:

```
Mode 1: no args → list branches + exit 1
  1. Resolve project root (git rev-parse --show-toplevel; follow worktree pointer if needed)
  2. Print local branches (excluding wt/* branches) to stderr
  3. Print remote branches (excluding HEAD pointers and wt/* branches) to stderr
  4. Print usage hint to stderr
  5. Exit 1

Mode 2: wt open <branch> → slug from branch name
Mode 3: wt open <branch> "description" → slug from description

  1. Parse args: positional only — first = branch, second = description (optional), flags → error
  2. Resolve project root (same as wt new: follow worktree pointer if inside a worktree)
  3. Validate branch exists locally: git rev-parse --verify <branch>
  4. Slugify: if description given, slugify(description); else slugify(branch with / → space)
     Same slugify() as wt new — allows multiple worktrees from the same branch via different descriptions
  5. worktree_path = <project_root>/.worktrees/<slug>
  6. Conflict checks: worktree dir exists? → error; wt/<slug> branch exists? → error
  7. _register_project(project_root)
  8. mkdir -p <project_root>/.worktrees
  9. Add ".worktrees/" to info/exclude (if not present)
  10. git worktree add <worktree_path> -b wt/<slug> <branch>
  11. Write .wt-meta (base_branch = target branch, description = description or branch name)
  12. Add ".wt-meta" to GIT_COMMON_DIR/info/exclude (if not present)
  13. Print worktree_path to stdout (shell wrapper cd)
```

### `wt finish [--yes|-y] [--force]`

Always rebases onto base branch. Merge commits from `wt sync` are dropped by the rebase (individual work commits are preserved).

```
1. git rev-parse --show-toplevel → repo_root
2. Verify: repo_root/.git is a FILE (not a dir) → you're in a worktree; dir → error "main checkout"
3. Read .wt-meta: base_branch, branch, description, project, project_root, slug
4. Validate: no uncommitted tracked changes (git status --porcelain | grep -v '^??')
5. If untracked files exist → warn + confirm "Untracked files will be lost" (only --force bypasses)
6. get_main_worktree()
7. _rebase_onto_base(base_branch, branch, --prefer-local) — SIGINT-trapped internally
   → on conflict: git rebase --abort; print "Run wt sync"; exit 1
8. _ff_onto_base(HEAD, base_branch, repo_root, branch)
9. _cleanup_worktree(repo_root, branch, main_wt, project, slug, force=true, project_root)
10. Print main_wt to stdout (shell wrapper uses this to cd back)
```

### `wt sync`

```
1. git rev-parse --show-toplevel → repo_root
2. Verify: repo_root/.git is a FILE → in a worktree; dir → error "main checkout"
3. Read .wt-meta: base_branch, branch, description
4. Validate: base_branch and branch non-empty
5. Check: no in-progress merge (MERGE_HEAD file) → error with instructions
6. Check: no in-progress rebase (rebase-merge/ or rebase-apply/ dirs) → error with instructions
7. Check: no uncommitted tracked changes (git status --porcelain | grep -v '^??')
8. git rev-parse --verify <base_branch> → error if not found locally
9. git merge-base --is-ancestor <base_branch> HEAD → if true, "Already up to date", return 0
10. git rebase <base_branch> (SIGINT-trapped)
    → on success: print success message; return 0
    → on conflict: show LLM-friendly output (conflicted files with line numbers,
                   REBASE_HEAD commit info), print git rebase --continue instructions, exit 1
```

Key difference from `wt finish`: no confirmation, no fast-forward, no cleanup, no cd.
**Rebase-based** — linear history, no merge commit. Conflicts resolved here won't recur in `wt finish`.
**Local base only** — no `git fetch`; user controls what's on the local base branch.
**Untracked files allowed** — only tracked uncommitted changes block.
**Safe for Claude Code** to invoke autonomously.

### `wt retarget [branch]`

```
1. Verify: repo_root/.git is a FILE → in a worktree; dir → error
2. Read .wt-meta: base_branch, branch, description
3. Validate: base_branch and branch non-empty
4. If arg given:
   - git rev-parse --verify "$arg" OR git rev-parse --verify "origin/$arg"
   - Neither found → error "Branch not found: X"
5. If no arg:
   - Print "Current base: <base_branch>"
   - Call _pick_base_branch(<branch_without_prefix>, base_branch) — falls back to local branches
   - No branches found → error; invalid choice / EOF → warn "Invalid choice. Aborted." + exit 0
6. If new_base == base_branch → info "Already targeting X"; return 0
7. sed -i.bak "s/^base_branch=.*/base_branch=${new_base}/" meta_file
8. success "Base branch changed: old → new"
9. No stdout output (no cd needed)
```

### `_ff_onto_base ff_ref base_branch repo_root branch` (shared helper)

```
1. Resolve ff_ref to absolute SHA (portable across worktrees)
2. Strategy 1: git fetch . "<sha>:refs/heads/<base_branch>"
   → success "Fast-forward successful"
3. Strategy 2 (Strategy 1 failed): scan git worktree list --porcelain
   → skip repo_root (current worktree)
   → find first worktree with base_branch checked out
   → git -C <ff_wt> merge --ff-only <sha>
   → success "Fast-forward successful (from worktree: <name>)"
4. If no worktree found or merge fails: print manual instructions, exit 1
```

Used by `cmd_finish`: `_ff_onto_base HEAD "$base_branch" "$repo_root" "$branch"`

### `_rebase_onto_base base_branch branch [--prefer-local]` (shared helper)

```
1. git fetch origin <base_branch> >&2 (warn on failure, continue)
2. Resolve rebase_target:
   Without --prefer-local (default, used by wt pr):
   - origin/<base_branch> if ref exists; else local <base_branch>
   With --prefer-local (used by wt finish, wt sync):
   - origin ahead or equal → origin/<base_branch>
   - local strictly ahead  → <base_branch> (local)
   - diverged              → origin/<base_branch> + warn
   - no origin ref         → <base_branch> (local)
3. git rebase <rebase_target> >&2
4. Returns git rebase exit code — conflict handling left to caller
```

Used by `cmd_finish` and `cmd_pr` (clean branches only). Each caller handles conflict differently:
- `cmd_finish`: `git rebase --abort`, print "Run 'wt sync'", exit 1 (sync rebases first, so finish's rebase is then trivial)
- `cmd_pr`: leave in conflict state, print continue/abort instructions, exit 1

`cmd_sync` does NOT use this helper — it calls `git rebase` directly (no fetch, local-only).

`cmd_pr` does NOT use `--prefer-local`: the PR targets the remote branch, so
rebasing onto local-only commits would include unpushed base work in the PR diff.

`cmd_pr` always calls `_rebase_onto_base` — since `wt sync` now rebases (no merge commits),
there is no need to detect and skip.

### `wt abandon [--yes|-y] [--force]`

```
1-3. Same as finish (verify worktree, read meta, validate slug/branch)
4. [if dirty] warn + confirm "drop anyway?"  ← skipped by --yes
5. Non-skippable: count commits ahead of base_branch; if > 0 → warn + list commits + confirm
   ← --yes does NOT skip; only --force bypasses
6. Confirm: "Drop <branch>? (no merge)"  ← skipped by --yes
7. get_main_worktree()
8. _cleanup_worktree(repo_root, branch, main_wt, project, slug, force=true, project_root)
9. Print main_wt to stdout
```

### `_cleanup_worktree` (shared)

```
Args: repo_root branch main_wt project slug delete_mode [project_root]
delete_mode: "force" → git branch -D (always used — see note below)
             "merged" → git branch -d (safe-delete, only succeeds if merged into HEAD)

1. git -C <main_wt> worktree remove <repo_root> --force
2. git -C <main_wt> branch -D <branch>  (always "force" mode — git branch -d fails when main_wt
   has a different branch checked out than the base, even after a successful fast-forward)
3. Auto-unregister (if project_root provided):
   - Check if <project_root>/.worktrees/ is empty or absent
   - Check if no wt/* branches remain: git branch --list 'wt/*' | wc -l == 0
   - If both: _unregister_project(project_root)
4. [if TMUX] Print bold "You can now close this tmux window" hint to stderr
```

### `wt list`

```
1. For each project_root in REGISTERED_PROJECTS:
   - skip if <project_root>/.worktrees/ doesn't exist (stale entry)
   - glob <project_root>/.worktrees/*/.wt-meta | sort
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

### `wt doctor [--dry-run]`

```
For each project_root in REGISTERED_PROJECTS:
  Stale registry check:
    If project_root doesn't exist on disk → report + offer _unregister_project → continue
  Skip if: not a git repo (.git dir missing)

    Check 1 — Orphaned wt/* branches:
      git branch --list 'wt/*' → for each branch, check if .worktrees/<slug>/ exists
      → offer to git branch -D

    Check 2 — Orphaned worktree dirs:
      for each .worktrees/*/: check if it's in `git worktree list --porcelain`
      → offer to rm -rf

    Check 2b — Missing .wt-meta:
      git worktree list --porcelain → for each non-main worktree, check if .wt-meta exists
      → offer to _repair_wt_meta (infers fields from git state)

    Check 3 — Corrupt .wt-meta:
      for each .worktrees/*/.wt-meta: verify base_branch, branch, slug non-empty
      → offer to _repair_wt_meta

    Check 4 — Missing .worktrees/ in info/exclude
      → offer to append

    Check 5 — Missing .wt-meta in info/exclude
      → offer to append

    Check 6 — Stale git worktree registrations:
      git worktree list --porcelain → paths not in main worktree that don't exist on disk
      → offer to git worktree prune + branch -D for each stale slug

    Print result per project (only projects with issues unless it's the first)

--dry-run: all checks run, all confirm() calls replaced with "[dry-run] Would fix:" messages, no mutations.
```

**`_repair_wt_meta` helper:** Infers `.wt-meta` fields from git state when the file is missing or corrupt. Uses `git rev-parse --abbrev-ref HEAD` for `branch`, directory name for `slug`, basename for `project`, branch reflog for `created`, and heuristic (fewest commits ahead of HEAD) for `base_branch`. Existing non-empty field values are preserved.

**fd trick:** Inner branch/worktree loops use `fd 5` to keep `fd 0` (stdin) free for `confirm()`. The outer project loop iterates the registry array (`for project_root in "${REGISTERED_PROJECTS[@]+"${REGISTERED_PROJECTS[@]}"}"`— the `+` guard prevents bash 3.2 `set -u` unbound-variable errors on empty arrays) and doesn't need a separate fd. Go/Rust doesn't need this — use an iterator + synchronous stdin read.

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
git worktree list --porcelain | awk '/^worktree /{ if (!f) { sub(/^worktree /, ""); f=$0 } } END { print f }'
```

The first entry in `git worktree list --porcelain` is always the main worktree. Works even when called from inside a linked worktree. Uses `sub()` + `$0` to handle paths with spaces (the old `$2` split on whitespace).

### `_load_registry()` / `_register_project()` / `_unregister_project()`

The registry is a plain text file (`~/.config/wt/projects`, one path per line). `_load_registry()` reads it into `REGISTERED_PROJECTS` at startup. `_register_project(path)` appends a path if not present (idempotent, using `grep -qxF`). `_unregister_project(path)` removes it (grep -v + temp file swap); deletes the registry file if it becomes empty.

---

## Safety invariants

1. **Never merge with uncommitted changes** — always check `git status --porcelain` before rebase/ff
2. **Always fast-forward (never --no-ff)** — preserves linear history
3. **Rebase before fast-forward** — handles base drift; if rebase fails, abort and print manual instructions
4. **Never eval `.wt-meta` values** — parse with string split, never shell-eval
5. **`info/exclude` over `.gitignore`** — keep `.worktrees/` and `.wt-meta` out of committed gitignore
6. **stdout is reserved for path output** — all UI to stderr; the shell wrapper depends on this contract
7. **tmux operations are always optional** — guard every tmux call with an "are we in tmux?" check
8. **`--yes` skips routine confirms; `--force` overrides safety gates** — untracked files in finish, unpushed commits in abandon are non-skippable by `--yes`; they require explicit `--force`
9. **SIGINT-trapped rebase paths** — `cmd_finish` and `cmd_pr` set a trap before `git rebase` that aborts the rebase and exits 130 on Ctrl+C; trap is cleared after rebase completes

---

## Known edge cases

| # | Edge case | Handling |
|---|---|---|
| 1 | `wt new` from inside a worktree | Detect `.git` file vs dir; redirect to main checkout via `get_main_worktree()`; register main checkout path |
| 2 | Base branch checked out in any worktree during ff | Can't `git fetch . HEAD:<base>` (ref locked); scan all worktrees via `git worktree list --porcelain` to find whichever has base checked out; run `merge --ff-only` there |
| 3 | `wt finish`/`abandon` inside tmux | Print a reminder to close the current window; session is never killed automatically |
| 4 | `wt new` with apostrophes in description | Slugify strips them; `.wt-meta` preserves them verbatim (no shell quoting) |
| 5 | `wt list` with dirty worktrees | Color the dirty count yellow; `.wt-meta` excluded via `info/exclude` so it doesn't count |
| 6 | `wt doctor` on repos that never used `wt` | Skip repos without a `.worktrees/` dir |
| 7 | `read_meta` on missing key | Returns empty string via `|| true` — never exits non-zero |
| 8 | `wt list` performance | Registry-based glob — no recursive find; O(registered projects × worktrees) |
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

Current strategy: try (1) first. On failure, scan ALL worktrees (not just main) using `git worktree list --porcelain` to find whichever one has base checked out; run `merge --ff-only` there. This handles the three-worktree scenario where base is checked out in a non-main worktree.

**Rebase target / ff target consistency:** `finish` and `sync` pass `--prefer-local` to `_rebase_onto_base`. Without it, the helper always prefers `origin/base` — correct for `wt pr` (PR targets remote state), but wrong for `finish`/`sync`: if local base is ahead of origin (e.g. previous finishes not pushed), rebasing onto stale origin produces a feature tip that local base is NOT an ancestor of, so the fast-forward fails. With `--prefer-local`, the helper uses whichever ref is further ahead.

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
4. **`wt finish` cd-back** — zsh wrapper handles `finish` the same as `new`; `cmd_finish` prints main worktree path on stdout for the wrapper to cd into
5. **Lockfile detection fixed** — Checks `${worktree_path}/pnpm-lock.yaml` instead of project root (worktrees have their own file copies)
6. **Nested worktree detection** — `wt new` from inside a worktree now resolves to the real main checkout instead of creating a nested worktree
7. **ff failure reason shown** — Removed `2>/dev/null` from fast-forward attempt; actual git error shown as warning before fallback
8. **Auto-gitignore** — `wt new` appends `.worktrees/` to `.gitignore` if missing
9. **tmux hint instead of session kill** — `wt finish` and `wt abandon` print a bold "close this tmux window" reminder when inside tmux; no session is killed automatically
10. **Flexible find depth** — `wt list` no longer hardcodes `-mindepth 4 -maxdepth 4`; uses path pattern matching instead

### v3 fixes (second review pass)

11. **`.wt-meta` quoting incompatibility** — v2 used shell-style `'\''` escaping for single quotes but `read_meta()` used dumb sed stripping, not shell parsing. Fixed by removing all quoting — plain `key=value`, values read with `cut -d= -f2-`
12. **`.wt-meta` inflated dirty count** — Every worktree showed "1 dirty" because `.wt-meta` was untracked. Fixed by appending `.wt-meta` to `.git/info/exclude` (worktree-local gitignore, doesn't affect repo)
13. **Color detection on wrong fd** — Colors were set based on stderr being a terminal (`-t 2`), but `wt list` writes to stdout. Piping `wt list | ...` leaked escape codes. Fixed by checking stdout (`-t 1`)
14. **`find_project` didn't verify git repo** — Would silently accept any directory; git errors were confusing. Fixed by checking for `.git` dir or file before returning
15. **Added `wt abandon`** — New command to abandon a worktree without merging. Uses `git branch -D` (force). Same safety checks as `wt finish` (dirty warning, Claude check, confirm)
16. **Better ff failure message** — When fast-forward fails because target is checked out elsewhere, now shows which worktree has it checked out instead of a raw git error

### v4 fixes (TDD coverage pass — 2026-03-11)

Expanded `wt-test` from 38 → 53 tests covering previously untested paths. Two tool bugs surfaced:

17. **FF branch not deleted when main_wt is on a different branch** — `_cleanup_worktree` used `git branch -d` (safe-delete), which checks if the branch is merged into the *currently checked out* branch in `$main_wt`. After a fast-forward merge where `$main_wt` was temporarily on `main` (not `dev`), `-d` failed silently. Fixed by always using `-D` (force-delete) in `cmd_finish` — the branch is guaranteed merged at that point.
18. **`git merge --no-ff` and `git branch -d/-D` output leaked to stdout** — These git commands printed summaries to stdout, polluting the path returned to the zsh `cd` wrapper. Fixed by appending `>&2` to both in `_cleanup_worktree` and the `--no-ff` merge call.

### v5 fixes (first real-world walkthrough — 2026-03-12)

Two bugs found during manual walkthrough:

19. **`wt abandon` didn't cd back after removing worktree** — Zsh wrapper only intercepted `new` and `finish` for the `cd` behavior. `cmd_abandon` already printed `$main_wt` on stdout (same as `cmd_finish`), but the wrapper silently discarded it. Fixed by adding `"abandon"` to the condition in the zsh wrapper.
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

**1. `wt finish`**
`finish` has `git flow finish` precedent and best describes the lifecycle action.

**2. Merge strategy → rebase + fast-forward**
Old: ff-first, `--no-ff` fallback. Created merge commits when base had moved.
New: `git rebase <base>` → `git fetch . HEAD:<base>` (ff). Always linear history.

If `base_branch` is checked out in the main worktree, falls back to `git -C $main_wt merge --ff-only $branch` (safe since rebase guarantees linearity).

### v8: Public repo + portability cleanup (2026-03-12)

Extracted `wt` into a standalone public GitHub repo. Goal: anyone can clone and run in 2 minutes.

23. **Configurable search paths** — Replaced hardcoded paths with a three-tier config system: `WT_SEARCH_PATHS` env var → `~/.config/wt/config` → defaults. Implemented as `_load_search_paths()` called at startup. (Superseded in v10.)
24. **Cross-platform date parsing** — `human_age()` now tries GNU `date -d` first (Linux), falls back to BSD `date -j -f` (macOS).
25. **`claude_running_in_session()` stubbed to `false`** — Removed personal tmux option check. Function always returned false. Documented as an override hook at the time; removed entirely in v16.
26. **Removed personal doc references** — Lines referencing local dev files removed from header and help output. README replaces the usage guide.
27. **Python package manager detection improved** — Added `uv.lock` → `uv` and `poetry.lock` → `poetry` detection before the `pip` fallback. Order: `uv.lock → poetry.lock → requirements.txt → pyproject.toml`.
28. **Shell wrapper documented for both zsh and bash** — Header now shows both `.zshrc` and `.bashrc` forms.
29. **`wt-test` switched to `WT_SEARCH_PATHS`** — Test suite now uses `WT_SEARCH_PATHS="$test_base" bash "$WT"` instead of `HOME="$FAKE_HOME" bash "$WT"`. (Superseded in v10.)
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

### v9: `--yes`/`-y` flag for `wt finish` and `wt abandon` (2026-03-12)

**Problem:** `confirm()` calls `read -r response` from stdin. Claude Code's Bash tool has no interactive stdin — `read` gets EOF, confirmation always fails, `wt finish`/`wt abandon` always abort.

**Fix:** Add `--yes`/`-y` flag to both commands. When set, all `confirm()` calls are bypassed. The dirty-file check in `cmd_finish` is `error()` not `confirm()`, so it is intentionally **not** skipped — never auto-merge dirty work. The dirty-file check in `cmd_abandon` **is** skipped — deliberately abandoning dirty work is the point of `--yes` on abandon.

33. **`wt finish --yes` / `wt abandon --yes`** — Non-interactive flag skips confirmation prompts. Local `auto_yes=0` variable parsed at top of each function; `confirm()` calls wrapped in `if (( auto_yes == 0 ))`. Tests expanded from 79 → 95.

### v10: Registry-based worktree discovery (2026-03-15)

Replaced `PROJECT_SEARCH_PATHS` / `WT_SEARCH_PATHS` / `~/.config/wt/config` with a project registry. Removes the need for any manual configuration.

34. **Registry replaces search paths** — `wt new` registers each project root in `~/.config/wt/projects`. `wt list` and `wt doctor` iterate the registry. No `find` traversal, no hardcoded paths, no config files.
35. **Auto-unregister** — `_cleanup_worktree` checks if `.worktrees/` is empty and no `wt/*` branches remain after cleanup; if so, calls `_unregister_project`. Projects are removed automatically when fully cleaned up.
36. **Stale entry detection** — `wt list` silently skips registry entries whose directories don't exist. `wt doctor` reports stale entries and offers to remove them.
37. **Two-arg `wt new` removed** — `wt new <project> "<desc>"` form deleted. Users must `cd` into the repo. Project names were ambiguous (basename collisions, no canonical location).
38. **`wt pr` dirty check moved earlier** — Dirty check now fires before the interactive base-branch prompt, consistent with `wt finish`/`wt abandon`.
39. **Tests switched to `WT_REGISTRY`** — All test invocations now use `WT_REGISTRY="$registry_file"` pointing at a temp file. Tests expanded from 95 → 156.
40. **Bash 3.2 empty-array fix** — `"${arr[@]}"` with `set -u` throws "unbound variable" on bash <4.4 (macOS system bash 3.2) when the array is empty. Fixed with `"${arr[@]+"${arr[@]}"}"` guard in `cmd_list` and `cmd_doctor`. Tests: 156 → 158.

### v11: Robustness audit fixes (2026-03-16)

Systematic audit of the codebase at commit `38a5e84`. All fixes TDD: failing test first, then fix.

41. **`get_main_worktree()` broken on paths with spaces** (C1) — `awk`'s `$2` splits on whitespace, truncating paths containing spaces. Fixed by using `sub(/^worktree /, "")` + `$0` instead of `$2`. Affects all commands that call `get_main_worktree()` (`finish`, `drop`, `new` from worktree, `_cleanup_worktree`).

42. **`sed` delimiter bug in `retarget` and `pr`** (C2) — `sed "s/^base_branch=.*/base_branch=${new_base}/"` used `/` as delimiter. Branch names like `release/v2` corrupted `.wt-meta` silently (sed command broke mid-pattern). Fixed by switching to `|` delimiter: `sed "s|^base_branch=.*|base_branch=${new_base}|"`.

43. **`_cleanup_worktree --force` silently destroyed untracked files** (C3) — `git status --porcelain` in `cmd_finish` treated untracked files the same as tracked changes (generic "Uncommitted changes" error). Split the check: tracked changes → hard error; untracked files → warn "will be permanently deleted" + confirm (auto-accepted by `--yes`). The `--force` flag on `worktree remove` is still used since the user has now consented.

44. **`wt finish --force` flag added** (S2) — PR-open check had no override. Users wanting to abandon a PR and finish locally had to close the PR on GitHub first. Added `--force` flag to `cmd_finish` that skips the open-PR guard and proceeds to local rebase+ff flow.

45. **Fast-forward failed with third worktree on base** (S3) — Strategy 2 FF fallback only checked the main worktree for the base branch. If a non-main worktree had base checked out, both strategies failed. Fixed by scanning ALL worktrees via `git worktree list --porcelain` and running `merge --ff-only` from whichever one has base checked out.

46. **`slugify` didn't strip leading hyphens** (M1) — Descriptions starting with non-alphanumeric characters (e.g. leading spaces) produced slugs with leading hyphens (`-verbose-mode`). Added `| sed 's/^-*//'` as final step in slugify pipeline.

47. **`cmd_doctor` check 2 used regex grep for path matching** (M2) — `grep -q "^worktree ${wt_dir%/}$"` treated the worktree path as a BRE pattern. Paths with bracket characters (`[`, `]`) created character classes that didn't match the literal path, causing false "Orphaned worktree dir" reports. Fixed by switching to `grep -qF` (fixed-string matching).

### v12: Remaining audit items (2026-03-16)

Continuation of the v11 robustness audit. All fixes TDD: failing test first, then fix.

48. **`wt new` from worktree didn't show base branch** (S1) — The "Detected worktree context" info message only showed the main checkout path, not which branch it was on. Users running `wt new` from inside a `dev`-based worktree couldn't easily see that the new worktree would target `main` (main checkout's HEAD), not `dev`. Fixed: info message now reads "Detected worktree context — branching from main checkout (<branch>): <path>".

49. **`wt retarget` interactive picker crashed on EOF** (S4) — `read -r choice` in the interactive picker returned non-zero on EOF (stdin closed). With `set -e`, this caused the script to exit with code 1 instead of showing "Aborted." and exiting cleanly. Affects non-interactive contexts (scripts, CI, stdin redirected to /dev/null). Fixed by appending `|| true` to the `read` call.

50. **Picker logic duplicated between `retarget` and `pr`** (M4) — `cmd_retarget` and `cmd_pr` each contained an independent copy of the remote-branch picker (list, number, read, validate). Extracted into `_pick_base_branch <exclude_branch> <current_base> [--no-fallback]` helper. Prints selection to stdout; returns 1 when no branches exist. Both commands now call the helper. Also fixed the same EOF `read` bug in `cmd_pr`'s picker as part of this refactor.

### v13: Fix `wt finish` ff failure when local base is ahead of origin (2026-03-19)

51. **`wt finish` failed when local base was ahead of origin** (S4) — When two worktrees were created from the same dev base (X), the first finish advanced local dev to X→A (not pushed, origin stayed at X). The second finish rebased its branch onto origin/dev (X, a no-op) — but then tried to fast-forward local dev (X→A) to the feature tip (X→B). Since X→A is not an ancestor of X→B, `merge --ff-only` failed. Fixed by inlining the rebase target selection in `cmd_finish`: if local base is strictly ahead of origin, rebase onto local base instead of origin. Also fixed the Strategy 2 error message to show the `merge --ff-only` error rather than the unrelated Strategy 1 (`git fetch .`) error.

52. **`wt sync` also rebased onto stale origin** (S5) — Same root cause as S4: `_rebase_onto_base` always preferred origin, so `wt sync` wouldn't include local-only commits from previous finishes. Extracted the smart target selection into `_rebase_onto_base` behind a `--prefer-local` flag. `cmd_finish` and `cmd_sync` now pass `--prefer-local`; `cmd_pr` does not (PR must target remote state).

### v14: Safety safeguards + wt update command (2026-03-19)

Two parallel feature branches merged:

53. **`wt update` command added** — merges the local base branch into the worktree branch instead of rebasing. Designed for Claude Code: when conflicts occur, the LLM reads conflict markers, edits files to resolve them, and runs `git add` + `git merge --continue`. Differences from `wt sync`: merge not rebase (all conflicts in one round), uses local base ref only (no `git fetch`), untracked files do not block the command. `--no-edit` flag prevents git from opening an editor for the merge commit message. Safe for Claude Code to invoke autonomously.

54. **`wt finish` and `wt sync` conflict messages updated** — both commands now mention `wt update` as an alternative when a rebase conflict is detected.

55. **Non-skippable untracked files gate in `wt finish`** — Previously, `--yes` auto-accepted the untracked files warning in `cmd_finish`. Untracked files are permanently deleted when the worktree is removed. This safety gate now always prompts, even with `--yes`; only `--force` bypasses it.

56. **`wt abandon --force` + unpushed commits gate** — `cmd_abandon` now reads `base_branch` from `.wt-meta` and counts commits ahead. If any unpushed commits exist, the gate always prompts (non-skippable by `--yes`). `--force` flag added to `cmd_abandon` to override.

57. **`_cleanup_worktree` delete_mode param** — Renamed `force` parameter to `delete_mode` (`"merged"` | `"force"`) for clarity. In practice, all callers use `"force"` (`git branch -D`) because `git branch -d` fails when the main worktree has a different branch checked out than the base (even after a successful fast-forward).

58. **SIGINT trap on rebase paths** — `_rebase_onto_base`, `cmd_sync`, and `cmd_pr` set a SIGINT trap before `git rebase` that runs `git rebase --abort` and exits 130 on Ctrl+C. Prevents abandoned in-progress rebases.

59. **`--dry-run` for `finish`, `abandon`, `doctor`** — New flag previews what would happen without making any changes. `finish --dry-run` shows rebase target, ff, and cleanup plan. `abandon --dry-run` shows commit count and worktree path. `doctor --dry-run` reports all issues without fixing any.

60. **`wt doctor` `.wt-meta` repair** — New `_repair_wt_meta` helper infers `.wt-meta` fields from git state. `wt doctor` now detects missing `.wt-meta` (check 2b) and corrupt `.wt-meta` (check 3) and offers to repair both. Previously, corrupt meta was reported but not fixable.

61. **Bash version check** — `bin/wt` now exits with a clear error on bash < 4.0 (macOS ships with 3.2). Escape hatch: `WT_SKIP_VERSION_CHECK=1`. Same check in `install.sh` (warning only). Test suite exports `WT_SKIP_VERSION_CHECK=1` so it runs under any bash.

62. **Cross-platform hardening** — `bin/wt-test` now exports `LC_ALL=C` for consistent sort/comparison. `.gitattributes` added for LF line-ending enforcement. CI now runs ShellCheck on `bin/wt` and `bin/wt-test` before the test step. CI stdin fixed: `bash bin/wt-test < /dev/null`.

### v15: Adaptive finish/pr — squash path after wt update (2026-03-19)

`wt finish` and `wt pr` are now adaptive:

**Problem:** `wt update` (merge-based, LLM-friendly) followed by `wt finish` (rebase-based) dropped the merge commit and re-encountered the same conflicts.

**Fix:** detect merge commits and switch strategy.

63. **`wt finish` squash path** — When `git rev-list --merges <base>..HEAD` is non-empty (merge commits from `wt sync`), `wt finish` uses `git commit-tree HEAD^{tree} -p <base> -m <description>` to create a single squash commit instead of rebasing. The squash commit has the full merged tree and the base as its only parent — a guaranteed fast-forward. Pre-flight check: `git merge-base --is-ancestor <base> HEAD` must pass; if not, the user is prompted to run `wt update` first.

64. **`wt pr` skips rebase when merge commits present** — `cmd_pr` checks `git rev-list --merges <base>..HEAD` before calling `_rebase_onto_base`. If merge commits are present, the rebase is skipped. `--force-with-lease` push works correctly in both cases.

### v16: Remove squash path from wt finish (2026-03-30)

`wt finish` now always rebases, even when merge commits from `wt sync` are present. `git rebase` drops merge commits and replays only work commits — preserving individual commit messages on the base branch. The squash path (which collapsed all work into a single commit with the `.wt-meta` description) is removed.

65. **Squash path removed from `wt finish`** — Strategy detection (`git rev-list --merges`), squash commit creation (`git commit-tree`), and the squash pre-flight ancestor check are all removed. The rebase path now handles all cases.

### v17: `wt sync` changed from merge to rebase (2026-03-30)

`wt sync` now uses `git rebase <base_branch>` instead of `git merge`. Eliminates the double-conflict problem where conflicts resolved during sync recurred during finish (finish's rebase dropped the merge commit and replayed original commits). Now both sync and finish use rebase — conflicts resolved once during sync don't recur.

66. **`wt sync` rebase-based** — `cmd_sync` calls `git rebase` directly (no fetch, local-only). SIGINT-trapped. Conflict output adapted: uses `REBASE_HEAD` instead of `MERGE_HEAD`, shows "Applying:" commit info and "Onto:" base info. Auto-merged files section removed (rebase applies one commit at a time).

67. **`wt pr` always rebases** — Merge-commit detection (`pr_has_merges`) removed from `cmd_pr`. Always calls `_rebase_onto_base` since `wt sync` no longer creates merge commits.

68. **`wt finish` error message restored** — Conflict error now says "Run 'wt sync'" again (no longer a loop since sync rebases).

---

### v18: Replace tmux session-kill with close-window hint (2026-03-19)

**Problem:** `_cleanup_worktree` killed the tmux session named `<project>/<slug>` on finish/abandon. This didn't match real usage — users keep multiple tmux windows in one session and don't want the session destroyed. The code was also effectively dead: `claude_running_in_session()` always returned `false`, the session name format didn't match actual session names, and `tmux_session_exists()` was never true in practice.

**Fix:** Removed `tmux_session_exists()`, `claude_running_in_session()`, the editor-still-running warning blocks in `cmd_finish` and `cmd_abandon`, and the session-kill block in `_cleanup_worktree`. Replaced with a single bold hint at the end of `_cleanup_worktree`: `"You can now close this tmux window."` — only shown when `$TMUX` is set. The user stays in control of their tmux layout.

55. **Dead tmux session-kill code removed** — `tmux_session_exists()`, `claude_running_in_session()`, editor-running checks, and the `tmux kill-session` call in `_cleanup_worktree` were all removed.

56. **Tmux close-window hint added** — `_cleanup_worktree` now prints a bold reminder to close the current tmux window when `$TMUX` is set. Fires once, after git cleanup, before the caller's success message.

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
| wt new — basic creation | dir created, meta written, stdout=path |
| wt new — .wt-meta contents | all 7 fields written correctly |
| wt new — single quotes | slugify strips apostrophes; description preserved verbatim |
| git status — .wt-meta excluded | info/exclude written correctly for both patterns |
| wt list — output | branch/clean/description columns present |
| wt list — age display | human_age() returns valid format |
| wt list — no ANSI when piped | tty check works |
| wt new — conflicts | duplicate worktree/branch → error |
| wt new — from inside worktree | redirects to main checkout |
| wt new — two-arg form errors | removed feature errors cleanly |
| wt finish — dirty check | blocks on uncommitted changes |
| wt finish — from main checkout | error message |
| wt abandon — dirty double-confirm | two prompts for dirty worktree |
| wt abandon — clean | single confirm, stdout=main_wt |
| wt finish — rebase + ff | rebase + fast-forward happy path |
| wt finish — diverged base | rebase handles base drift, linear history |
| wt finish --yes | skips confirmation, no stdin pipe |
| wt abandon --yes | clean worktree, no stdin pipe |
| wt abandon --yes (dirty) | skips dirty + main confirms |
| wt abandon -y | short flag works |
| wt list — empty | "No active worktrees" message |
| wt doctor — clean | "all good" |
| wt doctor — orphaned branch | detect + fix |
| wt doctor — orphaned dir | detect + fix |
| wt doctor — corrupt meta | detect only |
| wt doctor — missing excludes | detect + fix |
| wt doctor — stale registration | detect + fix |
| wt list — stale registry entry | silently skipped |
| wt doctor — stale registry entry | detect + offer to remove |
| registry — project registered after new | registry file written |
| registry — unregister after drop | auto-unregister on last drop |
| registry — unregister after finish | auto-unregister on last finish |
| registry — not unregistered if branches remain | orphan branch prevents removal |
| registry — auto-unregister both conditions | fires when empty + no branches |
| wt list — missing registry file (fresh install) | no crash, "No active worktrees" |

---

## Future ideas

- **`wt log`**: history of finished/dropped worktrees (currently no persistent log)
- **Per-project config** (`~/.config/wt/config`): default merge target, branch prefix, auto-tmux flag
- **Shell completions**: `wt new <TAB>` lists projects from search paths
- **Upgrade to Approach 3** (zsh plugin): if per-project config, completions, and prompt integration become needed
- **Conflict resolution flow**: offer to open `$EDITOR` with conflict markers or launch Claude in the worktree with conflict context
