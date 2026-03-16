# Contributing

## Running Tests

```bash
bash bin/wt-test < /dev/null
```

Redirect stdin from `/dev/null` to prevent interactive `confirm()` prompts from blocking the test runner.

Pass `--keep` to preserve the temp directory on failure for debugging:

```bash
bash bin/wt-test --keep < /dev/null
```

Tests require bash 4+ (macOS ships with bash 3.2 — install via `brew install bash`). CI runs on both macOS and Linux.

## Making Changes

- Keep changes focused — one concern per PR
- All tests must pass before submitting
- Follow the existing shell style (`set -euo pipefail`, quoted variables, no `eval`)
- Never use `eval` or `source` `.wt-meta` — parse with `grep | head | cut`
- All UI output goes to stderr; only directory paths and `wt list` table go to stdout (shell wrapper contract)

## Test-Driven Development

This project follows strict TDD. For every bug fix or feature:

1. Write a failing test in `bin/wt-test` that captures the expected behavior
2. Run `bash bin/wt-test < /dev/null` and confirm the test fails for the right reason
3. Write the minimal implementation to make the test pass
4. Run the full suite and confirm all tests pass

Never weaken, skip, or delete tests to make them pass — fix the implementation instead.

## Reporting Issues

Open an issue at https://github.com/GuidoSantillanID/wt/issues with steps to reproduce.
