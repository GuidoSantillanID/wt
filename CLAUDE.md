# CLAUDE.md

## Running tests

```bash
bash bin/wt-test < /dev/null
bash bin/wt-test --keep < /dev/null   # preserve temp dir on failure
```

Stdin must be closed (`< /dev/null`) or `confirm()` prompts hang. Requires bash 4+.

## Adding a new command

1. Write failing tests in `bin/wt-test` (append before the `# ─── Summary` section)
2. Add `cmd_<name>()` in `bin/wt` (functions are grouped before `main()`)
3. Add dispatch case in `main()` at the bottom of `bin/wt`
4. If the command prints a path to stdout (for the shell wrapper to `cd`), add it to the wrapper comment at the top of `bin/wt`

## Critical rules

**Stdout/stderr contract.** Commands that return paths (`new`, `finish`, `abandon`, `open`, `go`) print ONLY the path to stdout. All UI goes to stderr. `wt list` table goes to stdout. Breaking this breaks the shell wrapper.

**Never eval `.wt-meta`.** Always parse with `read_meta()` (grep+cut). Never `source` or `eval` the file.

## Pitfalls

- `slugify()` strips non-alphanumeric chars. Branch names with `/` need pre-processing (`tr '/' ' '`) before slugifying — see `cmd_open()`.
- `printf %s` does NOT interpret `\033` escape sequences. Color variables (`$YELLOW`, etc.) work in the format string but not as `%s` arguments. Put colors in the format string or use `%b`.
- `git worktree add` with an existing branch uses `<path> <branch>` (no `-b`). With a new branch uses `<path> -b <branch>`. `wt open` uses `-b` to create a new branch off the target.

## TDD

Write failing tests first. Run them. Then implement. Never weaken or delete tests to make them pass.

## Documentation is mandatory

Every change must update all relevant docs:

- `README.md` — command reference and usage examples
- `docs/DEVELOPMENT.md` — architecture and internals
- `CONTRIBUTING.md` — contributor instructions
- Inline help text in `bin/wt` (header comment block and `cmd_help()`)

## wt sync — conflict resolution

`wt sync` is safe to run via Bash tool (exception to the "never run wt commands" rule).

When conflicts occur after `wt sync`:

1. Read every conflicted file (look for `<<<<<<<`/`=======`/`>>>>>>>` markers)
2. If the resolution is clear: resolve it and explain what you did
3. If it requires product/business knowledge: explain both sides and ask
4. `git add <resolved-files>`, then `git rebase --continue`
5. To abort: `git rebase --abort`
