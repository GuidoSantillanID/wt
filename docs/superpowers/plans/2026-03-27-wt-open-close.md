# wt open / wt close Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `wt open <branch>` and `wt close` commands to check out existing branches into worktrees without the managed branch lifecycle.

**Architecture:** New `type` field in `.wt-meta` distinguishes open worktrees (`type=open`) from managed ones (no `type` field, implicit default). `wt open` creates a worktree for an existing branch. `wt close` removes it without touching the branch. Existing commands (`finish`, `abandon`, `sync`, `retarget`) get a guard clause rejecting open worktrees.

**Tech Stack:** Bash 4+, git worktrees, existing `wt` test framework (`bin/wt-test`)

---

### Task 1: Tests for `wt open` — happy path

**Files:**
- Modify: `bin/wt-test` (append before the Summary section at line 1929)

- [ ] **Step 1: Write tests for `wt open` happy path**

Append before the `# ─── Summary` line in `bin/wt-test`:

```bash
# ── wt open / wt close ──────────────────────────────────────────────────────

section "wt open — checks out existing branch into worktree"
cd "$REPO"
git -C "$REPO" checkout -q main
# Create a feature branch to open
git -C "$REPO" checkout -q -b feature/open-test
echo "feature work" > "$REPO/feature.txt"
git -C "$REPO" add feature.txt
git -C "$REPO" commit -q -m "feature commit"
git -C "$REPO" checkout -q main
OPEN_WT="${REPO}/.worktrees/feature-open-test"
open_stdout=$(wt open "feature/open-test" 2>/dev/null)
assert_eq "stdout is worktree path" "$OPEN_WT" "$open_stdout"
assert_dir_exists "worktree directory created" "$OPEN_WT"
assert_file_exists ".wt-meta exists" "${OPEN_WT}/.wt-meta"

section "wt open — .wt-meta has type=open"
open_type=$(grep "^type=" "${OPEN_WT}/.wt-meta" | head -1 | cut -d= -f2-)
assert_eq "type is open" "open" "$open_type"

section "wt open — .wt-meta has correct branch"
open_branch=$(grep "^branch=" "${OPEN_WT}/.wt-meta" | head -1 | cut -d= -f2-)
assert_eq "branch is feature/open-test" "feature/open-test" "$open_branch"

section "wt open — .wt-meta has no base_branch"
open_base=$(grep "^base_branch=" "${OPEN_WT}/.wt-meta" 2>/dev/null | head -1 | cut -d= -f2- || true)
assert_eq "no base_branch" "" "$open_base"

section "wt open — .wt-meta description is branch name"
open_desc=$(grep "^description=" "${OPEN_WT}/.wt-meta" | head -1 | cut -d= -f2-)
assert_eq "description is branch name" "feature/open-test" "$open_desc"

section "wt open — worktree is on the correct branch"
open_head=$(git -C "$OPEN_WT" symbolic-ref --short HEAD 2>/dev/null)
assert_eq "worktree HEAD is feature/open-test" "feature/open-test" "$open_head"

section "wt open — feature file is present in worktree"
assert_file_exists "feature.txt in worktree" "${OPEN_WT}/feature.txt"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: FAIL — `Unknown command: 'open'`

- [ ] **Step 3: Commit**

```
test(open): add wt open happy-path tests
```

---

### Task 2: Tests for `wt open` — error cases

**Files:**
- Modify: `bin/wt-test`

- [ ] **Step 1: Write tests for `wt open` error cases**

Append after Task 1's tests:

```bash
section "wt open — nonexistent branch errors"
open_noexist=$(wt open "nonexistent/branch" 2>&1 || true)
assert_contains "nonexistent branch error" "does not exist" "$open_noexist"

section "wt open — no argument errors"
open_noarg=$(wt open 2>&1 || true)
assert_contains "no-arg shows usage" "Usage:" "$open_noarg"

section "wt open — branch already checked out errors"
git -C "$REPO" checkout -q "feature/open-test"
open_checkedout=$(wt open "feature/open-test" 2>&1 || true)
assert_contains "already checked out error" "already checked out" "$open_checkedout"
git -C "$REPO" checkout -q main
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Commit**

```
test(open): add wt open error-case tests
```

---

### Task 3: Tests for `wt close` — happy path

**Files:**
- Modify: `bin/wt-test`

- [ ] **Step 1: Write tests for `wt close` happy path**

Append after Task 2's tests:

```bash
section "wt close — removes open worktree"
# OPEN_WT still exists from wt open tests above
cd "$OPEN_WT"
close_stdout=$(wt close 2>/dev/null)
assert_dir_not_exists "worktree removed" "$OPEN_WT"

section "wt close — branch still exists after close"
branch_exists=$(git -C "$REPO" rev-parse --verify "feature/open-test" 2>/dev/null && echo "yes" || echo "no")
assert_eq "branch still exists" "yes" "$branch_exists"

section "wt close — stdout is main worktree path"
assert_eq "stdout is main worktree" "$REPO" "$close_stdout"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: FAIL — `Unknown command: 'close'`

- [ ] **Step 3: Commit**

```
test(close): add wt close happy-path tests
```

---

### Task 4: Tests for `wt close` — error cases and guards

**Files:**
- Modify: `bin/wt-test`

- [ ] **Step 1: Write tests for `wt close` errors and guards on existing commands**

Append after Task 3's tests:

```bash
section "wt close — refuses on managed worktree"
cd "$REPO"
git -C "$REPO" checkout -q main
wt new "close guard test" 2>/dev/null
CLOSE_GUARD_WT="${REPO}/.worktrees/close-guard-test"
cd "$CLOSE_GUARD_WT"
close_managed=$(wt close 2>&1 || true)
assert_contains "close refuses managed worktree" "managed worktree" "$close_managed"

section "wt close — refuses from main checkout"
cd "$REPO"
close_main=$(wt close 2>&1 || true)
assert_contains "close refuses main checkout" "not a worktree" "$close_main"

section "wt finish — refuses on open worktree"
# Create a fresh open worktree for guard tests
git -C "$REPO" checkout -q -b feature/guard-test
echo "guard" > "$REPO/guard.txt"
git -C "$REPO" add guard.txt
git -C "$REPO" commit -q -m "guard commit"
git -C "$REPO" checkout -q main
GUARD_WT="${REPO}/.worktrees/feature-guard-test"
wt open "feature/guard-test" 2>/dev/null
cd "$GUARD_WT"
finish_open=$(wt finish 2>&1 || true)
assert_contains "finish refuses open worktree" "open worktree" "$finish_open"
assert_contains "finish suggests wt close" "wt close" "$finish_open"

section "wt abandon — refuses on open worktree"
cd "$GUARD_WT"
abandon_open=$(wt abandon --yes 2>&1 || true)
assert_contains "abandon refuses open worktree" "open worktree" "$abandon_open"
assert_contains "abandon suggests wt close" "wt close" "$abandon_open"

section "wt sync — refuses on open worktree"
cd "$GUARD_WT"
sync_open=$(wt sync 2>&1 || true)
assert_contains "sync refuses open worktree" "open worktree" "$sync_open"
assert_contains "sync suggests wt close" "wt close" "$sync_open"

section "wt retarget — refuses on open worktree"
cd "$GUARD_WT"
retarget_open=$(wt retarget main 2>&1 || true)
assert_contains "retarget refuses open worktree" "open worktree" "$retarget_open"
assert_contains "retarget suggests wt close" "wt close" "$retarget_open"

# Cleanup guard test worktrees
cd "$REPO"
git -C "$REPO" worktree remove "$GUARD_WT" --force 2>/dev/null || true
git -C "$REPO" worktree remove "$CLOSE_GUARD_WT" --force 2>/dev/null || true
git -C "$REPO" branch -D "wt/close-guard-test" 2>/dev/null || true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Commit**

```
test(open/close): add wt close error cases and guard tests
```

---

### Task 5: Tests for `wt go` and `wt list` with open worktrees

**Files:**
- Modify: `bin/wt-test`

- [ ] **Step 1: Write tests for `wt go` and `wt list` integration**

Append after Task 4's tests:

```bash
section "wt open + wt go — navigate by branch name"
cd "$REPO"
git -C "$REPO" checkout -q -b feature/go-open-test
echo "go" > "$REPO/go.txt"
git -C "$REPO" add go.txt
git -C "$REPO" commit -q -m "go commit"
git -C "$REPO" checkout -q main
GO_OPEN_WT="${REPO}/.worktrees/feature-go-open-test"
wt open "feature/go-open-test" 2>/dev/null
go_open_stdout=$(wt go "feature/go-open-test" 2>/dev/null) || true
assert_eq "wt go finds open worktree by branch" "$GO_OPEN_WT" "$go_open_stdout"

section "wt open + wt go — navigate by slug"
go_open_slug=$(wt go "feature-go-open-test" 2>/dev/null) || true
assert_eq "wt go finds open worktree by slug" "$GO_OPEN_WT" "$go_open_slug"

section "wt open + wt list — shows open worktree"
list_out=$(wt list 2>/dev/null)
assert_contains "list shows open worktree branch" "feature/go-open-test" "$list_out"

# Cleanup
cd "$REPO"
git -C "$REPO" worktree remove "$GO_OPEN_WT" --force 2>/dev/null || true
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Commit**

```
test(open): add wt go and wt list integration tests for open worktrees
```

---

### Task 6: Implement `cmd_open()`

**Files:**
- Modify: `bin/wt:268` (insert `cmd_open()` before `cmd_new()`)

- [ ] **Step 1: Implement `cmd_open()`**

Insert before `cmd_new()` (line 268) in `bin/wt`:

```bash
# wt open <branch> — check out an existing branch into a worktree
cmd_open() {
  local branch=""

  for arg in "$@"; do
    case "$arg" in
      -*) error "Unknown flag: $arg" ;;
      *) [[ -z "$branch" ]] && branch="$arg" \
           || error "Usage: wt open <branch>" ;;
    esac
  done

  [[ -z "$branch" ]] && error "Usage: wt open <branch>"

  # Resolve project root
  local project_root
  project_root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || error "Not inside a git repository. Run from inside a project."

  # If inside a worktree, redirect to actual project root
  if [[ -f "${project_root}/.git" ]]; then
    project_root=$(get_main_worktree) \
      || error "Could not resolve main worktree path"
  fi

  # Validate branch exists locally
  git -C "$project_root" rev-parse --verify "$branch" &>/dev/null \
    || error "Branch '${branch}' does not exist locally. Run 'git fetch' first?"

  # Validate branch is not already checked out
  local checked_out
  checked_out=$(git -C "$project_root" worktree list --porcelain 2>/dev/null \
    | grep "^branch refs/heads/${branch}$" || true)
  [[ -n "$checked_out" ]] \
    && error "Branch '${branch}' is already checked out in another worktree."

  # Slugify the branch name for the worktree directory
  local slug
  slug=$(slugify "$branch")
  [[ -z "$slug" ]] && error "Could not generate a slug from branch name: '$branch'"

  local worktree_path="${project_root}/${WORKTREES_DIR}/${slug}"

  # Conflict check
  [[ -d "$worktree_path" ]] && error "Worktree directory already exists: $worktree_path"

  local project_name
  project_name=$(basename "$project_root")

  local created
  created=$(date '+%Y-%m-%dT%H:%M:%S')

  _register_project "$project_root"

  mkdir -p "${project_root}/${WORKTREES_DIR}"

  # Exclude .worktrees/ from git status
  mkdir -p "${project_root}/.git/info"
  if ! grep -qxF ".worktrees/" "${project_root}/.git/info/exclude" 2>/dev/null; then
    echo ".worktrees/" >> "${project_root}/.git/info/exclude"
  fi

  info "Opening worktree: ${BOLD}${project_name}/.worktrees/${slug}${RESET}"
  info "Branch: ${BOLD}${branch}${RESET}"

  git -C "$project_root" worktree add "$worktree_path" "$branch" >&2 \
    || error "Failed to create git worktree"

  # Write .wt-meta with type=open (no base_branch)
  cat > "${worktree_path}/${META_FILE}" <<EOF
type=open
branch=${branch}
created=${created}
description=${branch}
project=${project_name}
project_root=${project_root}
slug=${slug}
EOF

  # Exclude .wt-meta from git status
  local common_dir
  common_dir=$(git -C "$worktree_path" rev-parse --git-common-dir 2>/dev/null || echo "")
  if [[ -n "$common_dir" ]]; then
    mkdir -p "${common_dir}/info"
    if ! grep -qxF ".wt-meta" "${common_dir}/info/exclude" 2>/dev/null; then
      echo ".wt-meta" >> "${common_dir}/info/exclude"
    fi
  fi

  success "Worktree opened: ${worktree_path}"

  echo "$worktree_path"
}
```

- [ ] **Step 2: Add `open` and `close` to `main()` dispatch (line ~1441)**

In the `case` block in `main()`, add:

```bash
    open)           cmd_open "$@" ;;
    close)          cmd_close "$@" ;;
```

- [ ] **Step 3: Run the `wt open` tests to check progress**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -30`
Expected: `wt open` happy-path and error-case tests PASS; `wt close` tests still FAIL

- [ ] **Step 4: Commit**

```
feat(open): implement wt open command
```

---

### Task 7: Implement `cmd_close()`

**Files:**
- Modify: `bin/wt` (insert `cmd_close()` after `cmd_open()`)

- [ ] **Step 1: Implement `cmd_close()`**

Insert after `cmd_open()` in `bin/wt`:

```bash
# wt close — remove an open worktree (branch stays as-is)
cmd_close() {
  local force=0
  for arg in "$@"; do
    case "$arg" in
      --force) force=1 ;;
      -*) error "Unknown flag: $arg" ;;
    esac
  done

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) \
    || error "Not inside a git repository"

  [[ -d "${repo_root}/.git" ]] \
    && error "You are in the main checkout, not a worktree."

  local meta_file="${repo_root}/${META_FILE}"
  [[ -f "$meta_file" ]] \
    || error "No ${META_FILE} found."

  local wt_type branch project project_root slug
  wt_type=$(read_meta "$meta_file" "type")
  branch=$(read_meta "$meta_file" "branch")
  project=$(read_meta "$meta_file" "project")
  project_root=$(read_meta "$meta_file" "project_root")
  slug=$(read_meta "$meta_file" "slug")

  [[ "$wt_type" != "open" ]] \
    && error "This is a managed worktree. Use 'wt finish' or 'wt abandon' instead."

  info "Worktree: ${BOLD}${branch}${RESET}"

  # Safety: uncommitted tracked changes
  local tracked_changes
  tracked_changes=$(git diff --name-only 2>/dev/null || true)
  local staged_changes
  staged_changes=$(git diff --cached --name-only 2>/dev/null || true)
  if [[ -n "$tracked_changes" || -n "$staged_changes" ]]; then
    if (( force == 0 )); then
      error "Uncommitted changes in worktree. Use --force to override."
    fi
    warn "Discarding uncommitted changes (--force)."
  fi

  # Safety: untracked files
  local untracked
  untracked=$(git ls-files --others --exclude-standard 2>/dev/null || true)
  if [[ -n "$untracked" ]]; then
    if (( force == 0 )); then
      error "Untracked files in worktree. Use --force to override."
    fi
    warn "Discarding untracked files (--force)."
  fi

  local main_wt
  main_wt=$(get_main_worktree) \
    || error "Could not resolve main worktree path"

  info "Removing worktree..."
  git -C "$main_wt" worktree remove "$repo_root" --force >&2 \
    || warn "Could not auto-remove worktree dir. Run: rm -rf ${repo_root}"

  # Auto-unregister project if no worktrees remain
  if [[ -n "$project_root" ]]; then
    local has_wts=0
    if [[ -d "${project_root}/${WORKTREES_DIR}" ]]; then
      for wt_dir in "${project_root}/${WORKTREES_DIR}"/*/; do
        [[ -d "$wt_dir" ]] && has_wts=1 && break
      done
    fi
    local wt_branch_count
    wt_branch_count=$(git -C "$project_root" branch --list 'wt/*' 2>/dev/null | wc -l | tr -d ' ')
    if (( has_wts == 0 && wt_branch_count == 0 )); then
      _unregister_project "$project_root"
    fi
  fi

  success "Worktree closed. Branch '${branch}' is untouched."

  if [[ -n "${TMUX:-}" ]]; then
    echo -e "\n  ${BOLD}You can now close this tmux window.${RESET}\n" >&2
  fi

  echo "$main_wt"
}
```

- [ ] **Step 2: Run tests to check `wt close` passes**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -30`
Expected: `wt close` happy-path tests PASS; guard tests still FAIL

- [ ] **Step 3: Commit**

```
feat(close): implement wt close command
```

---

### Task 8: Add guard clauses to `finish`, `abandon`, `sync`, `retarget`

**Files:**
- Modify: `bin/wt` — `cmd_finish()` (~line 590), `cmd_abandon()` (~line 800), `cmd_sync()` (~line 680), `cmd_retarget()` (~line 390)

- [ ] **Step 1: Add guard to `cmd_finish()`**

After reading `.wt-meta` fields (after `branch=$(read_meta "$meta_file" "branch")`), add:

```bash
  local wt_type
  wt_type=$(read_meta "$meta_file" "type")
  [[ "$wt_type" == "open" ]] \
    && error "This is an open worktree. Use 'wt close' to remove it."
```

- [ ] **Step 2: Add guard to `cmd_abandon()`**

After reading `.wt-meta` fields (after `branch=$(read_meta "$meta_file" "branch")`), add:

```bash
  local wt_type
  wt_type=$(read_meta "$meta_file" "type")
  [[ "$wt_type" == "open" ]] \
    && error "This is an open worktree. Use 'wt close' to remove it."
```

- [ ] **Step 3: Add guard to `cmd_sync()`**

After reading `.wt-meta` fields (after `branch=$(read_meta "$meta_file" "branch")`), add:

```bash
  local wt_type
  wt_type=$(read_meta "$meta_file" "type")
  [[ "$wt_type" == "open" ]] \
    && error "This is an open worktree. Use 'wt close' to remove it."
```

- [ ] **Step 4: Add guard to `cmd_retarget()`**

After reading `.wt-meta` fields (after `description=$(read_meta "$meta_file" "description")`), add:

```bash
  local wt_type
  wt_type=$(read_meta "$meta_file" "type")
  [[ "$wt_type" == "open" ]] \
    && error "This is an open worktree. Use 'wt close' to remove it."
```

- [ ] **Step 5: Run full test suite**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -30`
Expected: ALL tests PASS

- [ ] **Step 6: Commit**

```
feat(open/close): add type=open guards to finish, abandon, sync, retarget
```

---

### Task 9: Update `wt list` to show `[open]` marker

**Files:**
- Modify: `bin/wt` — `cmd_list()` (~line 1078)

- [ ] **Step 1: Write test for `[open]` marker in `wt list`**

In the Task 5 tests (the `wt open + wt list` section), add after the existing `assert_contains`:

```bash
assert_contains "list shows [open] marker" "[open]" "$list_out"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash bin/wt-test < /dev/null 2>&1 | grep -A2 "open.*marker"`
Expected: FAIL

- [ ] **Step 3: Modify `cmd_list()` to show `[open]` marker**

In `cmd_list()`, after reading the `.wt-meta` fields (around line 1054), add:

```bash
    local wt_type
    wt_type=$(read_meta "$meta_file" "type")
```

Then modify the `printf` line (~line 1078) to append the marker. Change:

```bash
      printf "  ${CYAN}%-40s${RESET}  ${BOLD}%8s${RESET}  ${dirty_color}%-10s${RESET}  %-8s  %s\n" \
        "$branch" "${ahead} ahead" "$dirty_label" "$age" "\"${description}\""
```

To:

```bash
      local type_label=""
      [[ "$wt_type" == "open" ]] && type_label="  ${YELLOW}[open]${RESET}"

      printf "  ${CYAN}%-40s${RESET}  ${BOLD}%8s${RESET}  ${dirty_color}%-10s${RESET}  %-8s  %s%s\n" \
        "$branch" "${ahead} ahead" "$dirty_label" "$age" "\"${description}\"" "$type_label"
```

Note: for open worktrees with no `base_branch`, the `ahead` count (`git rev-list --count "${base_branch}..HEAD"`) will fail. Change the `ahead` computation (~line 1064) to handle empty `base_branch`:

```bash
      local ahead="–"
      if [[ -n "$base_branch" ]]; then
        ahead=$(git -C "$wt_dir" rev-list --count "${base_branch}..HEAD" 2>/dev/null || echo "?")
      fi
```

And adjust the formatted output — when `ahead` is `–`, show `–` instead of `– ahead`:

```bash
      local ahead_label="${ahead} ahead"
      [[ "$ahead" == "–" ]] && ahead_label="–"
```

- [ ] **Step 4: Run full test suite**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: ALL tests PASS

- [ ] **Step 5: Commit**

```
feat(list): show [open] marker and handle missing base_branch
```

---

### Task 10: Update help text, shell wrapper comment, and command dispatch

**Files:**
- Modify: `bin/wt` — comment block (lines 2–71), `cmd_help()` (lines 205–264), shell wrapper (lines 35–52)

- [ ] **Step 1: Update the header comment block**

Add after line 18 (`wt go`):

```
#   wt open <branch>                           Check out an existing branch into a worktree
#   wt close [--force]                         Remove an open worktree (branch stays)
```

- [ ] **Step 2: Update the shell wrapper comment**

The wrapper needs `open` and `close` added to the commands that return paths. Change both zsh and bash wrappers from:

```bash
if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" || "$1" == "go" ]]; then
```

To:

```bash
if [[ "$1" == "new" || "$1" == "finish" || "$1" == "abandon" || "$1" == "go" || "$1" == "open" || "$1" == "close" ]]; then
```

- [ ] **Step 3: Update `cmd_help()`**

In the USAGE section, add after `wt go`:

```
  wt open <branch>                           Check out an existing branch into a worktree
  wt close [--force]                         Remove an open worktree (branch stays)
```

In the EXAMPLES section, add:

```
  # Check out an existing feature branch into a worktree:
  wt open feature/my-branch

  # Remove an open worktree (branch stays as-is):
  wt close
```

In the NOTES section, add:

```
  • `wt open` checks out an existing branch — no intermediate wt/ branch created
  • `wt close` removes the worktree but leaves the branch untouched
  • Open worktrees cannot use finish/abandon/sync/retarget — use close instead
```

- [ ] **Step 4: Write test for help output**

Append to test file:

```bash
section "wt help — includes open and close"
help_open=$(wt help 2>&1)
assert_contains "help lists wt open" "wt open" "$help_open"
assert_contains "help lists wt close" "wt close" "$help_open"
```

- [ ] **Step 5: Run full test suite**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: ALL tests PASS

- [ ] **Step 6: Commit**

```
docs(open/close): update help text and shell wrapper comment
```

---

### Task 11: Update zsh completion

**Files:**
- Modify: `config/wt-completion.zsh`

- [ ] **Step 1: Add `open` and `close` to subcommands array**

In the `subcommands` array (~line 62), add:

```zsh
    'open:check out an existing branch into a worktree'
    'close:remove an open worktree (branch stays)'
```

- [ ] **Step 2: Add completion for `open` arguments**

In the `args` case block (~line 86), add:

```zsh
        open)
          local -a localbranches
          localbranches=( ${(f)"$(git branch --format='%(refname:short)' 2>/dev/null)"} )
          _describe 'local branch' localbranches
          ;;
        close)
          _arguments '--force[override safety gates]'
          ;;
```

- [ ] **Step 3: Commit**

```
feat(completion): add wt open and wt close to zsh completion
```

---

### Task 12: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `CONTRIBUTING.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README.md**

Add `wt open` and `wt close` to the command reference table. Add a usage example showing the parallel feature-branch workflow.

- [ ] **Step 2: Update CONTRIBUTING.md**

Add mention of the `type` field in `.wt-meta` and the open/managed distinction.

- [ ] **Step 3: Update CLAUDE.md**

Update the project description line count. Add `open`/`close` to the command summary. Update the shell wrapper example to include `open` and `close`.

- [ ] **Step 4: Run full test suite one final time**

Run: `bash bin/wt-test < /dev/null 2>&1 | tail -20`
Expected: ALL tests PASS

- [ ] **Step 5: Commit**

```
docs: update README, CONTRIBUTING, and CLAUDE.md for wt open/close
```
