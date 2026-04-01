# wt open improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `wt open` support multiple worktrees from the same branch (via description param) and list branches when called with no args.

**Architecture:** Extend `cmd_open()` to accept an optional description argument (mirrors `wt new`). Add a branch-listing mode when no args are given. Update tests, help text, header comment, and docs.

**Tech Stack:** Bash 4+, git

---

### Task 1: Test — `wt open` with no args lists branches

**Files:**
- Modify: `bin/wt-test` (before the `# ─── Summary` section, ~line 2132)

- [ ] **Step 1: Write the failing test**

Append before the Summary section in `bin/wt-test`:

```bash
# ── wt open — branch listing ────────────────────────────────────────────────

section "wt open — no args lists local branches"
cd "$REPO"
git -C "$REPO" checkout -q main
open_list=$(wt open 2>&1 || true)
# main branch should appear in listing
assert_contains "lists main branch" "main" "$open_list"
# feature branches created earlier should appear
assert_contains "lists feature branch" "feature/open-test" "$open_list"
# wt/* branches should NOT appear
assert_not_contains "excludes wt/ branches" "wt/" "$open_list"

section "wt open — no args shows remote branches"
# Create a remote to test remote branch listing
git -C "$REPO" remote add fake-origin "$REPO" 2>/dev/null || true
git -C "$REPO" fetch fake-origin --quiet 2>/dev/null || true
open_list_remote=$(wt open 2>&1 || true)
assert_contains "lists remote branch" "fake-origin/" "$open_list_remote"

section "wt open — no args exits non-zero (no cd)"
wt open > /dev/null 2>&1 || open_exit=$?
assert_eq "exit code is non-zero" "1" "${open_exit:-0}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash bin/wt-test < /dev/null`
Expected: FAIL — current code errors with "Usage:" on no args

- [ ] **Step 3: Implement branch listing in `cmd_open()`**

In `bin/wt`, replace the no-arg error line in `cmd_open()` (line 284):

```bash
  [[ -z "$branch" ]] && error "Usage: wt open <branch>"
```

With:

```bash
  # No args: list available branches and exit
  if [[ -z "$branch" ]]; then
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null) \
      || error "Not inside a git repository."
    if [[ -f "${project_root}/.git" ]]; then
      project_root=$(get_main_worktree) \
        || error "Could not resolve main worktree path"
    fi

    info "Local branches:"
    git -C "$project_root" branch 2>/dev/null \
      | sed 's/^[* ]*/  /' \
      | grep -v '^ *wt/' >&2

    local remotes
    remotes=$(git -C "$project_root" branch -r 2>/dev/null \
      | sed 's/^[* ]*/  /' \
      | grep -v ' -> ' \
      | grep -v '^ *[^ ]*/HEAD' \
      | grep -v 'wt/' || true)
    if [[ -n "$remotes" ]]; then
      echo "" >&2
      info "Remote branches:"
      echo "$remotes" >&2
    fi

    echo "" >&2
    info "Usage: wt open <branch> [\"description\"]"
    exit 1
  fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash bin/wt-test < /dev/null`
Expected: PASS

- [ ] **Step 5: Commit**

```
feat(open): list branches when called with no args
```

---

### Task 2: Test — `wt open <branch> "description"` creates worktree with custom slug

**Files:**
- Modify: `bin/wt-test` (append before Summary section)

- [ ] **Step 1: Write the failing test**

Append before the Summary section in `bin/wt-test`:

```bash
# ── wt open — description parameter ─────────────────────────────────────────

section "wt open — with description uses description as slug"
cd "$REPO"
git -C "$REPO" checkout -q main
DESC_WT="${REPO}/.worktrees/custom-slug-name"
desc_stdout=$(wt open "feature/open-test" "custom slug name" 2>/dev/null)
assert_eq "stdout is worktree path" "$DESC_WT" "$desc_stdout"
assert_dir_exists "worktree dir created with description slug" "$DESC_WT"

section "wt open — description: branch is wt/<description-slug>"
desc_head=$(git -C "$DESC_WT" symbolic-ref --short HEAD 2>/dev/null)
assert_eq "branch is wt/custom-slug-name" "wt/custom-slug-name" "$desc_head"

section "wt open — description: .wt-meta has correct base_branch"
desc_base=$(grep "^base_branch=" "${DESC_WT}/.wt-meta" 2>/dev/null | head -1 | cut -d= -f2- || true)
assert_eq "base_branch is feature/open-test" "feature/open-test" "$desc_base"

section "wt open — description: .wt-meta description is the provided description"
desc_desc=$(grep "^description=" "${DESC_WT}/.wt-meta" 2>/dev/null | head -1 | cut -d= -f2- || true)
assert_eq "description is custom slug name" "custom slug name" "$desc_desc"

section "wt open — description: feature file is present"
assert_file_exists "feature.txt in description worktree" "${DESC_WT}/feature.txt"

section "wt open — second worktree from same branch with different description"
DESC_WT2="${REPO}/.worktrees/another-worktree"
desc2_stdout=$(wt open "feature/open-test" "another worktree" 2>/dev/null)
assert_eq "stdout is second worktree path" "$DESC_WT2" "$desc2_stdout"
assert_dir_exists "second worktree dir created" "$DESC_WT2"
desc2_head=$(git -C "$DESC_WT2" symbolic-ref --short HEAD 2>/dev/null)
assert_eq "second branch is wt/another-worktree" "wt/another-worktree" "$desc2_head"

# Cleanup
cd "$REPO"
git -C "$REPO" worktree remove "$DESC_WT" --force 2>/dev/null || true
git -C "$REPO" branch -D "wt/custom-slug-name" 2>/dev/null || true
git -C "$REPO" worktree remove "$DESC_WT2" --force 2>/dev/null || true
git -C "$REPO" branch -D "wt/another-worktree" 2>/dev/null || true
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash bin/wt-test < /dev/null`
Expected: FAIL — current `cmd_open` treats the second arg as an error ("Usage: wt open <branch>")

- [ ] **Step 3: Implement description parameter in `cmd_open()`**

In `bin/wt`, modify the argument parsing at the top of `cmd_open()` (lines 274-284). Replace:

```bash
  local branch=""

  for arg in "$@"; do
    case "$arg" in
      -*) error "Unknown flag: $arg" ;;
      *) [[ -z "$branch" ]] && branch="$arg" \
           || error "Usage: wt open <branch>" ;;
    esac
  done
```

With:

```bash
  local branch="" description=""

  for arg in "$@"; do
    case "$arg" in
      -*) error "Unknown flag: $arg" ;;
      *)
        if [[ -z "$branch" ]]; then
          branch="$arg"
        elif [[ -z "$description" ]]; then
          description="$arg"
        else
          error "Usage: wt open <branch> [\"description\"]"
        fi
        ;;
    esac
  done
```

Then modify the slug/branch-name logic (lines 302-310). Replace:

```bash
  # Slugify the branch name for the worktree directory
  # Replace / with space first so slugify converts them to hyphens
  local slug
  slug=$(slugify "${branch//\// }")
  [[ -z "$slug" ]] && error "Could not generate a slug from branch name: '$branch'"

  local worktree_path="${project_root}/${WORKTREES_DIR}/${slug}"

  # Conflict check
  [[ -d "$worktree_path" ]] && error "Worktree directory already exists: $worktree_path"
```

With:

```bash
  # Slugify: use description if provided, otherwise branch name
  local slug
  if [[ -n "$description" ]]; then
    slug=$(slugify "$description")
  else
    # Replace / with space first so slugify converts them to hyphens
    slug=$(slugify "${branch//\// }")
  fi
  [[ -z "$slug" ]] && error "Could not generate a slug from '${description:-$branch}'"

  local worktree_path="${project_root}/${WORKTREES_DIR}/${slug}"

  # Conflict check
  [[ -d "$worktree_path" ]] && error "Worktree directory already exists: $worktree_path"
```

Then update the `.wt-meta` description field (line 344). Replace:

```bash
description=${branch}
```

With:

```bash
description=${description:-${branch}}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash bin/wt-test < /dev/null`
Expected: PASS (all tests including existing ones)

- [ ] **Step 5: Commit**

```
feat(open): support optional description for custom slug
```

---

### Task 3: Update existing test for no-arg behavior

**Files:**
- Modify: `bin/wt-test` (~line 2032-2034)

The existing test at line 2032 asserts `wt open` with no args shows "Usage:". The new behavior shows a branch list plus usage hint. The test uses `assert_contains "Usage:"` which should still pass since we print the usage hint. Verify this.

- [ ] **Step 1: Run full test suite**

Run: `bash bin/wt-test < /dev/null`
Expected: PASS — the existing no-arg test should still pass because the new output includes "Usage:"

- [ ] **Step 2: If the test fails, update the assertion**

If needed, update line 2034 to match new output. Likely no change needed.

---

### Task 4: Update help text and header comment

**Files:**
- Modify: `bin/wt` — header comment (line 18), `cmd_help()` (line 219), examples (line 250)

- [ ] **Step 1: Update header comment**

In `bin/wt`, line 18, replace:

```
#   wt open <branch>                             Create a worktree branching off an existing branch
```

With:

```
#   wt open [<branch>] ["description"]           List branches, or create worktree off existing branch
```

- [ ] **Step 2: Update `cmd_help()` usage line**

In `bin/wt`, line 219, replace:

```
  wt open <branch>                            Create a worktree branching off an existing branch
```

With:

```
  wt open                                     List available branches
  wt open <branch> ["description"]            Create a worktree branching off an existing branch
```

- [ ] **Step 3: Update `cmd_help()` examples**

In `bin/wt`, after line 250 (`wt open feature/my-branch`), add:

```

  # Create a second worktree from the same branch with a custom name:
  wt open feature/my-branch "fix the login bug"

  # List available branches to open:
  wt open
```

- [ ] **Step 4: Update `cmd_help()` notes**

In `bin/wt`, line 267, replace:

```
  • `wt open` creates a wt/<slug> branch off an existing branch — full lifecycle (finish/abandon/sync) works
```

With:

```
  • `wt open <branch>` creates a wt/<slug> branch off an existing branch — full lifecycle works
  • `wt open <branch> "description"` uses description for the slug (allows multiple worktrees from one branch)
  • `wt open` with no args lists available local and remote branches
```

- [ ] **Step 5: Run tests**

Run: `bash bin/wt-test < /dev/null`
Expected: PASS — help test at line 2123 asserts `help lists wt open` which should still match

- [ ] **Step 6: Commit**

```
docs(open): update help text for new open modes
```

---

### Task 5: Update documentation files

**Files:**
- Modify: `README.md`
- Modify: `docs/DEVELOPMENT.md`
- Modify: `CONTRIBUTING.md`

- [ ] **Step 1: Update README.md**

Update the `wt open` entry in the command reference to show the new signature and describe both modes (branch listing, description parameter). Add an example for creating multiple worktrees from the same branch.

- [ ] **Step 2: Update docs/DEVELOPMENT.md**

Update the architecture/internals section for `cmd_open()` to mention the two new modes: no-arg branch listing and description-based slug.

- [ ] **Step 3: Update CONTRIBUTING.md**

No changes expected unless the contributor workflow references `wt open` specifically. Check and update if needed.

- [ ] **Step 4: Run tests**

Run: `bash bin/wt-test < /dev/null`
Expected: PASS

- [ ] **Step 5: Commit**

```
docs: update README, DEVELOPMENT, CONTRIBUTING for wt open changes
```

---

### Task 6: Verify stdout contract for `cd` behavior

**Files:**
- Modify: `bin/wt-test` (append before Summary section)

- [ ] **Step 1: Write test verifying stdout-only contract**

Append before Summary section in `bin/wt-test`:

```bash
# ── wt open — stdout contract ───────────────────────────────────────────────

section "wt open — stdout is ONLY the worktree path (no UI noise)"
cd "$REPO"
git -C "$REPO" checkout -q main
git -C "$REPO" checkout -q -b feature/stdout-contract-test
echo "stdout test" > "$REPO/stdout-test.txt"
git -C "$REPO" add stdout-test.txt
git -C "$REPO" commit -q -m "stdout contract test"
git -C "$REPO" checkout -q main
STDOUT_WT="${REPO}/.worktrees/feature-stdout-contract-test"
stdout_out=$(wt open "feature/stdout-contract-test" 2>/dev/null)
# stdout should be exactly one line: the path
stdout_lines=$(echo "$stdout_out" | wc -l | tr -d ' ')
assert_eq "stdout is exactly 1 line" "1" "$stdout_lines"
assert_eq "stdout is worktree path" "$STDOUT_WT" "$stdout_out"

# Cleanup
cd "$REPO"
git -C "$REPO" worktree remove "$STDOUT_WT" --force 2>/dev/null || true
git -C "$REPO" branch -D "wt/feature-stdout-contract-test" 2>/dev/null || true
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash bin/wt-test < /dev/null`
Expected: PASS — `cmd_open` already prints only the path to stdout (line 363), all UI goes to stderr

- [ ] **Step 3: Commit**

```
test(open): verify stdout contract for shell wrapper cd
```
