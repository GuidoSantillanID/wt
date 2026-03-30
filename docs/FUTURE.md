# Future Directions

Ideas that are well-understood but deliberately deferred. Captured here to avoid re-litigating them and to give future contributors a starting point.

---

## A. `wt` as a superpowers skill

### What

Replace (or supplement) the `using-git-worktrees` skill in the [superpowers plugin](https://github.com/anthropics/claude-code-superpowers) with a custom skill that calls `wt new` / `wt finish` instead of raw `git worktree add`. The skill would teach agents to use `wt` as their worktree interface.

### Context: what superpowers does today

The `using-git-worktrees` skill calls `git worktree add <path> -b <branch>` directly. This works but produces raw worktrees with none of `wt`'s metadata:

- No `.wt-meta` (base branch, description, project, slug)
- No project registry entry (`wt list` / `wt doctor` don't see the worktree)
- No dependency handling
- Branch name chosen ad-hoc, not namespaced under `wt/`
- Cleanup requires manual `git worktree remove` + `git branch -D`

The pipeline is: `brainstorming` → `writing-plans` → `executing-plans` (calls `using-git-worktrees` to isolate work) → `finishing-a-development-branch` (cleanup).

### What agents would gain from `wt`

| Feature | Raw `git worktree add` | `wt new` |
|---|---|---|
| `.wt-meta` metadata | ✗ | ✓ |
| Project registry | ✗ | ✓ |
| `wt list` / `wt doctor` awareness | ✗ | ✓ |
| Namespaced `wt/<slug>` branch | ✗ | ✓ |
| Dependency hint | ✗ | ✓ (generic reminder) |
| Rebase finish strategy | ✗ | `wt finish` |
| Clean `wt abandon` (abandon) path | ✗ | ✓ |

### Command mapping

| Superpowers today | `wt` equivalent |
|---|---|
| `git worktree add <path> -b <branch>` | `wt new "<description>"` |
| `git worktree remove` + `git branch -D` | `wt abandon` |
| (no equivalent) | `wt finish` (rebase + ff + cleanup) |

### Implementation sketch

A skill file (e.g. `skills/using-wt-worktrees.md`) would replace or extend `using-git-worktrees`. Key differences:

1. **Creation**: call `wt new "<description>"` instead of `git worktree add`. Path is printed to stdout; agent `cd`s into it.
2. **Finishing**: call `wt finish --yes` (or `wt abandon --yes` to abandon). The `--yes` flag skips interactive confirms, safe for agent use.
3. **CLAUDE.md integration**: the skill instructs agents to install `wt` and configure the shell wrapper (`function wt()` in `.zshrc`) as a prerequisite.

**Shell wrapper constraint**: `wt new` prints the worktree path to stdout for the shell wrapper to `cd` into. Agents don't have a shell wrapper — they need to capture stdout and `cd` explicitly:

```bash
worktree_path=$(command wt new "fix the login bug")
cd "$worktree_path"
```

This is a minor friction point but straightforward to document in the skill.

### Risks

- Couples to superpowers plugin release cadence — any `using-git-worktrees` updates need to be mirrored
- Requires `wt` installed on the machine where the agent runs (not guaranteed in CI or remote containers)
- Most `wt` features (registry, `wt list`, `wt doctor`) are human-facing — agents don't benefit from them directly
- Adds a new dependency for the simplest use case (raw worktree isolation)

### Verdict

Worth building if the target audience is developers who already use `wt` daily and want agents to operate within the same worktree ecosystem. Not worth it as a general-purpose replacement for `using-git-worktrees`.

---

## B. Agent orchestration command (`wt agent`)

### What

`wt agent "<task>"` — a new `wt` subcommand that automates the full agent workflow:

1. Creates a worktree (`wt new "<task>"`)
2. Spawns Claude Code in it (via `claude` CLI or a new tmux window/pane)
3. Manages the lifecycle: waits for the agent to signal completion, then runs `wt finish`

### UX

```bash
# Human runs one command
wt agent "add dark mode toggle"

# wt:
# 1. Creates .worktrees/add-dark-mode-toggle (wt new)
# 2. Opens new tmux window, launches: claude --dangerously-skip-permissions
# 3. Agent works in isolation
# 4. Agent signals done (creates .wt-done or calls `wt finish --yes`)
# 5. wt finish --yes runs, rebases, fast-forwards, cleans up
```

### tmux integration

Pairs naturally with the existing `wt new` tmux behavior (new window on creation, reminder to close on finish). `wt agent` would always open a new tmux window, since it's inherently async — the human hands off and moves on.

### "Done" signaling options

| Approach | Pros | Cons |
|---|---|---|
| Agent calls `wt finish --yes` | No polling, agent controls timing | Agent must know to call it; finish may fail |
| Agent creates `.wt-done` marker | Simple, observable | Requires `wt agent` to poll or use `inotify` |
| Agent exits `claude` process | No extra mechanism | Process exit doesn't mean work is clean |

The cleanest approach: agent calls `wt finish --yes` as its final action. `wt agent` just launches the process and trusts the agent to clean up.

### How it differs from the superpowers skill approach

| | Superpowers skill | `wt agent` |
|---|---|---|
| Who controls the loop | Agent (skill instructions) | `wt` (outer shell script) |
| Agent scope | Implementation + lifecycle | Implementation only |
| Human involvement | Per-task approval in CC session | Fire-and-forget |
| tmux | Existing session | Always new window |

### Risks

- Process management complexity: what if `claude` crashes mid-task? What if `wt finish` fails after agent exits?
- Scope creep: `wt` becomes an agent orchestrator, not just a worktree lifecycle tool. These are different jobs.
- Error handling: agent failures need to surface to the human without silently leaving orphaned worktrees.
- Security: `--dangerously-skip-permissions` is required for fully autonomous operation — this is a significant trust decision that the command would make on behalf of the user.

### Open questions

1. Should `wt agent` auto-finish on agent exit, or wait for explicit human review?
2. How to pass context to the agent (plan file, spec, linked issue)?
3. Should it support non-tmux environments (just `claude` in foreground)?
4. How to handle the case where the agent opens a PR instead of calling `wt finish`?

### Verdict

High value for fire-and-forget parallel agent tasks. The right time to build this is when `claude` CLI has a stable `--task-file` or `--prompt-file` flag that makes context passing clean. Until then, the overhead of getting context into the agent (pasting a plan, etc.) limits the benefit.
